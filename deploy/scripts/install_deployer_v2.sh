#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Ensure that the exit status of a pipeline command is non-zero if any
# stage of the pipefile has a non-zero exit status.
set -o pipefail

#External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

# Fail on any error, undefined variable, or pipeline failure
set -euo pipefail

# Enable debug mode if DEBUG is set to 'true'
if [[ "${DEBUG:-false}" == 'true' ]]; then
	# Enable debugging
	set -x
	# Exit on error
	set -o errexit
	echo "Environment variables:"
	printenv | sort
fi

# Constants
script_directory="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
readonly script_directory

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

CONFIG_REPO_PATH="${script_directory}/.."
CONFIG_DIR="${CONFIG_REPO_PATH}/.sap_deployment_automation"
readonly CONFIG_DIR

#Internal helper functions
function showhelp {
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo "#                                                                                       #"
	echo "#   This file contains the logic to deploy the deployer.                                #"
	echo "#   The script experts the following exports:                                           #"
	echo "#                                                                                       #"
	echo "#     ARM_SUBSCRIPTION_ID to specify which subscription to deploy to                    #"
	echo "#     SAP_AUTOMATION_REPO_PATH the path to the folder containing the cloned sap-automation        #"
	echo "#                                                                                       #"
	echo "#   The script will persist the parameters needed between the executions in the         #"
	echo "#   [CONFIG_REPO_PATH]/.sap_deployment_automation folder                                #"
	echo "#                                                                                       #"
	echo "#                                                                                       #"
	echo "#   Usage: install_deployer.sh                                                          #"
	echo "#    -p deployer parameter file                                                         #"
	echo "#                                                                                       #"
	echo "#    -i interactive true/false setting the value to false will not prompt before apply  #"
	echo "#    -h Show help                                                                       #"
	echo "#                                                                                       #"
	echo "#   Example:                                                                            #"
	echo "#                                                                                       #"
	echo "#   [REPO-ROOT]deploy/scripts/install_deployer.sh \                                     #"
	echo "#      -p PROD-WEEU-DEP00-INFRASTRUCTURE.json \                                         #"
	echo "#      -i true                                                                          #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
}

# Function to source helper scripts
function source_helper_scripts() {
	local -a helper_scripts=("$@")
	for script in "${helper_scripts[@]}"; do
		if [[ -f "$script" ]]; then
			# shellcheck source=/dev/null
			source "$script"
		else
			echo "Helper script not found: $script"
			exit 1
		fi
	done
}

#process inputs - may need to check the option i for auto approve as it is not used
# Function to parse command line arguments
function parse_arguments() {
	local input_opts
	input_opts=$(getopt -n install_deployer_v2 -o p:ih --longoptions parameter_file:,auto-approve,help -- "$@")
	is_input_opts_valid=$?

	if [[ "${is_input_opts_valid}" != "0" ]]; then
		showhelp
		exit 1
	fi

	eval set -- "$input_opts"
	while true; do
		case "$1" in
		-p | --parameter_file)
			parameter_file_name="$2"
			shift 2
			;;
		-i | --auto-approve)
			approve="--auto-approve"
			shift
			;;
		-h | --help)
			showhelp
			exit 3
			;;
		--)
			shift
			break
			;;
		esac
	done

	if [ ! -f "${parameter_file_name}" ]; then
		printf -v val %-40.40s "$parameter_file_name"
		echo ""
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo "#               Parameter file does not exist: ${val} #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		return 2 #No such file or directory
	fi

  param_dirname=$(dirname "${parameter_file_name}")
  export TF_DATA_DIR="${param_dirname}"/.terraform
	if [ "$param_dirname" != '.' ]; then
		echo ""
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo "#   Please run this command from the folder containing the parameter file               #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		return 3
	fi

	# Check that parameter files have environment and location defined
	if ! validate_key_parameters "$parameter_file_name"; then
		return $?
	fi

	# Check that the exports ARM_SUBSCRIPTION_ID and SAP_AUTOMATION_REPO_PATH are defined
	if ! validate_exports; then
		return $?
	fi

	region=$(echo "${region}" | tr "[:upper:]" "[:lower:]")
	# Convert the region to the correct code
	get_region_code "$region"

	# Check that Terraform and Azure CLI is installed
	if ! validate_dependencies; then
		exit $?
	fi

	return 0
}

function install_deployer() {
	deployment_system=sap_deployer
	approve=""
	# Define an array of helper scripts
	helper_scripts=(
		"${script_directory}/helpers/script_helpers.sh"
		"${script_directory}/deploy_utils.sh"
	)

	# Call the function with the array
	source_helper_scripts "${helper_scripts[@]}"

	# Parse command line arguments
	if parse_arguments "$@"; then
		return $?
	fi
	param_dirname=$(dirname "${parameter_file_name}")
	export TF_DATA_DIR="${param_dirname}/.terraform"

	echo "Parameter file:                      ${parameter_file_name}"

	key=$(echo "${parameter_file_name}" | cut -d. -f1)

	#Persisting the parameters across executions
	automation_config_directory=$CONFIG_REPO_PATH/.sap_deployment_automation/
	generic_config_information="${automation_config_directory}"config
	deployer_config_information="${automation_config_directory}/$CONTROL_PLANE_NAME"


	if [ ! -f "$deployer_config_information" ]; then
		if [ -f "${CONFIG_DIR}/${environment}${region_code}" ]; then
			echo "Move existing configuration file"
			sudo mv "${CONFIG_DIR}/${environment}${region_code}" "${deployer_config_information}"
		fi
	fi

	param_dirname=$(pwd)

	init "${automation_config_directory}" "${generic_config_information}" "${deployer_config_information}"

	var_file="${param_dirname}"/"${parameter_file_name}"

	echo "Configuration file:                  $parameter_file_name"
	echo "Deployment region:                   $region"
	echo "Deployment region code:              $region_code"

	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/"${deployment_system}"/
	export TF_DATA_DIR="${param_dirname}"/.terraform

	this_ip=$(curl -s ipinfo.io/ip) >/dev/null 2>&1
	export TF_VAR_Agent_IP=$this_ip
	echo "Agent IP:                            $this_ip"

	extra_vars=""
	reinstalled=0

	if [ -f terraform.tfvars ]; then
		extra_vars=" -var-file=${param_dirname}/terraform.tfvars "
	fi

	allParameters=$(printf " -var-file=%s %s" "${var_file}" "${extra_vars}")
	allImportParameters=$(printf " -var-file=%s %s " "${var_file}" "${extra_vars}")

	if [ ! -d ./.terraform/ ]; then
		print_banner "Deployer-bootstrap" "New deployment" "info"
		terraform -chdir="${terraform_module_directory}" init -upgrade=true -backend-config "path=${param_dirname}/terraform.tfstate"
		return_value=$?
	else
		if [ -f ./.terraform/terraform.tfstate ]; then
			azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate || true)
			if [ -n "$azure_backend" ]; then
				print_banner "Deployer-bootstrap" "State already migrated to Azure" "warning"
				unset TF_DATA_DIR
				return 10
			else
				if terraform -chdir="${terraform_module_directory}" init -upgrade=true -backend-config "path=${param_dirname}/terraform.tfstate"; then
					return_value=$?
					print_banner "Deployer-bootstrap" "Terraform init succeeded." "success"
				else
					print_banner "Deployer-bootstrap" "Terraform init failed." "error"
					unset TF_DATA_DIR
					return $?
				fi
			fi
		fi
		echo "Parameters:                          $allParameters"
		terraform -chdir="${terraform_module_directory}" refresh $allParameters
	fi
	return_value=$?
	if [ 1 == $return_value ]; then
		print_banner "Deployer-bootstrap" "Terraform init failed" "error"
		unset TF_DATA_DIR
		return $return_value
	fi

	print_banner "Deployer-bootstrap" "Running Terraform plan" "info"

	#########################################################################################"
	#                                                                                       #
	#                             Running Terraform plan                                    #
	#                                                                                       #
	#########################################################################################

	# shellcheck disable=SC2086

	if terraform -chdir="$terraform_module_directory" plan -detailed-exitcode $allParameters | tee -a plan_output.log; then
		return_value=${PIPESTATUS[0]}
	else
		return_value=${PIPESTATUS[0]}
	fi

	if [ 1 == $return_value ]; then
	  print_banner "Deployer-bootstrap" "Terraform plan failed" "error"
		if [ -f plan_output.log ]; then
			cat plan_output.log
			rm plan_output.log
		fi
		unset TF_DATA_DIR
		return $return_value
	fi

	if [ -f plan_output.log ]; then
		rm plan_output.log
	fi


	#########################################################################################
	#                                                                                       #
	#                             Running Terraform apply                                   #
	#                                                                                       #"
	#########################################################################################

  print_banner "Deployer-bootstrap" "Running Terraform apply" "info"
	parallelism=10

	#Provide a way to limit the number of parallel tasks for Terraform
	if printenv "TF_PARALLELLISM" ; then
		parallelism=$TF_PARALLELLISM
	fi

	if [ -f apply_output.json ]; then
		rm apply_output.json
	fi

	if [ -n "${approve}" ]; then
		# shellcheck disable=SC2086
		terraform -chdir="${terraform_module_directory}" apply -parallelism="${parallelism}" \
			$allParameters -no-color -compact-warnings -json -input=false --auto-approve | tee -a apply_output.json
		return_value=${PIPESTATUS[0]}

		if [ $return_value -eq 1 ]; then
		  print_banner "Deployer-bootstrap" "Terraform apply failed." "error"
		else
		  print_banner "Deployer-bootstrap" "Terraform apply succeeded." "success"
			# return code 2 is ok
			return_value=0
		fi
	else
		# shellcheck disable=SC2086
		terraform -chdir="${terraform_module_directory}" apply -parallelism="${parallelism}" \
			$allParameters
		return_value=$?
		if [ $return_value -eq 1 ]; then
		  print_banner "Deployer-bootstrap" "Terraform apply failed." "error"
		else
		  print_banner "Deployer-bootstrap" "Terraform apply succeeded." "success"
			# return code 2 is ok
			return_value=0
		fi
	fi

	if [ -f apply_output.json ]; then
		errors_occurred=$(jq 'select(."@level" == "error") | length' apply_output.json)

		if [[ -n $errors_occurred ]]; then
			return_value=10
			if [ -n "${approve}" ]; then

				# shellcheck disable=SC2086
				if ! ImportAndReRunApply "apply_output.json" "${terraform_module_directory}" $allImportParameters $allParameters; then
					return_value=$?
				fi
				if [ -f apply_output.json ]; then
					# shellcheck disable=SC2086
					if ! ImportAndReRunApply "apply_output.json" "${terraform_module_directory}" $allImportParameters $allParameters; then
						return_value=$?
					fi
				fi
				if [ -f apply_output.json ]; then
					# shellcheck disable=SC2086
					if ! ImportAndReRunApply "apply_output.json" "${terraform_module_directory}" $allImportParameters $allParameters; then
						return_value=$?
					fi
				fi
				if [ -f apply_output.json ]; then
					# shellcheck disable=SC2086
					if ! ImportAndReRunApply "apply_output.json" "${terraform_module_directory}" $allImportParameters $allParameters; then
						return_value=$?
					fi
				fi
				if [ -f apply_output.json ]; then
					# shellcheck disable=SC2086
					if ! ImportAndReRunApply "apply_output.json" "${terraform_module_directory}" $allImportParameters $allParameters; then
						return_value=$?
					fi
				fi
			else
				return_value=10
			fi
		fi
	fi

	echo "Terraform Apply return code:         $return_value"

	if [ 0 != $return_value ]; then
	  print_banner "Deployer-bootstrap" "!!! Error when creating the deployer !!!." "error"
		return  $return_value
	fi

	if ! terraform -chdir="${terraform_module_directory}" output | grep "No outputs"; then

		keyvault=$(terraform -chdir="${terraform_module_directory}" output deployer_kv_user_name | tr -d \")
		temp=$(echo "${keyvault}" | grep "Warning")
		if [ -z "${temp}" ]; then
			temp=$(echo "${keyvault}" | grep "Backend reinitialization required")
			if [ -z "${temp}" ]; then
				touch "${deployer_config_information}"
				printf -v val %-.20s "$keyvault"
				print_banner "Deployer-bootstrap" "Keyvault to use for SPN details: $val" "info"
				return_value=0
			else
				return_value=2
			fi
		fi

		APPLICATION_CONFIGURATION_ID=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw deployer_app_config_id | tr -d \")
		if [ -n "${APPLICATION_CONFIGURATION_ID}" ]; then
			save_config_var "APPLICATION_CONFIGURATION_ID" "${deployer_config_information}"
		fi

		deployer_random_id=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw random_id | tr -d \")
		if [ -n "${deployer_random_id}" ]; then
			custom_random_id="${deployer_random_id:0:3}"
			sed -i -e /"custom_random_id"/d "${var_file}"
			printf "# The parameter 'custom_random_id' can be used to control the random 3 digits at the end of the storage accounts and key vaults\ncustom_random_id=\"%s\"\n" "${custom_random_id}" >>"${var_file}"

		fi
	fi

	unset TF_DATA_DIR

	return "$return_value"
}

# Main script
install_deployer "$@"
exit $?

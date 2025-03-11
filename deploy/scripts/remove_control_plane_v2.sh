#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

################################################################################################
#                                                                                              #
#   This file contains the logic to deploy the environment to support SAP workloads.           #
#                                                                                              #
#   The script is intended to be run from a parent folder to the folders containing            #
#   the json parameter files for the deployer, the library and the environment.                #
#                                                                                              #
#   The script will persist the parameters needed between the executions in the                #
#   [CONFIG_REPO_PATH]/.sap_deployment_automation folder                                                        #
#                                                                                              #
#   The script experts the following exports:                                                  #
#   ARM_SUBSCRIPTION_ID to specify which subscription to deploy to                             #
#   SAP_AUTOMATION_REPO_PATH the path to the folder containing the cloned sap-automation                 #
#                                                                                              #
################################################################################################

# Ensure that the exit status of a pipeline command is non-zero if any
# stage of the pipefile has a non-zero exit status.
set -o pipefail

#colors for terminal
bold_red="\e[1;31m"
cyan="\e[1;36m"
reset_formatting="\e[0m"

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

SCRIPT_NAME="$(basename "$0")"

if printenv "CONFIG_REPO_PATH"; then
	CONFIG_DIR="${CONFIG_REPO_PATH}/.sap_deployment_automation"
else
	echo -e "${bold_red}CONFIG_REPO_PATH is not set${reset_formatting}"
	exit 1
fi

if [[ -f /etc/profile.d/deploy_server.sh ]]; then
	path=$(grep -m 1 "export PATH=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export PATH=$path
fi

terraform_storage_account_name=""

function showhelp {
	echo ""
	echo "##################################################################################################################"
	echo "#                                                                                                                #"
	echo "#                                                                                                                #"
	echo "#   This file contains the logic to remove the deployer and library from an Azure region                         #"
	echo "#                                                                                                                #"
	echo "#   The script experts the following exports:                                                                    #"
	echo "#                                                                                                                #"
	echo "#     SAP_AUTOMATION_REPO_PATH the path to the folder containing the cloned sap-automation                       #"
	echo "#                                                                                                                #"
	echo "#   The script is to be run from a parent folder to the folders containing the json parameter files for          #"
	echo "#    the deployer and the library and the environment.                                                           #"
	echo "#                                                                                                                #"
	echo "#   The script will persist the parameters needed between the executions in the                                  #"
	echo "#   [CONFIG_REPO_PATH]/.sap_deployment_automation folder                                                         #"
	echo "#                                                                                                                #"
	echo "#                                                                                                                #"
	echo "#   Usage: remove_region.sh                                                                                      #"
	echo "#      -d or --deployer_parameter_file       deployer parameter file                                             #"
	echo "#      -l or --library_parameter_file        library parameter file                                              #"
	echo "#                                                                                                                #"
	echo "#                                                                                                                #"
	echo "#   Example:                                                                                                     #"
	echo "#                                                                                                                #"
	echo "#   SAP_AUTOMATION_REPO_PATH/scripts/remove_controlplane.sh \                                                    #"
	echo "#      --deployer_parameter_file DEPLOYER/PROD-WEEU-DEP00-INFRASTRUCTURE/PROD-WEEU-DEP00-INFRASTRUCTURE.tfvars \ #"
	echo "#      --library_parameter_file LIBRARY/PROD-WEEU-SAP_LIBRARY/PROD-WEEU-SAP_LIBRARY.tfvars \                     #"
	echo "#                                                                                                                #"
	echo "##################################################################################################################"
}

function missing {
	printf -v val '%-40s' "$missing_value"
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo "#   Missing : ${val}                                  #"
	echo "#                                                                                       #"
	echo "#   Usage: remove_region.sh                                                             #"
	echo "#      -d or --deployer_parameter_file       deployer parameter file                    #"
	echo "#      -l or --library_parameter_file        library parameter file                     #"
	echo "#                                                                                       #"
	echo "#########################################################################################"

}

# Function to source helper scripts
source_helper_scripts() {
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

# Function to parse command line arguments
parse_arguments() {
	local input_opts
	input_opts=$(getopt -n remove_control_plane -o d:l:s:b:r:ihag --longoptions deployer_parameter_file:,library_parameter_file:,subscription:,resource_group:,storage_account:,auto-approve,ado,help,keep_agent -- "$@")
	VALID_ARGUMENTS=$?

	if [ "$VALID_ARGUMENTS" != "0" ]; then
		control_plane_showhelp
	fi

	eval set -- "$input_opts"
	while true; do
		case "$1" in
		-d | --deployer_parameter_file)
			deployer_parameter_file="$2"
			shift 2
			;;
		-l | --library_parameter_file)
			library_parameter_file="$2"
			shift 2
			;;
		-s | --subscription)
			subscription="$2"
			shift 2
			;;
		-b | --storage_account)
			storage_account="$2"
			shift 2
			;;
		-r | --resource_group)
			resource_group="$2"
			shift 2
			;;
		-a | --ado)
			approve_parameter="--auto-approve;ado=1"
			shift
			;;
		-g | --keep_agent)
			keep_agent=1
			shift
			;;
		-i | --auto-approve)
			approve_parameter="--auto-approve"
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

	if [ ! -f "${library_parameter_file}" ]; then
		control_plane_missing 'library parameter file'
		exit 2 #No such file or directory
	fi
	if [ ! -f "${deployer_parameter_file}" ]; then
		control_plane_missing 'deployer parameter file'
		exit 2 #No such file or directory
	fi

	if [ "$ado_flag" == "--ado" ] || [ "$approve_parameter" == "--auto-approve" ]; then
		echo "Approve:                             Automatically"
		autoApproveParameter="--auto-approve"
	else
		autoApproveParameter=""
	fi
	key=$(basename "${deployer_parameter_file}" | cut -d. -f1)
	deployer_tfstate_key="${key}.terraform.tfstate"
	deployer_dirname=$(dirname "${deployer_parameter_file}")
	deployer_parameter_file_name=$(basename "${deployer_parameter_file}")

	key=$(basename "${library_parameter_file}" | cut -d. -f1)
	library_tfstate_key="${key}.terraform.tfstate"
	library_dirname=$(dirname "${library_parameter_file}")
	library_parameter_file_name=$(basename "${library_parameter_file}")

	if [ -z $CONTROL_PLANE_NAME ]; then
		CONTROL_PLANE_NAME=$(basename "${deployer_parameter_file}" | cut -d'-' -f1-3)
		export CONTROL_PLANE_NAME
	fi

	# Check that parameter files have environment and location defined
	if ! validate_key_parameters "$deployer_parameter_file"; then
		return_code=$?
		exit $return_code
	fi

	# Check that the exports ARM_SUBSCRIPTION_ID and SAP_AUTOMATION_REPO_PATH are defined
	validate_exports
	return_code=$?
	if [ 0 != $return_code ]; then
		exit $return_code
	fi

	# Convert the region to the correct code
	get_region_code "$region"

	export TF_IN_AUTOMATION="true"
	# Terraform Plugins
	if checkIfCloudShell; then
		mkdir -p "${HOME}/.terraform.d/plugin-cache"
		export TF_PLUGIN_CACHE_DIR="${HOME}/.terraform.d/plugin-cache"
	else
		if [ ! -d /opt/terraform/.terraform.d/plugin-cache ]; then
			sudo mkdir -p /opt/terraform/.terraform.d/plugin-cache
			sudo chown -R "$USER" /opt/terraform
		fi
		export TF_PLUGIN_CACHE_DIR=/opt/terraform/.terraform.d/plugin-cache
	fi

}

# Function to retrieve data from Azure App Configuration
function retrieve_parameters() {
	tfstate_resource_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId" "$CONTROL_PLANE_NAME")
	TF_VAR_tfstate_resource_id=$tfstate_resource_id
	export TF_VAR_tfstate_resource_id

	terraform_storage_account_name=$(echo $tfstate_resource_id | cut -d'/' -f9)
	export terraform_storage_account_name

	terraform_storage_account_resource_group_name=$(echo $tfstate_resource_id | cut -d'/' -f5)
	export terraform_storage_account_resource_group_name

	terraform_storage_account_subscription_id=$(echo $tfstate_resource_id | cut -d'/' -f3)
	export terraform_storage_account_subscription_id

	TF_VAR_deployer_kv_user_arm_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultResourceId" "$CONTROL_PLANE_NAME")
	export TF_VAR_spn_keyvault_id="${TF_VAR_deployer_kv_user_arm_id}"

	subscription=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_SubscriptionId" "$CONTROL_PLANE_NAME")
	export subscription

}

function remove_control_plane() {
	step=0
	ado_flag="none"

	# Define an array of helper scripts
	helper_scripts=(
		"${script_directory}/helpers/script_helpers.sh"
		"${script_directory}/deploy_utils.sh"
	)

	# Call the function with the array
	source_helper_scripts "${helper_scripts[@]}"

	# Parse command line arguments
	parse_arguments "$@"
	echo "ADO flag:                            ${ado_flag}"

	deployer_config_information="${CONFIG_DIR}/$CONTROL_PLANE_NAME"

	# Check that Terraform and Azure CLI is installed
	validate_dependencies
	return_code=$?
	if [ 0 != $return_code ]; then
		echo "validate_dependencies returned $return_code"
		exit $return_code
	fi

	if [ -z "$APPLICATION_CONFIGURATION_ID" ]; then
		load_config_vars "${deployer_config_information}" "APPLICATION_CONFIGURATION_ID"
		export APPLICATION_CONFIGURATION_ID
	else
		save_config_var "APPLICATION_CONFIGURATION_ID" "${deployer_config_information}"
	fi

	retrieve_parameters

	echo ""
	echo "Control Plane Name:                  $CONTROL_PLANE_NAME"
	echo "Region code:                         ${region_code}"
	echo "Deployer State File:                 ${deployer_tfstate_key}"
	echo "Library State File:                  ${library_tfstate_key}"
	echo "Deployer Subscription:               $ARM_SUBSCRIPTION_ID"

	key=$(echo "${deployer_parameter_file}" | cut -d. -f1)

	if [ -f .terraform/terraform.tfstate ]; then
		terraform_storage_account_subscription_id=$(grep -m1 "subscription_id" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d '", \r' | xargs || true)
		terraform_storage_account_name=$(grep -m1 "storage_account_name" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d ' ",\r' | xargs || true)
		terraform_storage_account_resource_group_name=$(grep -m1 "resource_group_name" "${param_dirname}/.terraform/terraform.tfstate" | cut -d ':' -f2 | tr -d ' ",\r' | xargs || true)
	fi

	echo ""
	echo "Terraform details"
	echo "-------------------------------------------------------------------------"
	echo "Subscription:                        ${terraform_storage_account_subscription_id}"
	echo "Storage Account:                     ${terraform_storage_account_name}"
	echo "Resource Group:                      ${terraform_storage_account_resource_group_name}"
	echo "State file:                          ${key}.terraform.tfstate"

	if [ ! -f "$deployer_config_information" ]; then
		if [ -f "${CONFIG_DIR}/${environment}${region_code}" ]; then
			echo "Copying existing configuration file"
			sudo mv "${CONFIG_DIR}/${environment}${region_code}" "${deployer_config_information}"
		fi
	fi

	load_config_vars "${deployer_config_information}" "step"
	if [ 1 -eq $step ]; then
		exit 0
	fi

	if [ 0 -eq $step ]; then
		exit 0
	fi

	this_ip=$(curl -s ipinfo.io/ip) >/dev/null 2>&1
	export TF_VAR_Agent_IP=$this_ip
	echo "Agent IP:                              $this_ip"

	current_directory=$(pwd)

	#we know that we have a valid az session so let us set the environment variables
	set_executing_user_environment_variables "none"

	# Deployer

	cd "${deployer_dirname}" || exit

	param_dirname=$(pwd)

	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/run/sap_deployer/
	export TF_DATA_DIR="${param_dirname}/.terraform"

	# Reinitialize
	print_banner "Remove Control Plane " "Running Terraform init (deployer)" "info"

	if [ -f init_error.log ]; then
		rm init_error.log
	fi

	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/sap_deployer/

	if [ -f .terraform/terraform.tfstate ]; then
		azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate || true)
		if [ -n "$azure_backend" ]; then
			echo "Terraform state:                     remote"
			if terraform -chdir="${terraform_module_directory}" init -migrate-state -force-copy --backend-config "path=${param_dirname}/terraform.tfstate"; then
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init succeeded (deployer - local)" "success"
			else
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init failed (deployer - local)" "error"
			fi

		else
			echo "Terraform state:                     local"
			if terraform -chdir="${terraform_module_directory}" init --backend-config "path=${param_dirname}/terraform.tfstate"; then
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init succeeded (deployer - local)" "success"
			else
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init failed (deployer - local)" "error"
			fi

		fi
	else
		echo "Terraform state:                     unknown"
		if terraform -chdir="${terraform_module_directory}" init -reconfigure --backend-config "path=${param_dirname}/terraform.tfstate"; then
			return_value=$?
			print_banner "Remove Control Plane " "Terraform init succeeded (deployer - local)" "success"
		else
			return_value=$?
			print_banner "Remove Control Plane " "Terraform init failed (deployer - local)" "error"
		fi
	fi

	diagnostics_account_id=$(terraform -chdir="${terraform_module_directory}" output diagnostics_account_id | tr -d \")
	if [ -n "${diagnostics_account_id}" ]; then
		diagnostics_account_name=$(echo "${diagnostics_account_id}" | cut -d'/' -f9)
		diagnostics_account_resource_group_name=$(echo "${diagnostics_account_id}" | cut -d'/' -f5)
		diagnostics_account_subscription_id=$(echo "${diagnostics_account_id}" | cut -d'/' -f3)
		az storage account update --name "$diagnostics_account_name" --resource-group "$diagnostics_account_resource_group_name" --subscription "$diagnostics_account_subscription_id" --allow-shared-key-access --output none
	fi

	if terraform -chdir="${terraform_module_directory}" apply -var-file="${deployer_parameter_file}" "${approve_parameter}"; then
		return_value=$?
		print_banner "Remove Control Plane " "Terraform apply (deployer) succeeded" "success"
	else
		return_value=$?
		print_banner "Remove Control Plane " "Terraform apply (deployer) failed" "error"
		return 20
	fi

	if ! terraform -chdir="${terraform_module_directory}" output testing; then
		echo "not found"
	else
		echo "found"
	fi

	print_banner "Remove Control Plane " "Running Terraform init (library - local)" "info"

	deployer_statefile_foldername_path="${param_dirname}"
	export TF_VAR_deployer_statefile_foldername="${deployer_statefile_foldername_path}"

	if [ 0 != $return_value ]; then
		unset TF_DATA_DIR
		exit 10
	fi

	if [ -z $TF_VAR_spn_keyvault_id ]; then
		if ! terraform -chdir="${terraform_module_directory}" output | grep "No outputs"; then
			keyvault_id=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw deployer_kv_user_arm_id | tr -d \")
			TF_VAR_spn_keyvault_id="${keyvault_id}"
			export TF_VAR_spn_keyvault_id
		fi
	fi

	cd "${current_directory}" || exit

	key=$(echo "${library_parameter_file}" | cut -d. -f1)
	cd "${library_dirname}" || exit
	param_dirname=$(pwd)

	#Library

	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/sap_library/
	export TF_DATA_DIR="${param_dirname}/.terraform"

	if [ -f .terraform/terraform.tfstate ]; then
		azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate || true)
		if [ -n "$azure_backend" ]; then
			echo "Terraform state:                     remote"
			if terraform -chdir="${terraform_module_directory}" init -force-copy -migrate-state --backend-config "path=${param_dirname}/terraform.tfstate"; then
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init succeeded (library - local)" "success"
			else
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init failed (library - local)" "error"
			fi
		else
			echo "Terraform state:                     local"
			if terraform -chdir="${terraform_module_directory}" init -reconfigure --backend-config "path=${param_dirname}/terraform.tfstate"; then
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init succeeded (library - local)" "success"
			else
				return_value=$?
				print_banner "Remove Control Plane " "Terraform init failed (library - local)" "error"
			fi

		fi
	else
		echo "Terraform state:                     unknown"
		if terraform -chdir="${terraform_module_directory}" init -reconfigure --backend-config "path=${param_dirname}/terraform.tfstate"; then
			return_value=$?
			print_banner "Remove Control Plane " "Terraform init succeeded (library - local)" "success"
		else
			return_value=$?
			print_banner "Remove Control Plane " "Terraform init failed (library - local)" "error"
		fi
	fi

	if [ 0 != $return_code ]; then
		unset TF_DATA_DIR
		return 20
	fi

	extra_vars=""

	if [ -f terraform.tfvars ]; then
		extra_vars=" -var-file=${param_dirname}/terraform.tfvars "
	fi

	export TF_DATA_DIR="${param_dirname}/.terraform"
	export TF_use_spn=false

	print_banner "Remove Control Plane " "Running Terraform destroy (library)" "info"

	if terraform -chdir="${terraform_module_directory}" destroy -var-file="${library_parameter_file}" -var use_deployer=false "${approve_parameter}"; then
		return_value=$?
		print_banner "Remove Control Plane " "Terraform destroy (library) succeeded" "success"
	else
		return_value=$?
		print_banner "Remove Control Plane " "Terraform destroy (library) failed" "error"
		return 20
	fi

	if [ -f "${param_dirname}/terraform.tfstate" ]; then
		rm "${param_dirname}/terraform.tfstate"
	fi
	if [ -f "${param_dirname}/terraform.tfstate.backup" ]; then
		rm "${param_dirname}/terraform.tfstate.backup"
	fi
	if [ -f "${param_dirname}/.terraform/terraform.tfstate" ]; then
		rm "${param_dirname}/.terraform/terraform.tfstate"
	fi

	if [ 0 != $return_value ]; then
		return $return_value
	else
		print_banner "Remove Control Plane " "Reset Local File" "success"

		STATE_SUBSCRIPTION=''
		REMOTE_STATE_SA=''
		REMOTE_STATE_RG=''
		save_config_vars "${deployer_config_information}" \
			tfstate_resource_id \
			REMOTE_STATE_SA \
			REMOTE_STATE_RG \
			STATE_SUBSCRIPTION

	fi

	cd "${current_directory}" || exit

	if [ 1 -eq $keep_agent ]; then
		print_banner "Remove Control Plane " "Keeping the Azure DevOps agent" "info"
		step=1
		save_config_var "step" "${deployer_config_information}"
	else
		cd "${deployer_dirname}" || exit

		param_dirname=$(pwd)

		terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/sap_deployer/
		export TF_DATA_DIR="${param_dirname}/.terraform"

		extra_vars=""

		if [ -f terraform.tfvars ]; then
			extra_vars=" -var-file=${param_dirname}/terraform.tfvars "
		fi

		var_file="${param_dirname}"/"${deployer_tfvars_filename}"

		print_banner "Remove Control Plane " "Running Terraform destroy (deployer)" "info"

		if terraform -chdir="${terraform_module_directory}" destroy -var-file="${var_file}" "${extra_vars}" "${approve_parameter}"; then
			return_value=$?
			print_banner "Remove Control Plane " "Terraform destroy (deployer) succeeded" "success"
			if [ -f "${param_dirname}/terraform.tfstate" ]; then
				rm "${param_dirname}/terraform.tfstate"
			fi
			if [ -f "${param_dirname}/terraform.tfstate.backup" ]; then
				rm "${param_dirname}/terraform.tfstate.backup"
			fi
			if [ -f "${param_dirname}/.terraform/terraform.tfstate" ]; then
				rm "${param_dirname}/.terraform/terraform.tfstate"
			fi
		else
			return_value=$?
			print_banner "Remove Control Plane " "Terraform destroy (deployer) failed" "error"
			return 20
		fi
		step=0
		save_config_var "step" "${deployer_config_information}"
		if [ 0 != $return_value ]; then
			keyvault=''
			deployer_tfstate_key=''
			save_config_var "$keyvault" "${deployer_config_information}"
			save_config_var "$deployer_tfstate_key" "${deployer_config_information}"
			if [ -f "${deployer_config_information}" ]; then
				rm "${deployer_config_information}"
			fi
		fi
	fi

	cd "${current_directory}" || exit

	unset TF_DATA_DIR
	exit $return_value
}

remove_control_plane "$@"
return $?

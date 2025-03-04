#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#colors for terminal
bold_red="\e[1;31m"
cyan="\e[1;36m"
reset_formatting="\e[0m"

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

if printenv "CONFIG_REPO_PATH"; then
	CONFIG_DIR="${CONFIG_REPO_PATH}/.sap_deployment_automation"
else
	echo -e "${bold_red}CONFIG_REPO_PATH is not set${reset_formatting}"
	exit 1
fi
readonly CONFIG_DIR

if printenv "TEST_ONLY"; then
	TEST_ONLY="${TEST_ONLY}"
else
	TEST_ONLY="false"
fi

if [[ -f /etc/profile.d/deploy_server.sh ]]; then
	path=$(grep -m 1 "export PATH=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export PATH=$path
fi

#Internal helper functions
function showhelp {

	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                 $bold_red_underscore !Warning!: This script will remove deployed systems $reset_formatting                 #"
	echo "#                                                                                       #"
	echo "#   This file contains the logic to remove the different systems                        #"
	echo "#   The script expects the following exports:                                           #"
	echo "#                                                                                       #"
	echo "#      SAP_AUTOMATION_REPO_PATH (path to the repo folder (sap-automation))              #"
	echo "#      ARM_SUBSCRIPTION_ID (subscription containing the state file storage account)     #"
	echo "#      REMOTE_STATE_RG (resource group name for storage account containing state files) #"
	echo "#      REMOTE_STATE_SA (storage account for state file)                                 #"
	echo "#                                                                                       #"
	echo "#   The script will persist the parameters needed between the executions in the         #"
	echo "#   [CONFIG_REPO_PATH]/.sap_deployment_automation folder.                               #"
	echo "#                                                                                       #"
	echo "#                                                                                       #"
	echo "#   Usage: remover_v2.sh                                                                #"
	echo "#    -p or --parameterfile           parameter file                                     #"
	echo "#    -t or --type                    type of system to remove                           #"
	echo "#                                         valid options:                                #"
	echo "#                                           sap_deployer                                #"
	echo "#                                           sap_library                                 #"
	echo "#                                           sap_landscape                               #"
	echo "#                                           sap_system                                  #"
	echo "#    -h or --help                    Show help                                          #"
	echo "#                                                                                       #"
	echo "#   Optional parameters                                                                 #"
	echo "#                                                                                       #"
	echo "#    -o or --storageaccountname      Storage account name for state file                #"
	echo "#    -s or --state_subscription      Subscription for tfstate storage account           #"
	echo "#                                                                                       #"
	echo "#   Example:                                                                            #"
	echo "#                                                                                       #"
	echo "#   [REPO-ROOT]deploy/scripts/remover.sh \                                              #"
	echo "#      --parameterfile DEV-WEEU-SAP01-X00.tfvars \                                      #"
	echo "#      --type sap_system                                                                #"
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

# Function to parse command line arguments
function parse_arguments() {
	local input_opts
	input_opts=$(getopt -n remover_v2 -o p:t:o:d:l:s:g:c:w:ahif --longoptions type:,parameter_file:,storage_accountname:,deployer_tfstate_key:,landscape_tfstate_key:,state_subscription:,application_configuration_id:,control_plane_name:,workload_zone_name:,ado,auto-approve,force,help -- "$@")
	is_input_opts_valid=$?

	if [[ "${is_input_opts_valid}" != "0" ]]; then
		showhelp
		return 1
	fi

	eval set -- "$input_opts"
	while true; do
		case "$1" in
		-a | --ado)
			called_from_ado=1
			approve="--auto-approve"
			TF_IN_AUTOMATION=true
			export TF_IN_AUTOMATION
			shift
			;;
		-d | --deployer_tfstate_key)
			deployer_tfstate_key="$2"
			shift 2
			;;
		-c | --control_plane_name)
			CONTROL_PLANE_NAME="$2"
			shift 2
			;;
		-g | --application_configuration_id)
			APPLICATION_CONFIGURATION_ID="$2"
			shift 2
			;;
		-l | --landscape_tfstate_key)
			landscape_tfstate_key="$2"
			shift 2
			;;
		-o | --storage_accountname)
			terraform_storage_account_name="$2"
			shift 2
			;;
		-p | --parameter_file)
			parameterFilename="$2"
			shift 2
			;;
		-s | --state_subscription)
			terraform_storage_account_subscription_id="$2"
			shift 2
			;;
		-t | --type)
			deployment_system="$2"
			shift 2
			;;
		-w | --workload_zone_name)
			WORKLOAD_ZONE_NAME="$2"
			shift 2
			;;
		-f | --force)
			force=1
			shift
			;;
		-i | --auto-approve)
			approve="--auto-approve"
			shift
			;;
		-h | --help)
			showhelp
			return 3
			;;
		--)
			shift
			break
			;;
		esac
	done

	# Validate required parameters

	parameterfile_name=$(basename "${parameterFilename}")
	parameterfile_dirname=$(dirname "${parameterFilename}")

	if [ "${parameterfile_dirname}" != '.' ]; then
		print_banner "Remover" "Please run this command from the folder containing the parameter file" "error"
	fi

	if [ ! -f "${parameterfile_name}" ]; then
		print_banner "Remover" "Parameter file does not exist: ${parameterFilename}" "error"
	fi

	[[ -z "$CONTROL_PLANE_NAME" ]] && {
		print_banner "Remover" "control_plane_name is required" "error"
		return 1
	}
	[[ -z "$APPLICATION_CONFIGURATION_ID" ]] && {
		print_banner "Remover" "application_configuration_id is required" "error"
		return 1
	}

	[[ -z "$deployment_system" ]] && {
		print_banner "Remover" "type is required" "error"
		return 1
	}

	if [ -z $CONTROL_PLANE_NAME ] && [ -n "$deployer_tfstate_key" ]; then
		CONTROL_PLANE_NAME=$(echo $deployer_tfstate_key | cut -d'-' -f1-3)
	fi

	if [ -n "$CONTROL_PLANE_NAME" ]; then
		deployer_tfstate_key="${CONTROL_PLANE_NAME}-INFRASTRUCTURE.terraform.tfstate"
	fi

	if [ "${deployment_system}" == sap_system ] || [ "${deployment_system}" == sap_landscape ]; then
		if [ -n "$WORKLOAD_ZONE_NAME" ]; then
			landscape_tfstate_key="${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.terraform.tfstate"
		else
			WORKLOAD_ZONE_NAME=$(echo $landscape_tfstate_key | cut -d'-' -f1-3)

			if [ -z $WORKLOAD_ZONE_NAME ] && [ -n "$landscape_tfstate_key" ]; then
				WORKLOAD_ZONE_NAME=$(echo $landscape_tfstate_key | cut -d'-' -f1-3)
			fi
		fi
	fi

	if [ "${deployment_system}" == sap_system ]; then
		if [ -z "${landscape_tfstate_key}" ]; then
			if [ 1 != $called_from_ado ]; then
				read -r -p "Workload terraform statefile name: " landscape_tfstate_key
				save_config_var "landscape_tfstate_key" "${system_config_information}"
			else
				print_banner "Remover" "Workload terraform statefile name is required" "error"
				unset TF_DATA_DIR
				return 2
			fi
		else
			TF_VAR_landscape_tfstate_key="${landscape_tfstate_key}"
			export TF_VAR_landscape_tfstate_key
			landscape_tfstate_key_exists=true
		fi
	fi

	if [ "${deployment_system}" != sap_deployer ]; then
		if [ -z "${deployer_tfstate_key}" ]; then
			if [ 1 != $called_from_ado ]; then
				read -r -p "Deployer terraform state file name: " deployer_tfstate_key
				save_config_var "deployer_tfstate_key" "${system_config_information}"
			else
				print_banner "Remover" "Deployer terraform state file name is required" "error"
				unset TF_DATA_DIR
				return 2
			fi
		fi
	fi

	if [ -n "${deployer_tfstate_key}" ]; then
		TF_VAR_deployer_tfstate_key="${deployer_tfstate_key}"
		export TF_VAR_deployer_tfstate_key
	fi

	# Check that the exports ARM_SUBSCRIPTION_ID and SAP_AUTOMATION_REPO_PATH are defined
	if ! validate_exports; then
		return $?
	fi

	# Check that Terraform and Azure CLI is installed
	if ! validate_dependencies; then
		return $?
	fi

	# Check that parameter files have environment and location defined
	if ! validate_key_parameters "$parameterFilename"; then
		return $?
	fi

	if [ $deployment_system == sap_system ] || [ $deployment_system == sap_landscape ]; then
		system_config_information="${CONFIG_DIR}/${WORKLOAD_ZONE_NAME}"
		network_logical_name=$(echo $WORKLOAD_ZONE_NAME | cut -d'-' -f3)
	else
		system_config_information="${CONFIG_DIR}/${CONTROL_PLANE_NAME}"
		management_network_logical_name=$(echo $CONTROL_PLANE_NAME | cut -d'-' -f3)
	fi
	region=$(echo "${region}" | tr "[:upper:]" "[:lower:]")
	if valid_region_name "${region}"; then
		# Convert the region to the correct code
		get_region_code "${region}"
	else
		echo "Invalid region: $region"
		return 2
	fi

	return 0

}

# Function to parse command line arguments
retrieve_parameters() {
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

}

function sdaf_remover() {
	landscape_tfstate_key=""
	landscape_tfstate_key_exists=false
	called_from_ado=0
	extra_vars=""
	WORKLOAD_ZONE_NAME=""

	# Define an array of helper scripts
	helper_scripts=(
		"${script_directory}/helpers/script_helpers.sh"
		"${script_directory}/deploy_utils.sh"
	)

	# Call the function with the array
	source_helper_scripts "${helper_scripts[@]}"

	# Parse command line arguments
	if ! parse_arguments "$@"; then

		return $?
	fi

	retrieve_parameters

	parallelism=10

	#Provide a way to limit the number of parallel tasks for Terraform
	if printenv "TF_PARALLELLISM"; then
		parallelism=$TF_PARALLELLISM
	fi

	echo "Parameter file:                      $parameterFilename"
	echo "Current directory:                   $(pwd)"
	echo "Control Plane name:                  ${CONTROL_PLANE_NAME}"
	if [ -n "${WORKLOAD_ZONE_NAME}" ]; then
		echo "Workload zone name:                  ${WORKLOAD_ZONE_NAME}"
	fi
	key=$(echo "${parameterfile_name}" | cut -d. -f1)

	echo "Configuration file:                  $system_config_information"
	echo "Deployment region:                   $region"
	echo "Deployment region code:              $region_code"
	echo "Target subscription:                 $ARM_SUBSCRIPTION_ID"

	if [ "$DEBUG" = True ]; then
		print_banner "Remover" "Enabling debug mode" "info"
		set -x
		set -o errexit
	fi

	if [ 1 == $called_from_ado ]; then
		this_ip=$(curl -s ipinfo.io/ip) >/dev/null 2>&1
		export TF_VAR_Agent_IP=$this_ip
		echo "Agent IP:                            $this_ip"
	fi

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

	param_dirname=$(pwd)
	export TF_DATA_DIR="${param_dirname}/.terraform"

	#§init "${CONFIG_DIR}" "${generic_config_information}" "${system_config_information}"

	var_file="${param_dirname}"/"${parameterFilename}"

	if [ -f terraform.tfvars ]; then
		extra_vars="-var-file=${param_dirname}/terraform.tfvars"
	else
		extra_vars=""
	fi

	current_subscription_id=$(az account show --query id -o tsv)

	if [[ -n "$terraform_storage_account_subscription_id" ]] && [[ "$terraform_storage_account_subscription_id" != "$current_subscription_id" ]]; then
		print_banner "Remover" "Changing the subscription to: $terraform_storage_account_subscription_id" "info"
		az account set --sub "${terraform_storage_account_subscription_id}"

		return_code=$?
		if [ 0 != $return_code ]; then
			print_banner "Remover" "The deployment account (MSI or SPN) does not have access to: $terraform_storage_account_subscription_id" "ption_id}"
			exit $return_code
		fi

		az account set --sub "${current_subscription_id}"

	fi

	if [ "${deployment_system}" != sap_deployer ]; then
		echo "Deployer Keyvault ID:                $TF_VAR_deployer_kv_user_arm_id"

	fi

	useSAS=$(az storage account show --name "${terraform_storage_account_name}" --query allowSharedKeyAccess --subscription "${terraform_storage_account_subscription_id}" --out tsv)

	if [ "$useSAS" = "true" ]; then
		echo "Storage Account Authentication:      Key"
		export ARM_USE_AZUREAD=false
	else
		echo "Storage Account Authentication:      Entra ID"
		export ARM_USE_AZUREAD=true
	fi

	#setting the user environment variables
	set_executing_user_environment_variables "none"

	terraform_module_directory="$SAP_AUTOMATION_REPO_PATH/deploy/terraform/run/${deployment_system}"
	cd "${param_dirname}" || exit

	if [ ! -d "${terraform_module_directory}" ]; then

		printf -v val %-40.40s "$deployment_system"
		print_banner "Remover" "Incorrect system deployment type specified: ${val}$" "error"
		exit 1
	fi

	# This is used to tell Terraform if this is a new deployment or an update
	deployment_parameter=""
	# This is used to tell Terraform the version information from the state file
	version_parameter=""

	export TF_DATA_DIR="${param_dirname}/.terraform"

	terraform --version
	echo ""
	echo "Terraform details"
	echo "-------------------------------------------------------------------------"
	echo "Subscription:                        ${terraform_storage_account_subscription_id}"
	echo "Storage Account:                     ${terraform_storage_account_name}"
	echo "Resource Group:                      ${terraform_storage_account_resource_group_name}"
	echo "State file:                          ${key}.terraform.tfstate"
	echo "Target subscription:                 ${ARM_SUBSCRIPTION_ID}"
	echo "Deployer state file:                 ${deployer_tfstate_key}"
	echo "Workload zone state file:            ${landscape_tfstate_key}"
	echo "Current directory:                   $(pwd)"
	echo "Parallelism count:                   $parallelism"
	echo ""

	TF_VAR_subscription_id="$ARM_SUBSCRIPTION_ID"
	export TF_VAR_subscription_id

	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/run/${deployment_system}"/
	export TF_DATA_DIR="${param_dirname}/.terraform"


	var_file="${parameterfile_dirname}"/"${parameterfile_name}"

	cd "${param_dirname}" || exit
	if [ ! -f .terraform/terraform.tfstate ]; then

		terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/run/${deployment_system}"/

		if terraform -chdir="${terraform_module_directory}" init -force-copy \
			--backend-config "subscription_id=${terraform_storage_account_subscription_id}" \
			--backend-config "resource_group_name=${terraform_storage_account_resource_group_name}" \
			--backend-config "storage_account_name=${terraform_storage_account_name}" \
			--backend-config "container_name=tfstate" \
			--backend-config "key=${key}.terraform.tfstate"; then
			return_value=$?
			print_banner "Remover" "Terraform init succeeded." "success"

		else
			return_value=$?
			print_banner "Remover" "Terraform init failed" "error"
			exit $return_value
		fi
	else
		echo "Terraform state:                     remote"
		print_banner "Remover" "The system has already been deployed and the state file is in Azure" "info"

		if ! terraform -chdir="${terraform_module_directory}" init -upgrade=true \
			--backend-config "subscription_id=${terraform_storage_account_subscription_id}" \
			--backend-config "resource_group_name=${terraform_storage_account_resource_group_name}" \
			--backend-config "storage_account_name=${terraform_storage_account_name}" \
			--backend-config "container_name=tfstate" \
			--backend-config "key=${key}.terraform.tfstate"; then
			return_value=$?
			print_banner "Remover" "Terraform init failed." "error"
			exit $return_value
		else
			return_value=$?
			print_banner "Remover" "Terraform init succeeded." "success"
		fi
	fi

	if [ "$resource_group_exist" ]; then
		print_banner "Remover" "Running Terraform destroy" "info"

		if [ "$deployment_system" == "sap_deployer" ]; then
			terraform -chdir="${terraform_module_directory}" destroy -var-file="${var_file}"
			"$deployer_tfstate_key_parameter"

		elif [ "$deployment_system" == "sap_library" ]; then
			terraform_bootstrap_directory="${SAP_AUTOMATION_REPO_PATH}/deploy/terraform/bootstrap/${deployment_system}/"
			terraform -chdir="${terraform_bootstrap_directory}" init -upgrade=true -force-copy

			terraform -chdir="${terraform_bootstrap_directory}" refresh -var-file="${var_file}" \
				"$deployer_tfstate_key_parameter"

			terraform -chdir="${terraform_bootstrap_directory}" destroy -var-file="${var_file}" "${approve}" -var use_deployer=false \
				"$deployer_tfstate_key_parameter"
		elif [ "$deployment_system" == "sap_landscape" ]; then

			allParameters=$(printf " -var-file=%s %s %s  %s " "${var_file}" "${extra_vars}" "${tfstate_parameter}" "${deployer_tfstate_key_parameter}")

			moduleID="module.sap_landscape.azurerm_key_vault_secret.sid_ppk"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'sid_ppk' removed from state"
				fi
			fi

			moduleID="module.sap_landscape.azurerm_key_vault_secret.sid_pk"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'sid_pk' removed from state"
				fi
			fi

			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				moduleID="module.sap_landscape.azurerm_key_vault_secret.sid_username"
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'sid_username' removed from state"
				fi
			fi

			moduleID="module.sap_landscape.azurerm_key_vault_secret.sid_password"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'sid_password' removed from state"
				fi
			fi

			moduleID="module.sap_landscape.azurerm_key_vault_secret.witness_access_key"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'witness_access_key' removed from state"
				fi
			fi

			moduleID="module.sap_landscape.azurerm_key_vault_secret.deployer_keyvault_user_name"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'deployer_keyvault_user_name' removed from state"
				fi
			fi

			moduleID="module.sap_landscape.azurerm_key_vault_secret.witness_name"
			if terraform -chdir="${terraform_module_directory}" state list -id="${moduleID}"; then
				if terraform -chdir="${terraform_module_directory}" state rm "${moduleID}"; then
					echo "Secret 'witness_name' removed from state"
				fi
			fi

			if [ -n "${approve}" ]; then
				# shellcheck disable=SC2086
				if terraform -chdir="${terraform_module_directory}" destroy $allParameters "$approve" -no-color -json -parallelism="$parallelism" | tee -a destroy_output.json; then
					return_value=$?
					print_banner "Remover" "Terraform destroy succeeded" "success"
				else
					return_value=$?
					print_banner "Remover" "Terraform destroy failed" "error"
				fi
				if [ -f destroy_output.json ]; then
					errors_occurred=$(jq 'select(."@level" == "error") | length' destroy_output.json)
					if [[ -n $errors_occurred ]]; then
						return_value=10
					fi
				fi

			else
				# shellcheck disable=SC2086
				if terraform -chdir="${terraform_module_directory}" destroy $allParameters -parallelism="$parallelism"; then
					print_banner "Remover" "Terraform destroy succeeded" "success"
					return_value=$?
				else
					return_value=$?
					print_banner "Remover" "Terraform destroy failed" "error"
				fi
			fi
		else

			echo "Calling destroy with:          -var-file=${var_file} $approve $tfstate_parameter $landscape_tfstate_key_parameter $deployer_tfstate_key_parameter"

			allParameters=$(printf " -var-file=%s %s %s %s %s " "${var_file}" "${extra_vars}" "${tfstate_parameter}" "${landscape_tfstate_key_parameter}" "${deployer_tfstate_key_parameter}")

			if [ -n "${approve}" ]; then
				# shellcheck disable=SC2086
				if terraform -chdir="${terraform_module_directory}" destroy $allParameters "$approve" -no-color -json -parallelism="$parallelism" | tee -a destroy_output.json; then
					return_value=${PIPESTATUS[0]}
					print_banner "Remover" "Terraform destroy succeeded" "success"
				else
					return_value=${PIPESTATUS[0]}
					print_banner "Remover" "Terraform destroy failed" "error"
				fi
			else
				# shellcheck disable=SC2086
				if terraform -chdir="${terraform_module_directory}" destroy $allParameters -parallelism="$parallelism"; then
					return_value=$?
					print_banner "Remover" "Terraform destroy succeeded" "success"
				else
					return_value=$?
					print_banner "Remover" "Terraform destroy failed" "error"
				fi
			fi

			if [ -f destroy_output.json ]; then
				errors_occurred=$(jq 'select(."@level" == "error") | length' destroy_output.json)

				if [[ -n $errors_occurred ]]; then
				  print_banner "Remover" "Errors during the destroy phase" "success"
					echo ""
					echo "#########################################################################################"
					echo "#                                                                                       #"
					echo -e "#                      $bold_red_underscore!!! Errors during the destroy phase !!!$reset_formatting                          #"
					echo "#                                                                                       #"
					echo "#########################################################################################"
					echo ""

					return_value=2
					all_errors=$(jq 'select(."@level" == "error") | {summary: .diagnostic.summary, detail: .diagnostic.detail}' destroy_output.json)
					if [[ -n ${all_errors} ]]; then
						readarray -t errors_strings < <(echo ${all_errors} | jq -c '.')
						for errors_string in "${errors_strings[@]}"; do
							string_to_report=$(jq -c -r '.detail ' <<<"$errors_string")
							if [[ -z ${string_to_report} ]]; then
								string_to_report=$(jq -c -r '.summary ' <<<"$errors_string")
							fi

							report=$(echo $string_to_report | grep -m1 "Message=" "${var_file}" | cut -d'=' -f2- | tr -d ' ' | tr -d '"')
							if [[ -n ${report} ]]; then
								echo -e "#                          $bold_red_underscore  $report $reset_formatting"
								echo "##vso[task.logissue type=error]${report}"
							else
								echo -e "#                          $bold_red_underscore  $string_to_report $reset_formatting"
								echo "##vso[task.logissue type=error]${string_to_report}"
							fi

						done

					fi

				fi

			fi

			if [ -f destroy_output.json ]; then
				rm destroy_output.json
			fi

		fi

	else
		return_value=0
	fi

	if [ "${deployment_system}" == sap_deployer ]; then
		sed -i /deployer_tfstate_key/d "${system_config_information}"
	fi

	if [ "${deployment_system}" == sap_landscape ]; then
		rm "${system_config_information}"
	fi

	if [ "${deployment_system}" == sap_library ]; then
		sed -i /REMOTE_STATE_RG/d "${system_config_information}"
		sed -i /REMOTE_STATE_SA/d "${system_config_information}"
		sed -i /tfstate_resource_id/d "${system_config_information}"
	fi

	# if [ "${deployment_system}" == sap_system ]; then

	#     echo "#########################################################################################"
	#     echo "#                                                                                       #"
	#     echo -e "#                            $cyan Clean up load balancer IP $reset_formatting        #"
	#     echo "#                                                                                       #"
	#     echo "#########################################################################################"

	#     database_loadbalancer_public_ip_address=$(terraform -chdir="${terraform_module_directory}" output -no-color database_loadbalancer_ip | tr -d "\n"  | tr -d "("  | tr -d ")" | tr -d " ")
	#     database_loadbalancer_public_ip_address=$(echo ${database_loadbalancer_public_ip_address/tolist/})
	#     database_loadbalancer_public_ip_address=$(echo ${database_loadbalancer_public_ip_address/,]/]})
	#     echo "Database Load Balancer IP: $database_loadbalancer_public_ip_address"

	#     load_config_vars "${parameterfile_name}" "database_loadbalancer_ips"
	#     database_loadbalancer_ips=$(echo ${database_loadbalancer_ips} | xargs)

	#     if [[ "${database_loadbalancer_public_ip_address}" != "${database_loadbalancer_ips}" ]];
	#     then
	#       database_loadbalancer_ips=${database_loadbalancer_public_ip_address}
	#       save_config_var "database_loadbalancer_ips" "${parameterfile_name}"
	#     fi

	#     scs_loadbalancer_public_ip_address=$(terraform -chdir="${terraform_module_directory}" output -no-color scs_loadbalancer_ips | tr -d "\n"  | tr -d "("  | tr -d ")" | tr -d " ")
	#     scs_loadbalancer_public_ip_address=$(echo ${scs_loadbalancer_public_ip_address/tolist/})
	#     scs_loadbalancer_public_ip_address=$(echo ${scs_loadbalancer_public_ip_address/,]/]})
	#     echo "SCS Load Balancer IP: $scs_loadbalancer_public_ip_address"

	#     load_config_vars "${parameterfile_name}" "scs_server_loadbalancer_ips"
	#     scs_server_loadbalancer_ips=$(echo ${scs_server_loadbalancer_ips} | xargs)

	#     if [[ "${scs_loadbalancer_public_ip_address}" != "${scs_server_loadbalancer_ips}" ]];
	#     then
	#       scs_server_loadbalancer_ips=${scs_loadbalancer_public_ip_address}
	#       save_config_var "scs_server_loadbalancer_ips" "${parameterfile_name}"
	#     fi
	# fi

	unset TF_DATA_DIR

	exit "$return_value"
}

sdaf_remover "$@"
exit $?

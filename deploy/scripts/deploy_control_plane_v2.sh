#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

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
	input_opts=$(getopt -n deploy_controlplane_v2 -o d:l:s:c:p:t:a:k:ifohrvm --longoptions deployer_parameter_file:,library_parameter_file:,subscription:,spn_id:,spn_secret:,tenant_id:,terraform_storage_account_name:,vault:,auto-approve,force,only_deployer,help,recover,ado,msi -- "$@")
	VALID_ARGUMENTS=$?

	if [ "$VALID_ARGUMENTS" != "0" ]; then
		control_plane_showhelp
	fi

	eval set -- "$input_opts"
	while true; do
		case "$1" in
		-t | --terraform_storage_account_name)
			terraform_storage_account_name="$2"
			shift 2
			;;
		-d | --deployer_parameter_file)
			deployer_parameter_file="$2"
			shift 2
			;;
		-k | --vault)
			keyvault="$2"
			shift 2
			;;
		-l | --library_parameter_file)
			library_parameter_file="$2"
			shift 2
			;;
		-o | --only_deployer)
			only_deployer=1
			shift
			;;
		-s | --subscription)
			subscription="$2"
			shift 2
			;;
		-f | --force)
			force=1
			shift
			;;
		-h | --help)
			control_plane_showhelp
			exit 3
			;;
		-i | --auto-approve)
			approve="--auto-approve"
			shift
			;;
		-m | --msi)
			deploy_using_msi_only=1
			shift
			;;
		-v | --ado)
			ado_flag="--ado"
			shift
			;;
		-r | --recover)
			recover=1
			shift
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

	if [ "$ado_flag" == "--ado" ] || [ "$approve" == "--auto-approve" ]; then
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

}

# Function to bootstrap the deployer
function bootstrap_deployer() {
	##########################################################################################
	#                                                                                        #
	#                                      STEP 0                                            #
	#                                                                                        #
	#                           Bootstrapping the deployer                                   #
	#                                                                                        #
	##########################################################################################
	print_banner "Bootstrap Deployer " "Bootstrapping the deployer..." "info"

	allParameters=$(printf " --parameter_file %s %s" "${deployer_parameter_file_name}" "${autoApproveParameter}")

	cd "${deployer_dirname}" || exit

	echo "Calling install_deployer_v2.sh:         $allParameters"

	if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/install_deployer_v2.sh" --parameter_file "${deployer_parameter_file_name}" "$autoApproveParameter"; then
		return_code=$?
		echo "Return code from install_deployer_v2:   ${return_code}"

		if [ $return_code -eq 10 ]; then
			print_banner "Bootstrap Deployer " "Deployer is bootstrapped" "info"
			step=3
			save_config_var "step" "${deployer_config_information}"
			return 0
		else
			print_banner "Bootstrap Deployer " "Bootstrapping the deployer failed" "error"
			return 10
		fi
	else
		return_code=$?
		print_banner "Bootstrap Deployer " "Bootstrapping the deployer succeeded" "success"
		echo "Return code from install_deployer_v2:   ${return_code}"
		step=1
		save_config_var "step" "${deployer_config_information}"
		if [ 1 = "${only_deployer:-}" ]; then
			return 0
		fi
	fi

	load_config_vars "${deployer_config_information}" "APPLICATION_CONFIGURATION_ID"
	export APPLICATION_CONFIGURATION_ID
	load_config_vars "${deployer_config_information}" "keyvault"

	echo "Key vault:                           ${keyvault}"
	echo "Application configuration Id         ${APPLICATION_CONFIGURATION_ID}"

	echo "##vso[task.setprogress value=20;]Progress Indicator"
	cd "$root_dirname" || exit
	return "$return_code"
}

function validate_keyvault_access {

	##########################################################################################
	#                                                                                        #
	#                                     Step 1                                             #
	#                           Validating Key Vault Access                                  #
	#                                                                                        #
	#                                                                                        #
	##########################################################################################

	TF_DATA_DIR="${deployer_dirname}"/.terraform
	export TF_DATA_DIR

	if [ -n "$APPLICATION_CONFIGURATION_ID" ]; then
		keyvault=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultName" "${CONTROL_PLANE_NAME}")
	else
		if [ -f ./.terraform/terraform.tfstate ]; then
			azure_backend=$(grep "\"type\": \"azurerm\"" .terraform/terraform.tfstate || true)
			if [ -n "$azure_backend" ]; then
				echo "Terraform state:                     remote"

				terraform_module_directory="$SAP_AUTOMATION_REPO_PATH"/deploy/terraform/run/sap_deployer/
				terraform -chdir="${terraform_module_directory}" init -upgrade=true

				keyvault=$(terraform -chdir="${terraform_module_directory}" output deployer_kv_user_name | tr -d \")
				save_config_var "keyvault" "${deployer_config_information}"
			else
				echo "Terraform state:                     local"
				terraform_module_directory="$SAP_AUTOMATION_REPO_PATH"/deploy/terraform/bootstrap/sap_deployer/
				terraform -chdir="${terraform_module_directory}" init -upgrade=true

				keyvault=$(terraform -chdir="${terraform_module_directory}" output deployer_kv_user_name | tr -d \")
				save_config_var "keyvault" "${deployer_config_information}"
			fi
		else
			if [ $ado_flag != "--ado" ]; then
				read -r -p "Deployer keyvault name: " keyvault
				save_config_var "keyvault" "${deployer_config_information}"
			else
				step=0
				save_config_var "step" "${deployer_config_information}"
				exit 10
			fi
		fi
	fi

	if [ -n "${keyvault}" ] && [ 0 != "$step" ]; then

		if validate_key_vault "$keyvault" "$ARM_SUBSCRIPTION_ID"; then
			echo "Key vault:                           ${keyvault}"
			save_config_var "keyvault" "${deployer_config_information}"
			TF_VAR_deployer_kv_user_arm_id=$(az keyvault show --name="$keyvault" --subscription "${subscription}" --query id --output tsv)
			export TF_VAR_deployer_kv_user_arm_id

		else
			return_code=$?
			print_banner "Key Vault" "Key vault not found" "error"
		fi

	fi
	step=2
	save_config_var "step" "${deployer_config_information}"

	cd "${deployer_dirname}" || exit

	unset TF_DATA_DIR

	cd "$root_dirname" || exit

	az account set --subscription "$ARM_SUBSCRIPTION_ID"
}

function bootstrap_library {
	##########################################################################################
	#                                                                                        #
	#                                      STEP 2                                            #
	#                           Bootstrapping the library                                    #
	#                                                                                        #
	#                                                                                        #
	##########################################################################################

	if [ 2 -eq $step ]; then
		print_banner "Bootstrap-Library" "Bootstrapping the library..." "info"

		relative_path="${library_dirname}"
		export TF_DATA_DIR="${relative_path}/.terraform"
		relative_path="${deployer_dirname}"

		cd "${library_dirname}" || exit
		terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/sap_library/

		echo "Calling install_library_v2.sh with: --parameter_file ${library_parameter_file_name} --deployer_statefile_foldername ${relative_path} ${autoApproveParameter}"

		if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/install_library_v2.sh" \
			--parameter_file "${library_parameter_file_name}" \
			--deployer_statefile_foldername "${relative_path}" \
			"$autoApproveParameter"; then
			echo ""
			echo "#########################################################################################"
			echo "#                                                                                       #"
			echo -e "#                       $bold_red  Bootstrapping of the library failed $reset_formatting                          #"
			echo "#                                                                                       #"
			echo "#########################################################################################"
			echo ""
			step=2
			save_config_var "step" "${deployer_config_information}"
			exit 20
		else
			step=3
			save_config_var "step" "${deployer_config_information}"
			echo ""
			echo "#########################################################################################"
			echo "#                                                                                       #"
			echo -e "#                       $cyan Bootstrapping of the library succeeded $reset_formatting                        #"
			echo "#                                                                                       #"
			echo "#########################################################################################"
			echo ""

		fi

		if ! terraform -chdir="${terraform_module_directory}" output | grep "No outputs"; then

			terraform_storage_account_name=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw remote_state_storage_account_name | tr -d \")
			terraform_storage_account_subscription_id=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw created_resource_group_subscription_id | tr -d \")

			if [ "${ado_flag}" != "--ado" ]; then
				az storage account network-rule add -g "${terraform_storage_account_resource_group_name}" --account-name "${terraform_storage_account_name}" --ip-address "${this_ip}" --output none
			fi

			TF_VAR_sa_connection_string=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw sa_connection_string | tr -d \")
			export TF_VAR_sa_connection_string
		fi

		if [ -n "${tfstate_resource_id}" ]; then
			TF_VAR_tfstate_resource_id="${tfstate_resource_id}"
		else
			tfstate_resource_id=$(az resource list --name "$terraform_storage_account_name" --subscription "$terraform_storage_account_subscription_id" --resource-type Microsoft.Storage/storageAccounts --query "[].id | [0]" -o tsv)
			TF_VAR_tfstate_resource_id=$tfstate_resource_id
		fi
		export TF_VAR_tfstate_resource_id

		cd "${current_directory}" || exit
		save_config_var "step" "${deployer_config_information}"
		echo "##vso[task.setprogress value=60;]Progress Indicator"

	else
		echo ""
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                           $cyan Library is bootstrapped $reset_formatting                                   #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""
		echo "##vso[task.setprogress value=60;]Progress Indicator"

	fi

	unset TF_DATA_DIR
	cd "$root_dirname" || exit
	echo "##vso[task.setprogress value=80;]Progress Indicator"

}

function migrate_deployer_state() {
	##########################################################################################
	#                                                                                        #
	#                                      STEP 3                                            #
	#                           Migrating the state file for the deployer                    #
	#                                                                                        #
	#                                                                                        #
	##########################################################################################
	print_banner "Migrate-Deployer" "Migrating the deployer state..." "info"

	cd "${deployer_dirname}" || exit

	if [ -z "$terraform_storage_account_name" ]; then
		if [ -n "$APPLICATION_CONFIGURATION_ID" ]; then
			tfstate_resource_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId" "${CONTROL_PLANE_NAME}")
			TF_VAR_tfstate_resource_id=$tfstate_resource_id
			export TF_VAR_tfstate_resource_id

			terraform_storage_account_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 9)
			terraform_storage_account_subscription_id=$(echo "$tfstate_resource_id" | cut -d '/' -f 3)
			terraform_storage_account_resource_group_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 5)
			ARM_SUBSCRIPTION_ID=$terraform_storage_account_subscription_id
		fi
	fi

	if [ -z "${terraform_storage_account_name}" ]; then
		export step=2
		save_config_var "step" "${deployer_config_information}"
		echo "##vso[task.setprogress value=40;]Progress Indicator"
		print_banner "Migrate-Deployer" "Could not find the SAP Library, please re-run!" "error"
		exit 11
	fi

	if ! "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/installer_v2.sh" --parameter_file $deployer_parameter_file_name --type sap_deployer \
		--control_plane_name "${CONTROL_PLANE_NAME}" --application_configuration_id "${APPLICATION_CONFIGURATION_ID}" \
		$ado_flag "${autoApproveParameter}"; then

		echo ""
		step=3
		save_config_var "step" "${deployer_config_information}"
		print_banner "Migrate-Deployer" "Migrating the Deployer state failed." "error"
		exit 30
	else
		print_banner "Migrate-Deployer" "Migrating the Deployer state succeeded." "success"
	fi

	cd "$root_dirname" || exit
	export step=4
	save_config_var "step" "${deployer_config_information}"

	unset TF_DATA_DIR
	cd "$root_dirname" || exit

}

function migrate_library_state() {
	##########################################################################################
	#                                                                                        #
	#                                      STEP 4                                            #
	#                           Migrating the state file for the library                     #
	#                                                                                        #
	#                                                                                        #
	##########################################################################################

	print_banner "Migrate-Library" "Migrating the library state..." "info"

	terraform_module_directory="$SAP_AUTOMATION_REPO_PATH"/deploy/terraform/run/sap_library/
	cd "${library_dirname}" || exit

	echo "Calling installer_v2.sh with: --type sap_library --parameter_file ${library_parameter_file_name} --storage_account_name ${terraform_storage_account_name}  --deployer_tfstate_key ${deployer_tfstate_key} ${autoApproveParameter} ${ado_flag}"
	if ! "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/installer_v2.sh" --type sap_library --parameter_file "${library_parameter_file_name}" \
		--control_plane_name "${CONTROL_PLANE_NAME}" --application_configuration_id "${APPLICATION_CONFIGURATION_ID}" \
		$ado_flag $autoApproveParameter; then

		print_banner "Migrate-Library" "Migrating the Library state failed." "error"
		step=4
		save_config_var "step" "${deployer_config_information}"
		return 40
	else
		return_code=$?
		print_banner "Migrate-Library" "Migrating the Library state succeeded." "success"
	fi

	cd "$root_dirname" || exit

	step=5
	save_config_var "step" "${deployer_config_information}"
}

function copy_files_to_public_deployer() {
	if [ "${ado_flag}" != "--ado" ]; then
		cd "${current_directory}" || exit

		load_config_vars "${deployer_config_information}" "sshsecret"
		load_config_vars "${deployer_config_information}" "keyvault"
		load_config_vars "${deployer_config_information}" "deployer_public_ip_address"
		if [ ! -f /etc/profile.d/deploy_server.sh ]; then
			# Only run this when not on deployer
			print_banner "Copy-Files" "Copying the parameter files..." "info"

			if [ -n "${sshsecret}" ]; then
				step=3
				save_config_var "step" "${deployer_config_information}"
				printf "%s\n" "Collecting secrets from KV"
				temp_file=$(mktemp)
				ppk=$(az keyvault secret show --vault-name "${keyvault}" --name "${sshsecret}" | jq -r .value)
				echo "${ppk}" >"${temp_file}"
				chmod 600 "${temp_file}"

				remote_deployer_dir="/home/azureadm/Azure_SAP_Automated_Deployment/WORKSPACES/"$(dirname "$deployer_parameter_file")
				remote_library_dir="/home/azureadm/Azure_SAP_Automated_Deployment/WORKSPACES/"$(dirname "$library_parameter_file")
				remote_config_dir="$CONFIG_REPO_PATH/.sap_deployment_automation"

				ssh -i "${temp_file}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 azureadm@"${deployer_public_ip_address}" "mkdir -p ${remote_deployer_dir}"/.terraform 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "$deployer_parameter_file" azureadm@"${deployer_public_ip_address}":"${remote_deployer_dir}"/. 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "$(dirname "$deployer_parameter_file")"/.terraform/terraform.tfstate azureadm@"${deployer_public_ip_address}":"${remote_deployer_dir}"/.terraform/terraform.tfstate 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "$(dirname "$deployer_parameter_file")"/terraform.tfstate azureadm@"${deployer_public_ip_address}":"${remote_deployer_dir}"/terraform.tfstate 2>/dev/null

				ssh -i "${temp_file}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 azureadm@"${deployer_public_ip_address}" " mkdir -p ${remote_library_dir}"/.terraform 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "$(dirname "$deployer_parameter_file")"/.terraform/terraform.tfstate azureadm@"${deployer_public_ip_address}":"${remote_deployer_dir}"/. 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "$library_parameter_file" azureadm@"${deployer_public_ip_address}":"$remote_library_dir"/. 2>/dev/null

				ssh -i "${temp_file}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 azureadm@"${deployer_public_ip_address}" "mkdir -p ${remote_config_dir}" 2>/dev/null
				scp -i "${temp_file}" -q -o StrictHostKeyChecking=no -o ConnectTimeout=120 -p "${deployer_config_information}" azureadm@"${deployer_public_ip_address}":"${remote_config_dir}"/. 2>/dev/null
				rm "${temp_file}"
			fi
		fi

	fi

}

# Function to execute deployment steps
function execute_deployment_steps() {
	local step=$1
	echo "Step:                                $step"

	if [ 1 -eq "${step}" ]; then
		if ! validate_keyvault_access; then
			print_banner "Bootstrap" "Validating key vault access failed" "error"
			return $?
		else
			step=2
			save_config_var "step" "${deployer_config_information}"
		fi
	fi

	if [ 2 -eq "${step}" ]; then
		if ! bootstrap_library; then
			print_banner "Bootstrap-Library" "Bootstrapping the SAP Library failed" "error"
			return $?
		else
			step=3
			save_config_var "step" "${deployer_config_information}"
		fi
	fi

	if [ 3 -eq "${step}" ]; then
		if ! migrate_deployer_state; then
			print_banner "Migrate-Deployer" "Migration of deployer state failed" "error"
			return $?
		else
			step=4
			save_config_var "step" "${deployer_config_information}"
		fi
	fi
	if [ 4 -eq "${step}" ]; then
		if ! migrate_library_state; then
			print_banner "Migrate-Library" "Migration of library state failed" "error"
			return $?
		else
			step=5
			save_config_var "step" "${deployer_config_information}"
		fi
	fi
	if [ 5 -eq "${step}" ]; then
		if [ "${ado_flag}" != "--ado" ]; then
			if ! copy_files_to_public_deployer; then
				print_banner "Migrate-Library" "Copying files failed" "error"
				return $?
			else
				step=3
				save_config_var "step" "${deployer_config_information}"
			fi
		fi
	else
		step=3
		save_config_var "step" "${deployer_config_information}"
	fi
}

function deploy_control_plane() {
	force=0
	recover=0
	step=0
	ado_flag="none"
	deploy_using_msi_only=0
	autoApproveParameter=""

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

	root_dirname=$(pwd)

	# Check that Terraform and Azure CLI is installed
	validate_dependencies
	return_code=$?
	if [ 0 != $return_code ]; then
		echo "validate_dependencies returned $return_code"
		return $return_code
	fi
	echo ""
	echo "Control Plane Name:                  $CONTROL_PLANE_NAME"
	echo "Region code:                         ${region_code}"
	echo "Deployer State File:                 ${deployer_tfstate_key}"
	echo "Library State File:                  ${library_tfstate_key}"
	echo "Deployer Subscription:               ${subscription}"

	generic_config_information="${CONFIG_DIR}"/config
	deployer_config_information="${CONFIG_DIR}/$CONTROL_PLANE_NAME"

	if [ ! -f "$deployer_config_information" ]; then
		if [ -f "${CONFIG_DIR}/${environment}${region_code}" ]; then
			echo "Copying existing configuration file"
			sudo mv "${CONFIG_DIR}/${environment}${region_code}" "${deployer_config_information}"
		fi
	fi

	if [ $force == 1 ]; then
		if [ -f "${deployer_config_information}" ]; then
			rm "${deployer_config_information}"
		fi
	fi

	init "${CONFIG_DIR}" "${generic_config_information}" "${deployer_config_information}"

	if [ -z $APPLICATION_CONFIGURATION_ID ]; then
		load_config_vars "${deployer_config_information}" "APPLICATION_CONFIGURATION_ID"
		export APPLICATION_CONFIGURATION_ID
	else
		save_config_var "APPLICATION_CONFIGURATION_ID" "${deployer_config_information}"
	fi

	relative_path="${deployer_dirname}"
	TF_DATA_DIR="${relative_path}"/.terraform
	export TF_DATA_DIR

	load_config_vars "${deployer_config_information}" "step"
	if [ -z "${step}" ]; then
		step=0
	fi
	echo "Step:                                $step"
	current_directory=$(pwd)

	print_banner "Control Plane Deployment" "Starting the control plane deployment..." "info"

	noAccess=$(az account show --query name | grep "N/A(tenant level account)" || true)

	if [ -n "$noAccess" ]; then
		print_banner "Control Plane Deployment" "The provided credentials do not have access to the subscription" "error"
		az account show --output table

		return 65
	fi
	az account list --query "[].{Name:name,Id:id}" --output table

	if [ 0 = "${deploy_using_msi_only:-}" ]; then
		echo "Identity to use:                     Service Principal"
		unset ARM_USE_MSI
		set_executing_user_environment_variables "$ARM_CLIENT_SECRET"
	else
		echo "Identity to use:                     Managed Identity"
		set_executing_user_environment_variables "none"
	fi

	if [ 0 -eq $step ]; then
		if bootstrap_deployer; then
			print_banner "Bootstrap Deployer " "Bootstrapping the deployer failed" "error"
			return 10
		fi

		if [ 1 == "${only_deployer:-}" ]; then
			return 0
		fi
	else
		execute_deployment_steps $step
	fi

	printf -v kvname '%-40s' "${keyvault}"
	printf -v storage_account '%-40s' "${terraform_storage_account_name}"
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "# $cyan Please save these values: $reset_formatting                                                           #"
	echo "#     - Key Vault:       ${kvname}                       #"
	echo "#     - Storage Account: ${storage_account}                       #"
	echo "#                                                                                       #"
	echo "#########################################################################################"

	now=$(date)
	cat <<EOF >"${deployer_config_information}".md
# Control Plane Deployment #

Date : "${now}"

## Configuration details ##

| Item                    | Name                 |
| ----------------------- | -------------------- |
| Environment             | $environment         |
| Location                | $region              |
| Keyvault Name           | ${keyvault}          |
| Terraform state         | ${storage_account}   |

EOF

	cat "${deployer_config_information}".md

	deployer_keyvault="${keyvault}"
	export deployer_keyvault

	terraform_state_storage_account="${terraform_storage_account_name}"
	export terraform_state_storage_account

	step=3
	save_config_var "step" "${deployer_config_information}"
	echo "##vso[task.setprogress value=100;]Progress Indicator"

	unset TF_DATA_DIR

	return 0
}

deploy_control_plane "$@"
exit $?

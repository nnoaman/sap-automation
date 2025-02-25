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
#   $CONFIG_REPO_PATH/.sap_deployment_automation folder                                        #
#                                                                                              #
#   The script experts the following exports:                                                  #
#   ARM_SUBSCRIPTION_ID to specify which subscription to deploy to                             #
#   SAP_AUTOMATION_REPO_PATH the path to the folder containing the cloned sap-automation       #
#   CONFIG_REPO_PATH the path to the folder containing the configuration for sap               #
#                                                                                              #
################################################################################################

#error codes include those from /usr/include/sysexits.h

#colors for terminal
bold_red_underscore="\e[1;4;31m"
bold_red="\e[1;31m"
cyan="\e[1;36m"
reset_formatting="\e[0m"

#External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

if [[ -f /etc/profile.d/deploy_server.sh ]]; then
	path=$(grep -m 1 "export PATH=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export PATH=$path
fi

#call stack has full scriptname when using source
source "${script_directory}/deploy_utils.sh"

#helper files
source "${script_directory}/helpers/script_helpers.sh"

force=0
recover=0
ado_flag="none"
deploy_using_msi_only=0

INPUT_ARGUMENTS=$(getopt -n deploy_controlplane -o d:l:s:c:p:t:a:k:ifohrvm --longoptions deployer_parameter_file:,library_parameter_file:,subscription:,spn_id:,spn_secret:,tenant_id:,storageaccountname:,vault:,auto-approve,force,only_deployer,help,recover,ado,msi -- "$@")
VALID_ARGUMENTS=$?

if [ "$VALID_ARGUMENTS" != "0" ]; then
	control_plane_showhelp
fi

eval set -- "$INPUT_ARGUMENTS"
while :; do
	case "$1" in
	-a | --storageaccountname)
		REMOTE_STATE_SA="$2"
		shift 2
		;;
	-c | --spn_id)
		client_id="$2"
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
	-p | --spn_secret)
		client_secret="$2"
		shift 2
		;;
	-s | --subscription)
		subscription="$2"
		shift 2
		;;
	-t | --tenant_id)
		tenant_id="$2"
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
	-m | --msi)
		deploy_using_msi_only=1
		shift
		;;
	-o | --only_deployer)
		only_deployer=1
		shift
		;;
	-r | --recover)
		recover=1
		shift
		;;
	-v | --ado)
		ado_flag="--ado"
		shift
		;;
	-h | --help)
		control_plane_showhelp
		exit 3
		;;
	--)
		shift
		break
		;;
	esac
done

if [ ! -f "$deployer_parameter_file" ]; then
	control_plane_missing 'deployer parameter file'
	exit 2 #No such file or directory
fi

if [ ! -f "$library_parameter_file" ]; then
	control_plane_missing 'library parameter file'
	exit 2 #No such file or directory
fi

if [ "$DEBUG" = True ]; then
	# Enable debugging
	set -x
	# Exit on error
	set -o errexit
fi

echo "ADO flag:                            ${ado_flag}"

if [ "$ado_flag" == "--ado" ] || [ "$approve" == "--auto-approve" ]; then
	echo "Approve:                             Automatically"
fi

root_dirname=$(pwd)

key=$(basename "${deployer_parameter_file}" | cut -d. -f1)
deployer_tfstate_key="${key}.terraform.tfstate"
key=$(basename "${library_parameter_file}" | cut -d. -f1)
library_tfstate_key="${key}.terraform.tfstate"

deployer_dirname=$(dirname "${deployer_parameter_file}")
deployer_parameter_file_name=$(basename "${deployer_parameter_file}")

library_dirname=$(dirname "${library_parameter_file}")
library_parameter_file_name=$(basename "${library_parameter_file}")

if [ -z $CONTROL_PLANE_NAME ]; then
	CONTROL_PLANE_NAME=$(basename "${deployer_parameter_file}" | cut -d'-' -f1-3)
	export $CONTROL_PLANE_NAME
fi

# Capture the IP address of the agent
if [ ! -f /etc/profile.d/deploy_server.sh ]; then
	this_ip=$(curl -s ipinfo.io/ip) >/dev/null 2>&1
	TF_VAR_Agent_IP=$this_ip
	export TF_VAR_Agent_IP
else
	unset TF_VAR_Agent_IP
fi

# Check that Terraform and Azure CLI is installed
validate_dependencies
return_code=$?
if [ 0 != $return_code ]; then
	echo "validate_dependencies returned $return_code"
	exit $return_code
fi

# Check that parameter files have environment and location defined
if ! validate_key_parameters "$deployer_parameter_file"; then
	return_code=$?
	exit $return_code
fi

# Convert the region to the correct code
get_region_code "$region"

echo "Control Plane Name:                  $CONTROL_PLANE_NAME"
echo "Region code:                         ${region_code}"
echo "Deployer State File:                 ${deployer_tfstate_key}"
echo "Library State File:                  ${library_tfstate_key}"
echo "Deployer Subscription:               ${subscription}"

automation_config_directory=$CONFIG_REPO_PATH/.sap_deployment_automation
generic_config_information="${automation_config_directory}"/config
deployer_config_information="${automation_config_directory}/$CONTROL_PLANE_NAME"

if [ ! -f "$deployer_config_information" ]; then
	if [ -f "${automation_config_directory}/${environment}${region_code}" ]; then
		echo "Copying existing configuration file"
		sudo mv "${automation_config_directory}/${environment}${region_code}" "${deployer_config_information}"
	fi
fi

if [ $force == 1 ]; then
	if [ -f "${deployer_config_information}" ]; then
		rm "${deployer_config_information}"
	fi
fi

init "${automation_config_directory}" "${generic_config_information}" "${deployer_config_information}"

# Check that the exports ARM_SUBSCRIPTION_ID and SAP_AUTOMATION_REPO_PATH are defined
validate_exports
return_code=$?
if [ 0 != $return_code ]; then
	echo "Missing exports" >"${deployer_config_information}".err
	exit $return_code
fi

# Check that webapp exports are defined, if deploying webapp
if [ -n "${TF_VAR_use_webapp}" ]; then
	if [ "${TF_VAR_use_webapp}" == "true" ]; then
		validate_webapp_exports
		return_code=$?
		if [ 0 != $return_code ]; then
			exit $return_code
		fi
	fi
fi

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

if [ -n "${client_id}" ]; then
	TF_VAR_spn_id="$client_id"
	export TF_VAR_spn_id
else
	unset TF_VAR_spn_id
fi

echo ""
echo "#########################################################################################"
echo "#                                                                                       #"
echo -e "#                   $cyan Starting the control plane deployment $reset_formatting                             #"
echo "#                                                                                       #"
echo "#########################################################################################"
echo ""
noAccess=$(az account show --query name | grep "N/A(tenant level account)" || true)

if [ -n "$noAccess" ]; then
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#        $bold_red The provided credentials do not have access to the subscription!!! $reset_formatting           #"
	echo "#                                                                                       #"
	echo "#########################################################################################"

	az account show --output table

	exit 65
fi
az account list --query "[].{Name:name,Id:id}" --output table
#setting the user environment variables
if [ -n "${subscription}" ]; then
	if is_valid_guid "$subscription"; then
		echo ""
	else
		printf -v val %-40.40s "$subscription"
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#   The provided subscription is not valid:$bold_red ${val} $reset_formatting#   "
		echo "#                                                                                       #"
		echo "#########################################################################################"

		echo "The provided subscription is not valid: ${subscription}" >"${deployer_config_information}".err

		exit 65
	fi
fi
echo ""
echo "#########################################################################################"
echo "#                                                                                       #"
echo -e "#       $cyan Changing the subscription to: $subscription $reset_formatting            #"
echo "#                                                                                       #"
echo "#########################################################################################"
echo ""

if [ 0 = "${deploy_using_msi_only:-}" ]; then
	echo "Identity to use:                     Service Principal"
	unset ARM_USE_MSI
	set_executing_user_environment_variables "${client_secret}"
else
	echo "Identity to use:                     Managed Identity"
	set_executing_user_environment_variables "none"
fi

if [ $recover == 1 ]; then
	if [ -n "$REMOTE_STATE_SA" ]; then
		getAndStoreTerraformStateStorageAccountDetails "${REMOTE_STATE_SA}" "${deployer_config_information}"
		#Support running deploy_controlplane on new host when the resources are already deployed
		step=3
		save_config_var "step" "${deployer_config_information}"
	fi
fi

#Persist the parameters
if [ -n "$subscription" ]; then
	export STATE_SUBSCRIPTION=$subscription
	export ARM_SUBSCRIPTION_ID=$subscription
fi

current_directory=$(pwd)

if [ "$ado_flag" == "--ado" ] || [ "$approve" == "--auto-approve" ]; then
	autoApproveParameter="--auto-approve"
else
	autoApproveParameter=""
fi

##########################################################################################
#                                                                                        #
#                                      STEP 0                                            #
#                           Bootstrapping the deployer                                   #
#                                                                                        #
#                                                                                        #
##########################################################################################

if [ 0 -eq $step ]; then
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                          $cyan Bootstrapping the deployer $reset_formatting                                 #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
	echo ""

	allParameters=$(printf " --parameterfile %s %s" "${deployer_parameter_file_name}" "${autoApproveParameter}")

	cd "${deployer_dirname}" || exit

	echo "Calling install_deployer.sh:         $allParameters"
	echo "Deployer State File:                 ${deployer_tfstate_key}"

	if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/install_deployer.sh" \
		--parameterfile "${deployer_parameter_file_name}" "$autoApproveParameter"; then
		return_code=$?
		echo "Return code from install_deployer:   ${return_code}"
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       $bold_red  Bootstrapping of the deployer failed $reset_formatting                         #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		step=0
		save_config_var "step" "${deployer_config_information}"
		exit 10
	else
		return_code=$?
		echo "Return code from install_deployer:   ${return_code}"
		echo ""
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       $cyan Bootstrapping of the deployer succeeded $reset_formatting                       #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""

	fi

	echo "Return code from install_deployer:   ${return_code}"
	if [ 0 -eq $return_code ]; then
		step=1
		save_config_var "step" "${deployer_config_information}"
		if [ 1 = "${only_deployer:-}" ]; then
			exit 0
		fi
	fi

	load_config_vars "${deployer_config_information}" "APPLICATION_CONFIGURATION_ID"
	load_config_vars "${deployer_config_information}" "keyvault"
	echo "Key vault:                           ${keyvault}"
	echo "Application configuration Id         ${APPLICATION_CONFIGURATION_ID}"
	if [ -z "$keyvault" ]; then
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       $bold_red  Bootstrapping of the deployer failed $reset_formatting                         #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		exit 10
	fi

	cd "$root_dirname" || exit

	load_config_vars "${deployer_config_information}" "sshsecret"
	load_config_vars "${deployer_config_information}" "deployer_public_ip_address"

	echo "##vso[task.setprogress value=20;]Progress Indicator"
else
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                          $cyan Deployer is bootstrapped $reset_formatting                                   #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
	echo ""
	echo "##vso[task.setprogress value=20;]Progress Indicator"
	if [ 1 = "${only_deployer:-}" ]; then
		exit 0
	fi

fi

cd "$root_dirname" || exit

##########################################################################################
#                                                                                        #
#                                     Step 1                                             #
#                           Validating Key Vault Access                                  #
#                                                                                        #
#                                                                                        #
##########################################################################################

TF_DATA_DIR="${deployer_dirname}"/.terraform
export TF_DATA_DIR

if [ -z "$keyvault" ]; then
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
fi

if [ -n "${keyvault}" ] && [ 0 != "$step" ]; then

	if validate_key_vault "$keyvault" "$ARM_SUBSCRIPTION_ID"; then
		echo "Key vault:                           ${keyvault}"
		save_config_var "keyvault" "${deployer_config_information}"
		TF_VAR_deployer_kv_user_arm_id=$(az keyvault show --name="$keyvault" --subscription "${subscription}" --query id --output tsv)
		export TF_VAR_deployer_kv_user_arm_id

	else
		return_code=$?
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       $bold_red  Key vault not found $reset_formatting                                      #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
	fi

fi

cd "${deployer_dirname}" || exit

if [ 1 -eq $step ] && [ -n "$client_secret" ]; then

	if "${SAP_AUTOMATION_REPO_PATH}"/deploy/scripts/set_secrets.sh \
		--environment "${environment}" \
		--region "${region_code}" \
		--vault "${keyvault}" \
		--spn_id "${client_id}" \
		--spn_secret "${client_secret}" \
		--tenant_id "${tenant_id}"; then
		echo ""
		echo -e "${cyan}Set secrets:                           succeeded$reset_formatting"
		echo ""
		step=2
		save_config_var "step" "${deployer_config_information}"
	else
		echo -e "${bold_red}Set secrets:                           failed$reset_formatting"
		exit 10
	fi
fi

unset TF_DATA_DIR

cd "$root_dirname" || exit

az account set --subscription "$ARM_SUBSCRIPTION_ID"

##########################################################################################
#                                                                                        #
#                                      STEP 2                                            #
#                           Bootstrapping the library                                    #
#                                                                                        #
#                                                                                        #
##########################################################################################

if [ 2 -eq $step ]; then
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                          $cyan Bootstrapping the library $reset_formatting                                  #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
	echo ""

	relative_path="${library_dirname}"
	export TF_DATA_DIR="${relative_path}/.terraform"
	relative_path="${deployer_dirname}"

	cd "${library_dirname}" || exit
	terraform_module_directory="${SAP_AUTOMATION_REPO_PATH}"/deploy/terraform/bootstrap/sap_library/

	if [ $force == 1 ]; then
		rm -Rf .terraform terraform.tfstate*
	fi

	echo "Calling install_library.sh with: --parameterfile ${library_parameter_file_name} --deployer_statefile_foldername ${relative_path} --keyvault ${keyvault} ${autoApproveParameter}"

	if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/install_library.sh" \
		--parameterfile "${library_parameter_file_name}" \
		--deployer_statefile_foldername "${relative_path}" \
		--keyvault "${keyvault}" "$autoApproveParameter"; then
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

		if [ -z "$REMOTE_STATE_SA" ]; then
			REMOTE_STATE_RG=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw sapbits_sa_resource_group_name | tr -d \")
		fi
		if [ -z "$REMOTE_STATE_SA" ]; then
			REMOTE_STATE_SA=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw remote_state_storage_account_name | tr -d \")
		fi
		if [ -z "$STATE_SUBSCRIPTION" ]; then
			STATE_SUBSCRIPTION=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw created_resource_group_subscription_id | tr -d \")
		fi

		if [ "${ado_flag}" != "--ado" ]; then
			az storage account network-rule add -g "${REMOTE_STATE_RG}" --account-name "${REMOTE_STATE_SA}" --ip-address "${this_ip}" --output none
		fi

		TF_VAR_sa_connection_string=$(terraform -chdir="${terraform_module_directory}" output -no-color -raw sa_connection_string | tr -d \")
		export TF_VAR_sa_connection_string
	fi

	if [ -n "${tfstate_resource_id}" ]; then
		TF_VAR_tfstate_resource_id="${tfstate_resource_id}"
	else
		tfstate_resource_id=$(az resource list --name "$REMOTE_STATE_SA" --subscription "$STATE_SUBSCRIPTION" --resource-type Microsoft.Storage/storageAccounts --query "[].id | [0]" -o tsv)
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

##########################################################################################
#                                                                                        #
#                                      STEP 3                                            #
#                           Migrating the state file for the deployer                    #
#                                                                                        #
#                                                                                        #
##########################################################################################
if [ 3 -eq "$step" ]; then
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                          $cyan Migrating the deployer state $reset_formatting                               #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
	echo ""

	cd "${deployer_dirname}" || exit

	if [ -z "$REMOTE_STATE_SA" ]; then
		if [ -n "$APPLICATION_CONFIGURATION_ID" ]; then
			tfstate_resource_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId" "${CONTROL_PLANE_NAME}")
			TF_VAR_tfstate_resource_id=$tfstate_resource_id
			export TF_VAR_tfstate_resource_id

			REMOTE_STATE_SA=$(echo "$tfstate_resource_id" | cut -d '/' -f 9)
			STATE_SUBSCRIPTION=$(echo "$tfstate_resource_id" | cut -d '/' -f 3)
			REMOTE_STATE_RG=$(echo "$tfstate_resource_id" | cut -d '/' -f 5)
			ARM_SUBSCRIPTION_ID=$STATE_SUBSCRIPTION
		fi
	fi

	if [[ -z $REMOTE_STATE_SA ]]; then
		load_config_vars "${deployer_config_information}" "REMOTE_STATE_SA"
	fi

	if [[ -z $STATE_SUBSCRIPTION ]]; then
		load_config_vars "${deployer_config_information}" "STATE_SUBSCRIPTION"
	fi

	if [[ -z $ARM_SUBSCRIPTION_ID ]]; then
		load_config_vars "${deployer_config_information}" "ARM_SUBSCRIPTION_ID"
	fi

	if [ -z "${REMOTE_STATE_SA}" ]; then
		export step=2
		save_config_var "step" "${deployer_config_information}"
		echo "##vso[task.setprogress value=40;]Progress Indicator"
		echo ""
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                   $bold_red Could not find the SAP Library, please re-run! $reset_formatting                    #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""
		exit 11

	fi

	echo "Calling installer.sh with:          --parameterfile ${deployer_parameter_file_name} \
  --storageaccountname ${REMOTE_STATE_SA} --state_subscription ${STATE_SUBSCRIPTION} --type sap_deployer ${autoApproveParameter} ${ado_flag}"

	if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/installer.sh" \
		--type sap_deployer \ --control_plane_name "${CONTROL_PLANE_NAME}" \
		--parameterfile ${deployer_parameter_file_name} \
		--storageaccountname "${REMOTE_STATE_SA}" \
		$ado_flag \
		"${autoApproveParameter}"; then

		echo ""
		step=3
		save_config_var "step" "${deployer_config_information}"
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       ${bold_red}  Migrating the Deployer state failed ${reset_formatting}                          #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""

		exit 30
	else
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       ${cyan}  Migrating the Deployer state succeeded ${reset_formatting}                       #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""

	fi

	cd "${current_directory}" || exit
	export step=4
	save_config_var "step" "${deployer_config_information}"

fi

unset TF_DATA_DIR
cd "$root_dirname" || exit

##########################################################################################
#                                                                                        #
#                                      STEP 4                                            #
#                           Migrating the state file for the library                     #
#                                                                                        #
#                                                                                        #
##########################################################################################

if [ 4 -eq $step ]; then
	echo ""
	echo "#########################################################################################"
	echo "#                                                                                       #"
	echo -e "#                          $cyan Migrating the library state $reset_formatting                                #"
	echo "#                                                                                       #"
	echo "#########################################################################################"
	echo ""

	terraform_module_directory="$SAP_AUTOMATION_REPO_PATH"/deploy/terraform/run/sap_library/
	cd "${library_dirname}" || exit

	echo "Calling installer.sh with: --type sap_library --parameterfile ${library_parameter_file_name} --storageaccountname ${REMOTE_STATE_SA}  --deployer_tfstate_key ${deployer_tfstate_key} ${autoApproveParameter} ${ado_flag}"

	if ! "${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/installer.sh" \
		--type sap_library \
		--parameterfile "${library_parameter_file_name}" \
		--storageaccountname "${REMOTE_STATE_SA}" \
		--deployer_tfstate_key "${deployer_tfstate_key}" \
		$ado_flag \
		$autoApproveParameter; then
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       ${bold_red}  Migrating the Library state failed ${reset_formatting}                           #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""
		step=4
		save_config_var "step" "${deployer_config_information}"
		exit 40
	else
		return_code=$?
		echo "#########################################################################################"
		echo "#                                                                                       #"
		echo -e "#                       ${cyan}  Migrating the Library state succeeded ${reset_formatting}                        #"
		echo "#                                                                                       #"
		echo "#########################################################################################"
		echo ""
	fi

	cd "$root_dirname" || exit

	step=5
	save_config_var "step" "${deployer_config_information}"
fi

printf -v kvname '%-40s' "${keyvault}"
printf -v dep_ip '%-40s' "${deployer_public_ip_address}"
printf -v storage_account '%-40s' "${REMOTE_STATE_SA}"
echo ""
echo "#########################################################################################"
echo "#                                                                                       #"
echo -e "# $cyan Please save these values: $reset_formatting                                                           #"
echo "#     - Key Vault:       ${kvname}                       #"
echo "#     - Deployer IP:     ${dep_ip}                       #"
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
| Keyvault Name           | ${kvname}            |
| Deployer IP             | ${dep_ip}            |
| Terraform state         | ${storage_account}   |

EOF

cat "${deployer_config_information}".md

deployer_keyvault="${keyvault}"
export deployer_keyvault

if [ -n "${deployer_public_ip_address}" ]; then
	deployer_ip="${deployer_public_ip_address}"
	export deployer_ip
fi

terraform_state_storage_account="${REMOTE_STATE_SA}"
export terraform_state_storage_account

if [ 5 -eq $step ]; then
	if [ "${ado_flag}" != "--ado" ]; then
		cd "${current_directory}" || exit

		load_config_vars "${deployer_config_information}" "sshsecret"
		load_config_vars "${deployer_config_information}" "keyvault"
		load_config_vars "${deployer_config_information}" "deployer_public_ip_address"
		if [ ! -f /etc/profile.d/deploy_server.sh ]; then
			# Only run this when not on deployer
			echo "#########################################################################################"
			echo "#                                                                                       #"
			echo -e "#                         $cyan  Copying the parameterfiles $reset_formatting                                 #"
			echo "#                                                                                       #"
			echo "#########################################################################################"
			echo ""

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
fi

step=3
save_config_var "step" "${deployer_config_information}"
echo "##vso[task.setprogress value=100;]Progress Indicator"

unset TF_DATA_DIR

exit 0

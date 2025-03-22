#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

green="\e[1;32m"
reset="\e[0m"
bold_red="\e[1;31m"
cyan="\e[1;36m"

# External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"

SCRIPT_NAME="$(basename "$0")"


banner_title="Set Workload Zone Secrets"

#call stack has full script name when using source
# shellcheck disable=SC1091
source "${grand_parent_directory}/deploy_utils.sh"

#call stack has full script name when using source
source "${parent_directory}/helper.sh"

DEBUG=False

if [ "$SYSTEM_DEBUG" = True ]; then
	set -x
	DEBUG=True
	echo "Environment variables:"
	printenv | sort

fi
export DEBUG
set -eu

print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

echo "##vso[build.updatebuildnumber]Setting the deployment credentials for the SAP Workload zone defined in $ZONE"

cd "${CONFIG_REPO_PATH}" || exit
git checkout -q "$BUILD_SOURCEBRANCHNAME"

echo -e "$green--- Validations ---$reset"
if [ "$USE_MSI" != "true" ]; then

	if ! printenv ARM_SUBSCRIPTION_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_SUBSCRIPTION_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv CLIENT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv CLIENT_SECRET; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_SECRET was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv TENANT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_TENANT_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi
fi

# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
	configureNonDeployer "$(tf_version)"
	echo -e "$green--- az login ---$reset"
	if ! LogonToAzure false; then
		print_banner "$banner_title" "Login to Azure failed" "error"
		echo "##vso[task.logissue type=error]az login failed."
		exit 2
	fi
else
	ARM_USE_MSI=true
	export ARM_USE_MSI
	ARM_CLIENT_ID=$(grep -m 1 "export ARM_CLIENT_ID=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export ARM_CLIENT_ID

fi
# Print the execution environment details
print_header
GROUP_ID=0
if get_variable_group_id "$VARIABLE_GROUP" ;

then
	VARIABLE_GROUP_ID=$GROUP_ID
else
	echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset"
	echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
	exit 2
fi
export VARIABLE_GROUP_ID

if (get_variable_group_id "$PARENT_VARIABLE_GROUP") ;
then
	PARENT_VARIABLE_GROUP_ID=$GROUP_ID
else
	echo -e "$bold_red--- Variable group $PARENT_VARIABLE_GROUP not found ---$reset"
	echo "##vso[task.logissue type=error]Variable group $PARENT_VARIABLE_GROUP not found."
	exit 2
fi
export PARENT_VARIABLE_GROUP_ID

az account set --subscription "$ARM_SUBSCRIPTION_ID"

echo ""

az devops configure --defaults organization=$SYSTEM_COLLECTIONURI project=$SYSTEM_TEAMPROJECTID --output none

environment_file_name="$CONFIG_REPO_PATH/.sap_deployment_automation/${CONTROL_PLANE_NAME}"

APPLICATION_CONFIGURATION_ID=$(az pipelines variable-group variable list --group-id "${PARENT_VARIABLE_GROUP_ID}" --query "APPLICATION_CONFIGURATION_ID.value" --output tsv)
if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then

	key_vault_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultResourceId" "${CONTROL_PLANE_NAME}")
	if [ -z "$key_vault_id" ]; then
		echo "##vso[task.logissue type=warning]Key '${CONTROL_PLANE_NAME}_KeyVaultResourceId' was not found in the application configuration ( '$application_configuration_name' )."
	fi
	WZ_APPLICATION_CONFIGURATION_ID=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "APPLICATION_CONFIGURATION_ID.value" --output tsv)
	if [ -z "$WZ_APPLICATION_CONFIGURATION_ID" ]; then
		az pipelines variable-group variable create --group-id "${VARIABLE_GROUP_ID}" --name "APPLICATION_CONFIGURATION_ID" --value "$APPLICATION_CONFIGURATION_ID" --output none
	else
		az pipelines variable-group variable update --group-id "${VARIABLE_GROUP_ID}" --name "APPLICATION_CONFIGURATION_ID" --value "$APPLICATION_CONFIGURATION_ID" --output none
	fi
else
	load_config_vars "${environment_file_name}" "keyvault"
	key_vault="$keyvault"
	key_vault_id=$(az resource list --name "${keyvault}" --subscription "$ARM_SUBSCRIPTION_ID" --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" -o tsv)

fi

echo -e "$green--- Read parameter values ---$reset"

deployer_tfstate_key=$CONTROL_PLANE_NAME.terraform.tfstate
export deployer_tfstate_key

keyvault_subscription_id=$(echo "$key_vault_id" | cut -d '/' -f 3)
key_vault=$(echo "$key_vault_id" | cut -d '/' -f 9)

if [ -z "$key_vault" ]; then
	echo "##vso[task.logissue type=error]Key vault name (${CONTROL_PLANE_NAME}_KeyVaultName) was not found in the application configuration ( '$application_configuration_name' ) or in configuration file ( ${environment_file_name} )."
	print_banner "$banner_title" "Key vault name (${CONTROL_PLANE_NAME}_KeyVaultName) was not found in the application configuration ( '$application_configuration_name' ) or in configuration file ( ${environment_file_name}" "error"
	exit 2
fi

if [ "$USE_MSI" != "true" ]; then

	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "${CONTROL_PLANE_NAME}" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --client_id "$CLIENT_ID" --client_secret "$CLIENT_SECRET" --client_tenant_id "$TENANT_ID" --ado; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
else
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "${CONTROL_PLANE_NAME}" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --msi --ado; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi

fi
print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

green="\e[1;32m"
reset="\e[0m"
bold_red="\e[1;31m"
cyan="\e[1;36m"

# Source the shared platform configuration
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/shared_platform_config.sh"
. ${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/pipeline_scripts/v2/shared_functions.sh

# External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"

SCRIPT_NAME="$(basename "$0")"

banner_title="Store credentials in Key Vault"

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
echo "Environment variables:"
printenv | sort

print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

return_code=0

echo -e "$green--- Validations ---$reset"
if [ "$USE_MSI" != "true" ]; then
	print_banner "$banner_title" "Using Service Principals for deployment" "info"

	if ! printenv CLIENT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_ID was not defined in the variable group/environment."
		exit 2
	fi

	if ! printenv CLIENT_SECRET; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_SECRET was not defined in the variable group/environment."
		exit 2
	fi

	if ! printenv TENANT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_TENANT_ID was not defined in the variable group/environment."
		exit 2
	fi
else
	print_banner "$banner_title" "Using Managed Identities for deployment" "info"
fi

# Print the execution environment details
print_header

echo ""
deployer_environment_file_name="$CONFIG_REPO_PATH/.sap_deployment_automation/$CONTROL_PLANE_NAME"

APPLICATION_CONFIGURATION_NAME=$(grep -m1 "^APPLICATION_CONFIGURATION_NAME" "${deployer_environment_file_name}" | awk -F'=' '{print $2}' | xargs || true)
if [ -n "${APPLICATION_CONFIGURATION_NAME}" ]; then
	echo "APPLICATION_CONFIGURATION_NAME:       ${APPLICATION_CONFIGURATION_NAME}"
fi
# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then
	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID
	echo "##vso[build.updatebuildnumber]Setting the deployment credentials for the Key Vault defined in $ZONE"
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
	if [[ ! -v $DEPLOYER_KEYVAULT ]]; then
		DEPLOYER_KEYVAULT=$(get_value_with_key DEPLOYER_KEYVAULT "$CONTROL_PLANE_NAME")
	fi
fi

echo -e "$green--- Read parameter values ---$reset"
key_vault="$DEPLOYER_KEYVAULT"
key_vault_id=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$DEPLOYER_KEYVAULT' | project id, name, subscription" --query data[0].id --output tsv)

keyvault_subscription_id=$(echo "$key_vault_id" | cut -d '/' -f 3)

if [ -z "$key_vault" ]; then
	echo "##vso[task.logissue type=error]Key vault name (${CONTROL_PLANE_NAME}_KeyVaultName) was not found in the application configuration ( '$APP_CONFIGURATION_NAME')."
	exit 2
fi

if [ "$USE_MSI" != "true" ]; then
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --client_id "$CLIENT_ID" --client_secret "$CLIENT_SECRET" --client_tenant_id "$TENANT_ID" --ado; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
else
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
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

#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"

SCRIPT_NAME="$(basename "$0")"

banner_title="Set Secrets in Key Vault"

#call stack has full script name when using source

# shellcheck disable=SC1091
source "${script_directory}/shared_platform_config.sh"
# shellcheck disable=SC1091
source "${script_directory}/shared_functions.sh"
# shellcheck disable=SC1091
source "${script_directory}/set-colors.sh"

# shellcheck disable=SC1091
source "${grand_parent_directory}/deploy_utils.sh"
# shellcheck disable=SC1091
source "${parent_directory}/helper.sh"

# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then

	platform_flag="--ado"

	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset_formatting"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID

	if [ -v DEPLOYER_KEYVAULT ]; then
		echo -e "$green--- DEPLOYER_KEYVAULT already set ---$reset_formatting"
	else
		if [ -v PARENT_VARIABLE_GROUP ]; then
			PARENT_VARIABLE_GROUP_ID=0

			if get_variable_group_id "$PARENT_VARIABLE_GROUP" "PARENT_VARIABLE_GROUP_ID"; then
				DEPLOYER_KEYVAULT=$(az pipelines variable-group variable list --group-id "${PARENT_VARIABLE_GROUP_ID}" --query "DEPLOYER_KEYVAULT.value" --output tsv)
				saveVariableInVariableGroup "${VARIABLE_GROUP_ID}" "DEPLOYER_KEYVAULT" "$DEPLOYER_KEYVAULT"

				export PARENT_VARIABLE_GROUP_ID
			else
				echo -e "$bold_red--- Variable group $PARENT_VARIABLE_GROUP not found ---$reset"
				echo "##vso[task.logissue type=error]Variable group $PARENT_VARIABLE_GROUP not found."
				exit 2
			fi
		fi
	fi

	echo -e "$green--- az login ---$reset"
	LogonToAzure "$USE_MSI"
	return_code=$?
	if [ 0 != $return_code ]; then
		echo -e "$bold_red--- Login failed ---$reset"
		echo "##vso[task.logissue type=error]az login failed."
		exit $return_code
	fi

elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
	export VARIABLE_GROUP_ID="$ZONE"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
	platform_flag="--github"
fi

DEBUG=false

if [ "${SYSTEM_DEBUG:-false}" = true ]; then
	set -x
	DEBUG=true
	echo "Environment variables:"
	printenv | sort

fi
export DEBUG
set -eu

print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

# Set platform-specific output
if [ "$PLATFORM" == "devops" ]; then
	echo "##vso[build.updatebuildnumber]Setting the secrets for $CONTROL_PLANE_NAME "
fi

return_code=0

echo -e "$green--- Checkout $BUILD_SOURCEBRANCHNAME ---$reset"

cd "${CONFIG_REPO_PATH}" || exit
git checkout -q "$BUILD_SOURCEBRANCHNAME"

echo -e "$green--- Validations ---$reset"
if [ "$USE_MSI" != "true" ]; then
	print_banner "$banner_title" "Using Service Principals for deployment" "info"

	if ! printenv ARM_SUBSCRIPTION_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_SUBSCRIPTION_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv ARM_CLIENT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv ARM_CLIENT_SECRET; then
		echo "##vso[task.logissue type=error]Variable ARM_CLIENT_SECRET was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi

	if ! printenv ARM_TENANT_ID; then
		echo "##vso[task.logissue type=error]Variable ARM_TENANT_ID was not defined in the $VARIABLE_GROUP variable group."
		exit 2
	fi
else
	print_banner "$banner_title" "Using Managed Identities for deployment" "info"
fi

# Print the execution environment details
print_header

if [ ! -v APPLICATION_CONFIGURATION_ID ]; then
	APPLICATION_CONFIGURATION_ID=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$APPLICATION_CONFIGURATION_NAME' | project id, name, subscription" --query data[0].id --output tsv)
	export APPLICATION_CONFIGURATION_ID
fi
APPLICATION_CONFIGURATION_SUBSCRIPTION_ID=$(echo "$APPLICATION_CONFIGURATION_ID" | cut -d '/' -f 3)
export APPLICATION_CONFIGURATION_SUBSCRIPTION_ID

az account set --subscription "$ARM_SUBSCRIPTION_ID"

echo -e "$green--- Read parameter values ---$reset"

deployer_tfstate_key=$CONTROL_PLANE_NAME.terraform.tfstate
export deployer_tfstate_key
if [ -z "$DEPLOYER_KEYVAULT" ]; then
	key_vault_id=$(get_value_with_key "${CONTROL_PLANE_NAME}_KeyVaultResourceId")
	if [ -z "$key_vault_id" ]; then
		echo "##vso[task.logissue type=warning]Key '${CONTROL_PLANE_NAME}_KeyVaultResourceId' was not found in the application configuration ( '$APPLICATION_CONFIGURATION_NAME' )."
	else
		keyvault_subscription_id=$(echo "$key_vault_id" | cut -d '/' -f 3)
		key_vault=$(echo "$key_vault_id" | cut -d '/' -f 9)
	fi
else
	if [ ! -v key_vault_id ]; then
		key_vault_id=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$DEPLOYER_KEYVAULT' | project id, name, subscription,subscriptionId" --query data[0].id --output tsv)
		export key_vault_id
	fi
	keyvault_subscription_id=$(echo "$key_vault_id" | cut -d '/' -f 3)
	key_vault=$(echo "$key_vault_id" | cut -d '/' -f 9)
fi

if [ -z "$key_vault" ]; then
	echo "##vso[task.logissue type=error]Key vault name (${CONTROL_PLANE_NAME}_KeyVaultName) was not found in the application configuration ( '$APPLICATION_CONFIGURATION_NAME')."
	exit 2
fi

if [ "$USE_MSI" != "true" ]; then
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --client_id "$ARM_CLIENT_ID" --client_secret "$ARM_CLIENT_SECRET" --client_tenant_id "$ARM_TENANT_ID" "$platform_flag"; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
else
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "${key_vault}" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --msi "$platform_flag"; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
fi

print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

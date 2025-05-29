#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Source the shared platform configuration
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/shared_platform_config.sh"
source "${SCRIPT_DIR}/shared_functions.sh"
source "${SCRIPT_DIR}/set-colors.sh"

SCRIPT_NAME="$(basename "$0")"

# Set platform-specific output
if [ "$PLATFORM" == "devops" ]; then
	echo "##vso[build.updatebuildnumber]Deploying the control plane defined in $CONTROL_PLANE_NAME "
fi

#External helper functions

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"

# Source helper scripts
source "${parent_directory}/helper.sh"
source "${grand_parent_directory}/deploy_utils.sh"

# Print the execution environment details
print_header
echo ""

# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then
	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset_formatting"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
	export VARIABLE_GROUP_ID="$ZONE"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
fi


print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

return_code=0

echo -e "$green--- Validations ---$reset_formatting"
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

if [ -z "$DEPLOYER_KEYVAULT" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo -e "$bold_red--- DEPLOYER_KEYVAULT is not defined ---$reset_formatting"
		echo "##vso[task.logissue type=error]DEPLOYER_KEYVAULT is not defined."
		exit 2
	elif [ "$PLATFORM" == "github" ]; then
		echo -e "$bold_red--- DEPLOYER_KEYVAULT is not defined ---$reset_formatting"
	fi
fi

# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then
	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset_formatting"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID
	echo "##vso[build.updatebuildnumber]Setting the deployment credentials for the Key Vault defined in $ZONE"
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
fi

echo -e "$green--- Read parameter values ---$reset_formatting"
keyvault_subscription_id=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$DEPLOYER_KEYVAULT' | project id, name, subscription,subscriptionId" --query data[0].subscriptionId --output tsv)

if [ "$USE_MSI" != "true" ]; then
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "$DEPLOYER_KEYVAULT" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --client_id "$CLIENT_ID" --client_secret "$CLIENT_SECRET" --client_tenant_id "$TENANT_ID" --devops; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
else
	if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/set_secrets_v2.sh" --prefix "$ZONE" --key_vault "$DEPLOYER_KEYVAULT" --keyvault_subscription "$keyvault_subscription_id" \
		--subscription "$ARM_SUBSCRIPTION_ID" --msi --devops; then
		return_code=$?
	else
		return_code=$?
		print_banner "$banner_title - Set secrets" "Set_secrets failed" "error"
		exit $return_code
	fi
fi

print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

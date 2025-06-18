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

# External helper functions
#. "$(dirname "${BASH_SOURCE[0]}")/deploy_utils.sh"
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"
#call stack has full script name when using source
# shellcheck disable=SC1091
source "${grand_parent_directory}/deploy_utils.sh"
source "${parent_directory}/helper.sh"

SCRIPT_NAME="$(basename "$0")"

banner_title="SAP Workload Zone"
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
	platform_flag="--ado"
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
	export VARIABLE_GROUP_ID="${WORKLOAD_ZONE_NAME}"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
	platform_flag="--github"
else
	platform_flag=""
fi

print_banner "$banner_title" "Entering $SCRIPT_NAME" "info"

tfvarsFile="LANDSCAPE/${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE/${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars"

cd "${CONFIG_REPO_PATH}" || exit
mkdir -p .sap_deployment_automation
# Platform-specific git checkout
if [ "$PLATFORM" == "devops" ]; then
	echo -e "$green--- Checkout $BUILD_SOURCEBRANCHNAME ---$reset_formatting"
	git checkout -q "$BUILD_SOURCEBRANCHNAME"
elif [ "$PLATFORM" == "github" ]; then
	echo -e "$green--- Checkout $GITHUB_REF_NAME ---$reset_formatting"
	git checkout -q "$GITHUB_REF_NAME"
fi

if [ ! -f "$tfvarsFile" ]; then
	print_banner "$banner_title" "${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars was not found" "error"
	echo "##vso[task.logissue type=error]File ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars was not found."
	exit 2
fi

# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
	if [ "$PLATFORM" == "devops" ]; then
		configureNonDeployer "${tf_version:-1.11.2}"

		ARM_CLIENT_ID="$servicePrincipalId"
		export ARM_CLIENT_ID
		TF_VAR_spn_id=$ARM_CLIENT_ID
		export TF_VAR_spn_id

		if printenv servicePrincipalKey; then
			unset ARM_OIDC_TOKEN
			ARM_CLIENT_SECRET="$servicePrincipalKey"
			export ARM_CLIENT_SECRET
		else
			ARM_OIDC_TOKEN="$idToken"
			export ARM_OIDC_TOKEN
			ARM_USE_OIDC=true
			export ARM_USE_OIDC
			unset ARM_CLIENT_SECRET
		fi

		ARM_TENANT_ID="$tenantId"
		export ARM_TENANT_ID
	fi
else
	if [ "$USE_MSI" == "true" ]; then
		TF_VAR_use_spn=false
		export TF_VAR_use_spn
		ARM_USE_MSI=true
		export ARM_USE_MSI
		echo "Deployment using:                    Managed Identity"
	else
		TF_VAR_use_spn=true
		export TF_VAR_use_spn
		ARM_USE_MSI=false
		export ARM_USE_MSI
		echo "Deployment using:                    Service Principal"
	fi
	ARM_CLIENT_ID=$(grep -m 1 "export ARM_CLIENT_ID=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export ARM_CLIENT_ID
fi

if [ -v APPLICATION_CONFIGURATION_NAME ]; then
	APPLICATION_CONFIGURATION_ID=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$APPLICATION_CONFIGURATION_NAME' | project id, name, subscription" --query data[0].id --output tsv)
	export APPLICATION_CONFIGURATION_ID
fi

ENVIRONMENT=$(grep -m1 "^environment" "$tfvarsFile" | awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"')
LOCATION=$(grep -m1 "^location" "$tfvarsFile" | awk -F'=' '{print $2}' | tr '[:upper:]' '[:lower:]' | tr -d ' \t\n\r\f"')
NETWORK=$(grep -m1 "^network_logical_name" "$tfvarsFile" | awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"')

ENVIRONMENT_IN_FILENAME=$(echo ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE | awk -F'-' '{print $1}')
LOCATION_CODE_IN_FILENAME=$(echo ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE | awk -F'-' '{print $2}')
LOCATION_IN_FILENAME=$(get_region_from_code "$LOCATION_CODE_IN_FILENAME" || true)

NETWORK_IN_FILENAME=$(echo ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE | awk -F'-' '{print $3}')

landscape_tfstate_key="${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.terraform.tfstate"
export landscape_tfstate_key
workload_environment_file_name="$CONFIG_REPO_PATH/.sap_deployment_automation/$WORKLOAD_ZONE_NAME"

deployer_tfstate_key=$CONTROL_PLANE_NAME-INFRASTRUCTURE.terraform.tfstate
export deployer_tfstate_key

echo ""
echo -e "${green}Deployment details:"
echo -e "-------------------------------------------------------------------------------$reset_formatting"

echo "Workload TFvars:                     ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars"
echo "CONTROL_PLANE_NAME:                  $CONTROL_PLANE_NAME"
echo "WORKLOAD_ZONE_NAME:                  $WORKLOAD_ZONE_NAME"
echo "Workload Zone Environment File:      $workload_environment_file_name"
echo ""
echo "Environment:                         $ENVIRONMENT"
echo "Environment(filename):               $ENVIRONMENT_IN_FILENAME"
echo "Location:                            $LOCATION"
echo "Location(filename):                  $LOCATION_IN_FILENAME"
echo "Network:                             $NETWORK"
echo "Network(filename):                   $NETWORK_IN_FILENAME"

echo ""

if [ "$ENVIRONMENT" != "$ENVIRONMENT_IN_FILENAME" ]; then
	print_banner "$banner_title" "The 'environment' setting in $SAP_SYSTEM_TFVARS_FILENAME does not match the file name" "error" "Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	echo "##vso[task.logissue type=error]The environment setting in ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars '$ENVIRONMENT' does not match the ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars file name '$ENVIRONMENT_IN_FILENAME'. Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	exit 2
fi

if [ "$LOCATION" != "$LOCATION_IN_FILENAME" ]; then
	print_banner "$banner_title" "The 'location' setting in $SAP_SYSTEM_TFVARS_FILENAME does not match the file name" "error" "Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	echo "##vso[task.logissue type=error]The location setting in ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars '$LOCATION' does not match the ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars file name '$LOCATION_IN_FILENAME'. Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	exit 2
fi

if [ "$NETWORK" != "$NETWORK_IN_FILENAME" ]; then
	print_banner "$banner_title" "The 'network_logical_name' setting in $SAP_SYSTEM_TFVARS_FILENAME does not match the file name" "error" "Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	echo "##vso[task.logissue type=error]The network_logical_name setting in ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars '$NETWORK' does not match the ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars file name '$NETWORK_IN_FILENAME-. Filename should have the pattern [ENVIRONMENT]-[REGION_CODE]-[NETWORK_LOGICAL_NAME]-INFRASTRUCTURE"
	exit 2
fi

dos2unix -q "${workload_environment_file_name}"

if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then

	application_configuration_name=$(echo "$APPLICATION_CONFIGURATION_ID" | cut -d '/' -f 9)

	TF_VAR_management_subscription_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_SubscriptionId" "${CONTROL_PLANE_NAME}")
	export TF_VAR_management_subscription_id

	key_vault=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultName" "${CONTROL_PLANE_NAME}")
	key_vault_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultResourceId" "${CONTROL_PLANE_NAME}")
	if [ -z "$key_vault_id" ]; then
		echo "##vso[task.logissue type=warning]Key '${CONTROL_PLANE_NAME}_KeyVaultResourceId' was not found in the application configuration ( '$application_configuration_name' )."
	fi
	tfstate_resource_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId" "${CONTROL_PLANE_NAME}")
	if [ -z "$tfstate_resource_id" ]; then
		echo "##vso[task.logissue type=warning]Key '${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId' was not found in the application configuration ( '$application_configuration_name' )."
	fi
	workload_key_vault=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${WORKLOAD_ZONE_NAME}_KeyVaultName" "${WORKLOAD_ZONE_NAME}")
else
	echo "##vso[task.logissue type=warning]Variable APPLICATION_CONFIGURATION_ID was not defined."
	load_config_vars "${workload_environment_file_name}" "keyvault"
	# shellcheck disable=SC2154
	key_vault="$keyvault"
	load_config_vars "${workload_environment_file_name}" "tfstate_resource_id"
	key_vault_id=$(az resource list --name "${keyvault}" --subscription "$ARM_SUBSCRIPTION_ID" --resource-type Microsoft.KeyVault/vaults --query "[].id | [0]" -o tsv)
fi

if [ -z "$key_vault" ]; then
	echo "##vso[task.logissue type=error]Key vault name (${CONTROL_PLANE_NAME}_KeyVaultName) was not found in the application configuration ( '$application_configuration_name' nor was it defined in ${workload_environment_file_name})."
	exit 2
fi

if [ -z "$tfstate_resource_id" ]; then
	echo "##vso[task.logissue type=error]Terraform state storage account resource id ('${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId') was not found in the application configuration ( '$application_configuration_name' nor was it defined in ${workload_environment_file_name})."
	exit 2
fi

export TF_VAR_spn_keyvault_id=${key_vault_id}

terraform_storage_account_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 9)
terraform_storage_account_resource_group_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 5)
terraform_storage_account_subscription_id=$(echo "$tfstate_resource_id" | cut -d '/' -f 3)

export terraform_storage_account_name
export terraform_storage_account_resource_group_name
export terraform_storage_account_subscription_id
export tfstate_resource_id

export workload_key_vault

echo ""
echo -e "${green}Terraform parameter information:"
echo -e "-------------------------------------------------------------------------------$reset_formatting"
echo "Deployer state file:                 $deployer_tfstate_key"
echo "Workload state file:                 $landscape_tfstate_key"
echo "Deployer Key vault:                  $key_vault"
echo "Workload Key vault:                  ${workload_key_vault}"
echo "Statefile subscription:              $terraform_storage_account_subscription_id"
echo "Statefile storage account:           $terraform_storage_account_name"
echo ""
echo "Target subscription:                 $ARM_SUBSCRIPTION_ID"

cd "$CONFIG_REPO_PATH/LANDSCAPE/${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE" || exit
return_code=10

if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/remover_v2.sh" --parameter_file "${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars" --type sap_landscape \
	--control_plane_name "${CONTROL_PLANE_NAME}" --application_configuration_name "${APPLICATION_CONFIGURATION_NAME}" \
	--workload_zone_name "${WORKLOAD_ZONE_NAME}" \
	--ado --auto-approve; then
	return_code=$?
	print_banner "$banner_title" "The removal of ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars succeeded" "success" "Return code: ${return_code}"
else
	return_code=$?
	print_banner "$banner_title" "The removal of ${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars failed" "error" "Return code: ${return_code}"
fi

echo "Return code from deployment:         ${return_code}"
if [ 0 != $return_code ]; then
	echo "##vso[task.logissue type=error]Return code from remover $return_code."
else
	if [ 0 == $return_code ]; then
		# Pull changes
		# Pull latest changes from appropriate branch
		if [ "$PLATFORM" == "devops" ]; then
			git pull -q origin "$BUILD_SOURCEBRANCHNAME"
		elif [ "$PLATFORM" == "github" ]; then
			git pull -q origin "$GITHUB_REF_NAME"
		fi

		git clean -d -f -X

		if [ -f ".terraform/terraform.tfstate" ]; then
			git rm --ignore-unmatch -q --ignore-unmatch ".terraform/terraform.tfstate"
			changed=1
		fi

		if [ -d ".terraform" ]; then
			git rm -q -r --ignore-unmatch ".terraform"
			changed=1
		fi

		if [ -f "${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars" ]; then
			git add "${WORKLOAD_ZONE_NAME}-INFRASTRUCTURE.tfvars"
			changed=1
		fi

		if [ -d "logs" ]; then
			git rm -q -r --ignore-unmatch "logs"
			changed=1
		fi

		# Commit changes based on platform
		if [ 1 == $changed ]; then
			if [ "$PLATFORM" == "devops" ]; then
				git config --global user.email "$BUILD_REQUESTEDFOREMAIL"
				git config --global user.name "$BUILD_REQUESTEDFOR"
				commit_message="Added updates from Workload zone removal for $WORKLOAD_ZONE_NAME  [skip ci]"
			elif [ "$PLATFORM" == "github" ]; then
				git config --global user.email "github-actions@github.com"
				git config --global user.name "GitHub Actions"
				commit_message="Added updates from Workload zone removal for $WORKLOAD_ZONE_NAME [skip ci]"
			else
				git config --global user.email "local@example.com"
				git config --global user.name "Local User"
				commit_message="Added updates from Workload zone removal for $WORKLOAD_ZONE_NAME [skip ci]"
			fi

			if [ "$DEBUG" = True ]; then
				git status --verbose
				if git commit --message --verbose "$commit_message"; then
					if [ "$PLATFORM" == "devops" ]; then
						if ! git -c http.extraheader="AUTHORIZATION: bearer $SYSTEM_ACCESSTOKEN" push --set-upstream origin "$BUILD_SOURCEBRANCHNAME" --force-with-lease; then
							echo "Failed to push changes to the repository."
						fi
					elif [ "$PLATFORM" == "github" ]; then
						if ! git push --set-upstream origin "$GITHUB_REF_NAME" --force-with-lease; then
							echo "Failed to push changes to the repository."
						fi
					fi
				fi
			else
				if git commit -m "$commit_message"; then
					if [ "$PLATFORM" == "devops" ]; then
						if ! git -c http.extraheader="AUTHORIZATION: bearer $SYSTEM_ACCESSTOKEN" push --set-upstream origin "$BUILD_SOURCEBRANCHNAME" --force-with-lease; then
							echo "Failed to push changes to the repository."
						fi
					elif [ "$PLATFORM" == "github" ]; then
						if ! git push --set-upstream origin "$GITHUB_REF_NAME" --force-with-lease; then
							echo "Failed to push changes to the repository."
						fi
					fi
				fi
			fi
		fi

		echo -e "$green--- Deleting variables ---$reset_formatting"
		if [ -n "$VARIABLE_GROUP_ID" ]; then
			print_banner "Remove workload zone" "Deleting variables" "info"

			variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "CONTROL_PLANE_NAME.value" --out tsv)
			if [ ${#variable_value} != 0 ]; then
				az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name CONTROL_PLANE_NAME --yes --only-show-errors
			fi

			variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "APPLICATION_CONFIGURATION_ID.value" --out tsv)
			if [ ${#variable_value} != 0 ]; then
				az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name APPLICATION_CONFIGURATION_ID --yes --only-show-errors
			fi
		fi

	fi
fi

print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

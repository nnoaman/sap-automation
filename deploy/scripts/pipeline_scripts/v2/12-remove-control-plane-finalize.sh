#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

echo "##vso[build.updatebuildnumber]Removing the control plane defined in $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME"
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

#call stack has full script name when using source
source "${parent_directory}/helper.sh"
source "${grand_parent_directory}/deploy_utils.sh"

DEBUG=False

if [ "$SYSTEM_DEBUG" = True ]; then
	set -x
	set -eu
	DEBUG=True
fi

export DEBUG
# Ensure that the exit status of a pipeline command is non-zero if any
# stage of the pipefile has a non-zero exit status.
set -o pipefail

cd "$CONFIG_REPO_PATH" || exit

deployerTFvarsFile="${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME"
libraryTFvarsFile="${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME"
deployer_tfstate_key="$DEPLOYER_FOLDERNAME.terraform.tfstate"

echo ""
echo -e "$cyan Starting the removal of the deployer and its associated infrastructure $reset"
echo ""

echo -e "$green--- File Validations ---$reset"

if [ ! -f "$deployerTFvarsFile" ]; then
	echo -e "$bold_red--- File ${deployerTFvarsFile} was not found ---$reset"
	echo "##vso[task.logissue type=error]File DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME was not found."
	exit 2
fi

if [ ! -f "${libraryTFvarsFile}" ]; then
	echo -e "$bold_red--- File ${libraryTFvarsFile}  was not found ---$reset"
	echo "##vso[task.logissue type=error]File LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME was not found."
	exit 2
fi

TF_VAR_deployer_tfstate_key="$deployer_tfstate_key"
export TF_VAR_deployer_tfstate_key

CONTROL_PLANE_NAME=$(echo "$DEPLOYER_FOLDERNAME" | cut -d'-' -f1-3)
export "CONTROL_PLANE_NAME"

deployer_environment_file_name="${CONFIG_REPO_PATH}/.sap_deployment_automation/$CONTROL_PLANE_NAME"

echo -e "$green--- Information ---$reset"

echo ""
echo "Control Plane Name:                  ${CONTROL_PLANE_NAME}"
echo "Agent:                               $THIS_AGENT"
echo "Organization:                        $SYSTEM_COLLECTIONURI"
echo "Project:                             $SYSTEM_TEAMPROJECT"
echo "Environment file:                    $deployer_environment_file_name"
if [ -n "$POOL" ]; then
	echo "Deployer Agent Pool:                 $POOL"
fi

echo -e "$green--- Configure devops CLI extension ---$reset"
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors
az extension add --name azure-devops --output none --only-show-errors
az devops configure --defaults organization="$SYSTEM_COLLECTIONURI" project="$SYSTEM_TEAMPROJECT" --output none --only-show-errors

if [[ -f /etc/profile.d/deploy_server.sh ]]; then
	path=$(grep -m 1 "export PATH=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
	export PATH=$PATH:$path
fi

VARIABLE_GROUP_ID=$(az pipelines variable-group list --query "[?name=='$PARENT_VARIABLE_GROUP'].id | [0]")

if [ -z "${VARIABLE_GROUP_ID}" ]; then
	echo "##vso[task.logissue type=error]Variable group $PARENT_VARIABLE_GROUP could not be found."
	exit 2
fi

if [ -z "$ARM_SUBSCRIPTION_ID" ]; then
	echo "##vso[task.logissue type=error]Variable ARM_SUBSCRIPTION_ID was not defined."
	exit 2
fi

# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
	configureNonDeployer "$TF_VERSION"

	ARM_CLIENT_ID="$servicePrincipalId"
	export ARM_CLIENT_ID

	ARM_OIDC_TOKEN="$idToken"
	export ARM_OIDC_TOKEN

	ARM_TENANT_ID="$tenantId"
	export ARM_TENANT_ID

	ARM_USE_OIDC=true
	export ARM_USE_OIDC

	ARM_USE_AZUREAD=true
	export ARM_USE_AZUREAD

	unset ARM_CLIENT_SECRET

else
	echo -e "$green--- az login ---$reset"
	LogonToAzure "$USE_MSI"
fi

az account set --subscription "$ARM_SUBSCRIPTION_ID"

key_vault_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultResourceId" "$CONTROL_PLANE_NAME")

if [ -n "${key_vault_id}" ]; then
	if [ "azure pipelines" = "$THIS_AGENT" ]; then
		key_vault_resource_group=$(echo "$key_vault_id" | cut -d'/' -f5)
		key_vault=$(echo "$key_vault_id" | cut -d'/' -f9)

		az keyvault update --name "$key_vault" --resource-group "$key_vault_resource_group" --public-network-access Enabled
		this_ip=$(curl -s ipinfo.io/ip) >/dev/null 2>&1
		az keyvault network-rule add --name "${key_vault}" --ip-address "${this_ip}" --only-show-errors --output
		sleep 30
	fi
fi

cd "$CONFIG_REPO_PATH" || exit
echo -e "$green--- Running the remove_deployer script that destroys deployer VM ---$reset"

if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" ]; then
	pass=${SYSTEM_COLLECTIONID//-/}
	unzip -qq -o -P "${pass}" "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" -d "DEPLOYER/$DEPLOYER_FOLDERNAME"
fi

echo -e "$green--- Running the remove region script that destroys deployer VM and SAP library ---$reset"

cd "$CONFIG_REPO_PATH/DEPLOYER/$DEPLOYER_FOLDERNAME" || exit

if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/remove_deployer_v2.sh" --auto-approve \
	--parameter_file "$DEPLOYER_TFVARS_FILENAME"; then
	return_code=$?
	echo "Control Plane $DEPLOYER_FOLDERNAME removal step 2 completed."
	echo "##vso[task.logissue type=warning]Control Plane $DEPLOYER_FOLDERNAME removal step 2 completed."
else
	return_code=$?
	echo "Control Plane $DEPLOYER_FOLDERNAME removal step 2 failed."
fi

echo "Return code from remove_deployer: $return_code."

echo -e "$green--- Remove Control Plane Part 2 ---$reset"
git checkout -q "$BUILD_SOURCEBRANCHNAME"
git pull -q

if [ 0 == $return_code ]; then
	cd "$CONFIG_REPO_PATH" || exit
	changed=0

	if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/$deployerTFvarsFile" ]; then
		sed -i /"custom_random_id"/d "DEPLOYER/$DEPLOYER_FOLDERNAME/$deployerTFvarsFile"
		git add -f "DEPLOYER/$DEPLOYER_FOLDERNAME/$deployerTFvarsFile"
		changed=1
	fi

	if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate" ]; then
		git rm -q -f --ignore-unmatch "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate"
		changed=1
	fi

	if [ -d "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform" ]; then
		git rm -q -r --ignore-unmatch "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform"
		changed=1
	fi

	if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" ]; then
		git rm -q -f --ignore-unmatch "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip"
		changed=1
	fi

	if [ -f ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}" ]; then
		rm ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}"
		git rm -q --ignore-unmatch ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}"
		changed=1
	fi
	if [ -f ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}.md" ]; then
		rm ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}.md"
		git rm -q --ignore-unmatch ".sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE_IN_FILENAME}.md"
		changed=1
	fi

	if [ 1 == $changed ]; then
		git config --global user.email "$BUILD_REQUESTEDFOREMAIL"
		git config --global user.name "$BUILD_REQUESTEDFOR"
		if git commit -m "Control Plane $DEPLOYER_FOLDERNAME removal step 2[skip ci]"; then
			if git -c http.extraheader="AUTHORIZATION: bearer $SYSTEM_ACCESSTOKEN" push --set-upstream origin "$BUILD_SOURCEBRANCHNAME" --force-with-lease; then
				return_code=$?
				echo "##vso[task.logissue type=warning]Control Plane $DEPLOYER_FOLDERNAME removal step 2 updated in $BUILD_SOURCEBRANCHNAME"
			else
				return_code=$?
				echo "##vso[task.logissue type=error]Failed to push changes to $BUILD_SOURCEBRANCHNAME"
			fi
		fi
	fi
	echo -e "$green--- Deleting variables ---$reset"
	if [ ${#VARIABLE_GROUP_ID} != 0 ]; then
		echo "Deleting variables"

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "Terraform_Remote_Storage_Account_Name.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name Terraform_Remote_Storage_Account_Name --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "Terraform_Remote_Storage_Resource_Group_Name.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name Terraform_Remote_Storage_Resource_Group_Name --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "Terraform_Remote_Storage_Subscription.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name Terraform_Remote_Storage_Subscription --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "Deployer_State_FileName.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name Deployer_State_FileName --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "Deployer_Key_Vault.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name Deployer_Key_Vault --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "WEBAPP_URL_BASE.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name WEBAPP_URL_BASE --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "WEBAPP_IDENTITY.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name WEBAPP_IDENTITY --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "WEBAPP_ID.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name WEBAPP_ID --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "WEBAPP_RESOURCE_GROUP.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name WEBAPP_RESOURCE_GROUP --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "INSTALLATION_MEDIA_ACCOUNT.value")
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name INSTALLATION_MEDIA_ACCOUNT --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "DEPLOYER_RANDOM_ID.value" --out tsv)
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name DEPLOYER_RANDOM_ID --yes --only-show-errors
		fi

		variable_value=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "LIBRARY_RANDOM_ID.value" --out tsv)
		if [ ${#variable_value} != 0 ]; then
			az pipelines variable-group variable delete --group-id "${VARIABLE_GROUP_ID}" --name LIBRARY_RANDOM_ID --yes --only-show-errors
		fi
	fi

fi

exit $return_code

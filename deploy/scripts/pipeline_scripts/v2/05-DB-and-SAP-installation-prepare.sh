#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

echo "##vso[build.updatebuildnumber]Deploying the control plane defined in $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME"
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
readonly SCRIPT_NAME
banner_title="SAP Configuration and Installation"

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

WORKLOAD_ZONE_NAME=$(basename "${SAP_SYSTEM_CONFIGURATION_NAME}" | cut -d'-' -f1-3)

print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

echo -e "$green--- Configure devops CLI extension ---$reset"
az config set extension.use_dynamic_install=yes_without_prompt --output none --only-show-errors

if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then

	management_subscription_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_SubscriptionId" "${CONTROL_PLANE_NAME}")

	key_vault=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${WORKLOAD_ZONE_NAME}_KeyVaultName" "${WORKLOAD_ZONE_NAME}")

fi

cd "$CONFIG_REPO_PATH" || exit

environment_file_name=".sap_deployment_automation/$WORKLOAD_ZONE_NAME"
parameters_filename="$CONFIG_REPO_PATH/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}/sap-parameters.yaml"

az devops configure --defaults organization=$SYSTEM_COLLECTIONURI project='$SYSTEM_TEAMPROJECT' --output none --only-show-errors

echo -e "$green--- Validations ---$reset"

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
	echo "##vso[task.logissue type=error]Variable AZURE_SUBSCRIPTION_ID was not defined."
	exit 2
fi

if [ "azure pipelines" == "$THIS_AGENT" ]; then
	echo "##vso[task.logissue type=error]Please use a self hosted agent for this playbook. Define it in the SDAF-$ENVIRONMENT variable group"
	exit 2
fi

echo -e "$green--- az login ---$reset"
# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
	configureNonDeployer "$(tf_version)"
	echo -e "$green--- az login ---$reset"
	LogonToAzure false
else
	LogonToAzure "$USE_MSI"
fi
return_code=$?
if [ 0 != $return_code ]; then
	echo -e "$bold_red--- Login failed ---$reset"
	echo "##vso[task.logissue type=error]az login failed."
	exit $return_code
fi

echo "##vso[build.updatebuildnumber]Deploying ${SAP_SYSTEM_CONFIGURATION_NAME} using BoM ${BOM_BASE_NAME}"

echo "##vso[task.setvariable variable=SID;isOutput=true]${SID}"
echo "##vso[task.setvariable variable=SAP_PARAMETERS;isOutput=true]sap-parameters.yaml"
echo "##vso[task.setvariable variable=FOLDER;isOutput=true]$CONFIG_REPO_PATH/SYSTEM/$SAP_SYSTEM_CONFIGURATION_NAME"
echo "##vso[task.setvariable variable=HOSTS;isOutput=true]${SID}_hosts.yaml"
echo "##vso[task.setvariable variable=KV_NAME;isOutput=true]$key_vault"

echo "Workload Zone Name:                  $WORKLOAD_ZONE_NAME"
echo "Environment:                         $ENVIRONMENT"
echo "Location:                            $LOCATION"
echo "Virtual network logical name:        $NETWORK"
echo "Keyvault:                            $key_vault"
echo "SAP Application BoM:                 $BOM_BASE_NAME"

echo "SID:                                 ${SID}"
echo "Folder:                              $CONFIG_REPO_PATH/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}"
echo "Hosts file:                          ${SID}_hosts.yaml"
echo "sap_parameters_file:                 $parameters_filename"
echo "Configuration file:                  $environment_file_name"

cd "$CONFIG_REPO_PATH/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}"

echo -e "$green--- Add BOM Base Name and SAP FQDN to sap-parameters.yaml ---$reset"
sed -i 's|bom_base_name:.*|bom_base_name:                 '"$BOM_BASE_NAME"'|' sap-parameters.yaml

mkdir -p artifacts

echo "Workload Key Vault:                  ${key_vault}"

if [ $EXTRA_PARAMETERS = '$(EXTRA_PARAMETERS)' ]; then
	new_parameters=$PIPELINE_EXTRA_PARAMETERS
else
	echo "##vso[task.logissue type=warning]Extra parameters were provided - '$EXTRA_PARAMETERS'"
	new_parameters="$EXTRA_PARAMETERS $PIPELINE_EXTRA_PARAMETERS"
fi

echo "##vso[task.setvariable variable=SSH_KEY_NAME;isOutput=true]${WORKLOAD_ZONE_NAME}-sid-sshkey"
echo "##vso[task.setvariable variable=VAULT_NAME;isOutput=true]$key_vault"
echo "##vso[task.setvariable variable=PASSWORD_KEY_NAME;isOutput=true]${WORKLOAD_ZONE_NAME}-sid-password"
echo "##vso[task.setvariable variable=USERNAME_KEY_NAME;isOutput=true]${WORKLOAD_ZONE_NAME}-sid-username"
echo "##vso[task.setvariable variable=NEW_PARAMETERS;isOutput=true]${new_parameters}"
echo "##vso[task.setvariable variable=CP_SUBSCRIPTION;isOutput=true]${management_subscription_id}"

az keyvault secret show --name "${WORKLOAD_ZONE_NAME}-sid-sshkey" --vault-name "$key_vault" --subscription "$management_subscription_id" --query value -o tsv >"artifacts/${SAP_SYSTEM_CONFIGURATION_NAME}_sshkey"
cp sap-parameters.yaml artifacts/.
cp "${SID}_hosts.yaml" artifacts/.

2> >(while read line; do (echo >&2 "STDERROR: $line"); done)

echo -e "$green--- Done ---$reset"
print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"
exit 0

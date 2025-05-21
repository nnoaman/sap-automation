#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Source the shared platform configuration
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/shared_platform_config.sh"
source "${SCRIPT_DIR}/shared_functions.sh"
source "${SCRIPT_DIR}/set-colors.sh"

SCRIPT_NAME="$(basename "$0")"

green="\e[1;32m"
reset="\e[0m"
bold_red="\e[1;31m"

# External helper functions
full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
grand_parent_directory="$(dirname "$parent_directory")"

SCRIPT_NAME="$(basename "$0")"

banner_title="Prepare for software download"
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

cd "$CONFIG_REPO_PATH" || exit

if [ "$PLATFORM" == "devops" ]; then
	AZURE_DEVOPS_EXT_PAT=$SYSTEM_ACCESSTOKEN
	export AZURE_DEVOPS_EXT_PAT
elif [ "$PLATFORM" == "github" ]; then
	echo "Configuring for GitHub Actions"
fi


environment_file_name=".sap_deployment_automation/$CONTROL_PLANE_NAME"

# Print the execution environment details
print_header

# Configure DevOps
configure_devops

if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID" ;
then
	echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset_formatting"
	echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
	exit 2
fi
export VARIABLE_GROUP_ID


echo -e "$green--- Validations ---$reset_formatting"
# File existence check
if [ ! -f "${environment_file_name}" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]File '${environment_file_name}' was not found."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing File::File '${environment_file_name}' was not found."
	fi
	exit 2
fi

# Required variable: ARM_SUBSCRIPTION_ID
if [ -z "$ARM_SUBSCRIPTION_ID" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Variable 'ARM_SUBSCRIPTION_ID' was not defined."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing Variable::Variable 'ARM_SUBSCRIPTION_ID' was not defined."
	fi
	exit 2
fi

# Agent validation
if [ "$PLATFORM" == "devops" ]; then
	if [ "$THIS_AGENT" == "azure pipelines" ]; then
		echo "##vso[task.logissue type=error]Please use a self-hosted agent for this playbook. Define it in the SDAF-$(environment_code) variable group."
	fi
	exit 2
fi

# SUSERNAME validation
if [ "$SUSERNAME" == "your S User" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Please define the S-Username variable."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing S-Username::Please define the S-Username variable."
	fi
	exit 2
fi

# SPASSWORD validation
if [ "$SPASSWORD" == "your S user password" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Please define the S-Password variable."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing S-Password::Please define the S-Password variable."
	fi
	exit 2
fi

echo -e "$green--- az login ---$reset_formatting"
# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
  configureNonDeployer "$(tf_version)"
    echo -e "$green--- az login ---$reset_formatting"
  LogonToAzure false
fi
return_code=$?
if [ 0 != $return_code ]; then
  echo -e "$bold_red--- Login failed ---$reset_formatting"
  echo "##vso[task.logissue type=error]az login failed."
  exit $return_code
fi

az account set --subscription "$ARM_SUBSCRIPTION_ID" --output none

key_vault=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "Deployer_Key_Vault" "${environment_file_name}" "keyvault")

echo "Keyvault: $key_vault"
echo " ##vso[task.setvariable variable=KV_NAME;isOutput=true]$key_vault"

echo -e "$green--- BoM $BOM ---$reset_formatting"
echo "##vso[build.updatebuildnumber]Downloading BoM defined in $BOM"

echo -e "$green--- Set S-Username and S-Password in the key_vault if not yet there ---$reset_formatting"

SUsername_from_Keyvault=$(az keyvault secret list --vault-name "${key_vault}" --subscription "$ARM_SUBSCRIPTION_ID" --query "[].{Name:name} | [? contains(Name,'S-Username')] | [0]" -o tsv)
if [ "$SUsername_from_Keyvault" == "$SUSERNAME" ]; then
  echo -e "$green--- $SUsername present in keyvault. In case of download errors check that user and password are correct ---$reset_formatting"
else
  echo -e "$green--- Setting the S username in key vault ---$reset_formatting"
  az keyvault secret set --name "S-Username" --vault-name "$key_vault" --value="$SUSERNAME" --subscription "$ARM_SUBSCRIPTION_ID" --expires "$(date -d '+1 year' -u +%Y-%m-%dT%H:%M:%SZ)" --output none
fi

SPassword_from_Keyvault=$(az keyvault secret list --vault-name "${key_vault}" --subscription "$ARM_SUBSCRIPTION_ID" --query "[].{Name:name} | [? contains(Name,'S-Password')] | [0]" -o tsv)
if [ "$SPASSWORD" == "$SPassword_from_Keyvault" ]; then
  echo -e "$green--- Password present in keyvault. In case of download errors check that user and password are correct ---$reset_formatting"
else
  echo -e "$green--- Setting the S user name password in key vault ---$reset_formatting"
  az keyvault secret set --name "S-Password" --vault-name "$key_vault" --value "$SPASSWORD" --subscription "$ARM_SUBSCRIPTION_ID" --expires "$(date -d '+1 year' -u +%Y-%m-%dT%H:%M:%SZ)" --output none

fi

echo "##vso[task.setvariable variable=SUSERNAME;isOutput=true]$SUSERNAME"
echo "##vso[task.setvariable variable=SPASSWORD;isOutput=true]$SPASSWORD"
echo "##vso[task.setvariable variable=BOM_NAME;isOutput=true]$BOM"

echo -e "$green--- Done ---$reset_formatting"
exit 0

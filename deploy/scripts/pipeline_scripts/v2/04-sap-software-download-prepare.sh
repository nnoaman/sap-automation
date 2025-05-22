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

banner_title="Prepare for software download"
#call stack has full script name when using source
# shellcheck disable=SC1091
source "${grand_parent_directory}/deploy_utils.sh"

#call stack has full script name when using source
source "${parent_directory}/helper.sh"


DEBUG=False


set -eu

cd "$CONFIG_REPO_PATH" || exit

if [ "$PLATFORM" == "devops" ]; then
	if [ "$SYSTEM_DEBUG" = True ]; then
		set -x
		DEBUG=True
		echo "Environment variables:"
		printenv | sort
	fi
	export DEBUG
	AZURE_DEVOPS_EXT_PAT=$SYSTEM_ACCESSTOKEN
	export AZURE_DEVOPS_EXT_PAT
elif [ "$PLATFORM" == "github" ]; then
	echo "Configuring for GitHub Actions"
fi


environment_file_name=".sap_deployment_automation/$CONTROL_PLANE_NAME"

# Print the execution environment details
print_header

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
	echo "Configuring for GitHub Actions"
	export VARIABLE_GROUP_ID="${CONTROL_PLANE_NAME}"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
fi


echo -e "$green--- Validations ---$reset_formatting"
if [ ! -f "${environment_file_name}" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]File '${environment_file_name}' was not found."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing File::File '${environment_file_name}' was not found."
	fi
	exit 2
fi

if [ "$PLATFORM" == "devops" ]; then
	key_vault=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "Deployer_Key_Vault" "${environment_file_name}" "keyvault")
elif [ "$PLATFORM" == "github" ]; then
	load_config_vars "${environment_file_name}" "DEPLOYER_KEYVAULT"
	key_vault="$DEPLOYER_KEYVAULT"
fi

if [ -z "$key_vault" ]; then
	if [ "$PLATFORM" == "devops" ]; then
	  echo " ##vso[task.setvariable variable=KV_NAME;isOutput=true]$key_vault"
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing Key Vault::Key Vault was not defined in the variable group."
	fi
	exit 2
fi

if [ -z "$ARM_SUBSCRIPTION_ID" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Variable 'ARM_SUBSCRIPTION_ID' was not defined."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing Variable::Variable 'ARM_SUBSCRIPTION_ID' was not defined."
	fi
	exit 2
fi

if [ "$PLATFORM" == "devops" ]; then
	if [ "$THIS_AGENT" == "azure pipelines" ]; then
		echo "##vso[task.logissue type=error]Please use a self-hosted agent for this playbook. Define it in the SDAF-$(environment_code) variable group."
	fi
	exit 2
fi

if [ -z "$SUSERNAME" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Please define the S-Username variable."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing S-Username::Variable 'SUSERNAME' is not defined or is empty."
	fi
	exit 2
fi

if [ -z "$SPASSWORD" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Please define the S-Password variable."
	elif [ "$PLATFORM" == "github" ]; then
		echo "::error title=Missing S-Password::Variable 'SPASSWORD' is not defined or is empty."
	fi
	exit 2
fi

echo -e "$green--- az login ---$reset_formatting"
# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
  configureNonDeployer "${tf_version}"
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

echo "Keyvault: $key_vault"

echo -e "$green--- BoM $BOM ---$reset_formatting"
echo "Downloading BoM defined in $BOM"

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


if [ "$PLATFORM" == "devops" ]; then
	echo "##vso[task.setvariable variable=SUSERNAME;isOutput=true]$SUSERNAME"
	echo "##vso[task.setvariable variable=SPASSWORD;isOutput=true]$SPASSWORD"
	echo "##vso[task.setvariable variable=BOM_NAME;isOutput=true]$BOM"
elif [ "$PLATFORM" == "github" ]; then
	start_group "Download SAP Bill of Materials"

	az account set --subscription "$ARM_SUBSCRIPTION_ID" --output none

	sample_path=${SAMPLE_REPO_PATH}/SAP
	command="ansible-playbook \
		-e download_directory=${GITHUB_WORKSPACE} \
		-e s_user=${SUSERNAME} \
		-e BOM_directory=${sample_path} \
		-e bom_base_name='${BOM}' \
		-e deployer_kv_name=${key_vault} \
		-e check_storage_account=${re_download} \
		-e orchestration_ansible_user=root \
		${EXTRA_PARAMETERS} \
		${SAP_AUTOMATION_REPO_PATH}/deploy/ansible/playbook_bom_downloader.yaml"
	echo "Executing [$command]"
	eval $command

	end_group
	exit $return_code
fi

echo -e "$green--- Done ---$reset_formatting"
exit 0

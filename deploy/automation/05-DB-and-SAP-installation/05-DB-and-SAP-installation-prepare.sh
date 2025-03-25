#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/shared_functions.sh
. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/set-colors.sh

green="\e[1;32m"
reset="\e[0m"
bold_red="\e[1;31m"

DEBUG=False

function check_required_inputs() {
    REQUIRED_VARS=(
        "SAP_AUTOMATION_REPO_PATH"
        "AZURE_SUBSCRIPTION_ID"
        "AZURE_CLIENT_ID"
        "AZURE_CLIENT_SECRET"
        "AZURE_TENANT_ID"
        "DEPLOYER_FOLDER"
        "SAP_SYSTEM_CONFIGURATION_NAME"
        "BOM_BASE_NAME"
    )

    case $(get_platform) in
    github)
        REQUIRED_VARS+=("APP_TOKEN")
        ;;

    devops)
        REQUIRED_VARS+=("CONFIG_REPO_PATH")
        ;;

    *) ;;
    esac

    success=0
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var+x}" ] || [ -z "${!var}" ]; then
            success=1
            log_warning "Missing required variable: ${var}"
        fi
    done

    return $success
}

if [[ $(get_platform) = github ]]; then
    export CONFIG_REPO_PATH=${GITHUB_WORKSPACE}/WORKSPACES
fi

if [ "$SYSTEM_DEBUG" = True ]; then
	set -x
	DEBUG=True
	echo "Environment variables:"
	printenv | sort

fi
export DEBUG
set -eu

if [[ $(get_platform) = devops ]]; then
	echo -e "$green--- Configure devops CLI extension ---$reset"
	az config set extension.use_dynamic_install=yes_without_prompt --output none --only-show-errors
	AZURE_DEVOPS_EXT_PAT=$SYSTEM_ACCESSTOKEN
	export AZURE_DEVOPS_EXT_PAT
fi

start_group "Check all required inputs are set"
check_required_inputs
if [ $? == 0 ]; then
	echo "All required variables are set"
else
	exit_error "Missing required variables" 1
fi
end_group

export USE_MSI=false
export VARIABLE_GROUP_ID=${DEPLOYER_FOLDER}
export ARM_CLIENT_ID=$AZURE_CLIENT_ID
export ARM_CLIENT_SECRET=$AZURE_CLIENT_SECRET
export ARM_TENANT_ID=$AZURE_TENANT_ID
export ARM_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID

start_group "Setup platform dependencies"
# Will return vars which we need to export afterwards
eval "$(setup_dependencies | sed 's/^/export /')"
end_group

ENVIRONMENT=$(echo "$SAP_SYSTEM_CONFIGURATION_NAME" | awk -F'-' '{print $1}' | xargs)
LOCATION=$(echo "${SAP_SYSTEM_CONFIGURATION_NAME}" | awk -F'-' '{print $2}' | xargs)
NETWORK=$(echo "${SAP_SYSTEM_CONFIGURATION_NAME}" | awk -F'-' '{print $3}' | xargs)
SID=$(echo "${SAP_SYSTEM_CONFIGURATION_NAME}" | awk -F'-' '{print $4}' | xargs)

cd "$CONFIG_REPO_PATH" || exit

environment_file_name=".sap_deployment_automation/${ENVIRONMENT}${LOCATION}${NETWORK}"
parameters_filename="$CONFIG_REPO_PATH/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}/sap-parameters.yaml"

if [[ $(get_platform) = devops ]]; then
	az devops configure --defaults organization=$SYSTEM_COLLECTIONURI project='$SYSTEM_TEAMPROJECT' --output none --only-show-errors
fi

echo -e "$green--- Validations ---$reset"
if [ ! -f "${environment_file_name}" ]; then
	echo -e "$bold_red--- ${environment_file_name} was not found ---$reset"
	exit_error "File ${environment_file_name} was not found." 2
fi

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
	echo "##vso[task.logissue type=error]Variable AZURE_SUBSCRIPTION_ID was not defined."
	exit 2
fi

if [[ $(get_platform) = devops ]] && [ "azure pipelines" == "$THIS_AGENT" ]; then
	echo "##vso[task.logissue type=error]Please use a self hosted agent for this playbook. Define it in the SDAF-$ENVIRONMENT variable group"
	exit 2
fi

start_group "Azure Login"
# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
    echo -e "$green--- az login ---$resetformatting"
    az login --service-principal --username $ARM_CLIENT_ID --password=$ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID --output none
    return_code=$?
    if [ 0 != $return_code ]; then
        echo -e "$boldred--- Login failed ---$resetformatting"
        exit_error "az login failed." $return_code
    fi
    az account set --subscription $ARM_SUBSCRIPTION_ID
else
    if [ $USE_MSI != "true" ]; then
        echo -e "$cyan--- Using SPN ---$resetformatting"
        export ARM_USE_MSI=false
        az login --service-principal --username $ARM_CLIENT_ID --password=$ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID --output none

        return_code=$?
        if [ 0 != $return_code ]; then
            echo -e "$boldred--- Login failed ---$resetformatting"
            exit_error "az login failed." $return_code
            exit $return_code
        fi
        az account set --subscription $ARM_SUBSCRIPTION_ID
    else
        echo -e "$cyan--- Using MSI ---$resetformatting"
        source /etc/profile.d/deploy_server.sh
        unset ARM_TENANT_ID
        export ARM_USE_MSI=true
    fi
fi
end_group

az account set --subscription "$AZURE_SUBSCRIPTION_ID" --output none

start_group "Get key vault name"
if [[ $(get_platform) = devops ]]; then
	VARIABLE_GROUP_ID=$(az pipelines variable-group list --query "[?name=='$VARIABLE_GROUP'].id | [0]")
	export VARIABLE_GROUP_ID
	printf -v val '%-15s' "$VARIABLE_GROUP_ID id:"
	echo "$val                      $VARIABLE_GROUP_ID"
	if [ -z "${VARIABLE_GROUP_ID}" ]; then
		exit_error "Variable group $VARIABLE_GROUP could not be found." 2
	fi
	key_vault=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "Deployer_Key_Vault" "${environment_file_name}" "keyvault")
else
    var=$(get_value_with_key "Deployer_Key_Vault") "${environment_file_name}")
    if [ -z ${var} ]; then
        key_vault=$(config_value_with_key "keyvault")
    else
        key_vault=${var}
    fi
fi
echo "Deployer Key Vault: ${key_vault}"
end_group

if [[ $(get_platform) = devops ]]; then
	echo "##vso[build.updatebuildnumber]Deploying ${SAP_SYSTEM_CONFIGURATION_NAME} using BoM ${BOM_BASE_NAME}"
	echo "##vso[task.setvariable variable=SID;isOutput=true]${SID}"
	echo "##vso[task.setvariable variable=SAP_PARAMETERS;isOutput=true]sap-parameters.yaml"
	echo "##vso[task.setvariable variable=FOLDER;isOutput=true]$CONFIG_REPO_PATH/SYSTEM/$SAP_SYSTEM_CONFIGURATION_NAME"
	echo "##vso[task.setvariable variable=HOSTS;isOutput=true]${SID}_hosts.yaml"
	echo "##vso[task.setvariable variable=KV_NAME;isOutput=true]$key_vault"
fi

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

start_group "Get Files from the Repository"
cd "$CONFIG_REPO_PATH/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}"
end_group

start_group "Add BOM Base Name and SAP FQDN to sap-parameters.yaml"
sed -i 's|bom_base_name:.*|bom_base_name:                 '"$BOM_BASE_NAME"'|' sap-parameters.yaml
end_group

start_group "Get connection details"
mkdir -p artifacts

dos2unix -q ${environment_file_name}

prefix="${ENVIRONMENT}${LOCATION}${NETWORK}"

if [[ $(get_platform) = devops ]]; then
	workload_key_vault=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "${prefix}Workload_Key_Vault" "${environment_file_name}" "workloadkeyvault" || true)
	workload_prefix=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "${prefix}Workload_Secret_Prefix" "${environment_file_name}" "workload_zone_prefix" || true)
	control_plane_subscription=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "Terraform_Remote_Storage_Subscription" "${environment_file_name}" "STATE_SUBSCRIPTION" || true)
else
    var=$(get_value_with_key "workloadkeyvault")
    if [ -z ${var} ]; then
        workload_key_vault=$(config_value_with_key "Workload_Key_Vault")
    else
        workload_key_vault=${var}
    fi
    var=$(get_value_with_key "workload_zone_prefix")
    if [ -z ${var} ]; then
        workload_prefix=$(config_value_with_key "${NETWORK}Workload_Secret_Prefix")
    else
        workload_prefix=${var}
    fi

    var=$(get_value_with_key "STATE_SUBSCRIPTION")
    if [ -z ${var} ]; then
        control_plane_subscription=$(config_value_with_key "Terraform_Remote_Storage_Subscription")
    else
        control_plane_subscription=${var}
    fi
fi

echo "SID:                                 ${SID}"
echo "Folder:                              $HOME/SYSTEM/${SAP_SYSTEM_CONFIGURATION_NAME}"
echo "Workload Key Vault:                  ${workload_key_vault}"
echo "Control Plane Subscription:          ${control_plane_subscription}"
echo "Workload Prefix:                     ${workload_prefix}"

if [ $EXTRA_PARAMETERS = '$(EXTRA_PARAMETERS)' ]; then
	new_parameters=$PIPELINE_EXTRA_PARAMETERS
else
	if [[ $(get_platform) = devops ]]; then
		echo "##vso[task.logissue type=warning]Extra parameters were provided - '$EXTRA_PARAMETERS'"
	fi
	new_parameters="$EXTRA_PARAMETERS $PIPELINE_EXTRA_PARAMETERS"
fi

if [[ $(get_platform) = devops ]]; then
	echo "##vso[task.setvariable variable=SSH_KEY_NAME;isOutput=true]${workload_prefix}-sid-sshkey"
	echo "##vso[task.setvariable variable=VAULT_NAME;isOutput=true]$workload_key_vault"
	echo "##vso[task.setvariable variable=PASSWORD_KEY_NAME;isOutput=true]${workload_prefix}-sid-password"
	echo "##vso[task.setvariable variable=USERNAME_KEY_NAME;isOutput=true]${workload_prefix}-sid-username"
	echo "##vso[task.setvariable variable=NEW_PARAMETERS;isOutput=true]${new_parameters}"
	echo "##vso[task.setvariable variable=CP_SUBSCRIPTION;isOutput=true]${control_plane_subscription}"
fi
end_group

az keyvault secret show --name "${workload_prefix}-sid-sshkey" --vault-name "$workload_key_vault" --subscription "$control_plane_subscription" --query value -o tsv >"artifacts/${SAP_SYSTEM_CONFIGURATION_NAME}_sshkey"
cp sap-parameters.yaml artifacts/.
cp "${SID}_hosts.yaml" artifacts/.

2> >(while read line; do (echo >&2 "STDERROR: $line"); done)

echo -e "$green--- Done ---$reset"
exit 0

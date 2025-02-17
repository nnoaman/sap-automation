#!/usr/bin/env bash

. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/shared_functions.sh
. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/set-colors.sh

function check_required_inputs() {
    REQUIRED_VARS=(
        "SAP_AUTOMATION_REPO_PATH"
        "TEST_ONLY"
        "WL_ARM_SUBSCRIPTION_ID"
        "WL_ARM_CLIENT_ID"
        "WL_ARM_CLIENT_SECRET"
        "WL_ARM_TENANT_ID"
        "DEPLOYER_FOLDER"
        "SAP_SYSTEM_FOLDERNAME"
        "SAP_SYSTEM_TFVARS_FILENAME"
    )

    case $(get_platform) in
    github)
        REQUIRED_VARS+=("APP_TOKEN")
        ;;

    devops)
        REQUIRED_VARS+=("CONFIG_REPO_PATH")
        # REQUIRED_VARS+=("this_agent")
        # REQUIRED_VARS+=("PAT")
        # REQUIRED_VARS+=("POOL")
        # REQUIRED_VARS+=("VARIABLE_GROUP_ID")
        ;;

    *) ;;
    esac

    success=0
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            success=1
            log_warning "Missing required variable: ${var}"
        fi
    done

    return $success
}

if [[ $(get_platform) = github ]]; then
    export CONFIG_REPO_PATH=${GITHUB_WORKSPACE}/WORKSPACES
fi

start_group "Check all required inputs are set"
check_required_inputs
if [ $? == 0 ]; then
    echo "All required variables are set"
else
    exit_error "Missing required variables" 1
fi
end_group

set -euo pipefail

export USE_MSI=false
export VARIABLE_GROUP_ID=${SAP_SYSTEM_FOLDERNAME}
export ARM_CLIENT_ID=$WL_ARM_CLIENT_ID
export ARM_CLIENT_SECRET=$WL_ARM_CLIENT_SECRET
export ARM_TENANT_ID=$WL_ARM_TENANT_ID
export ARM_SUBSCRIPTION_ID=$WL_ARM_SUBSCRIPTION_ID

if [ ! -f ${CONFIG_REPO_PATH}/SYSTEM/${SAP_SYSTEM_FOLDERNAME}/${SAP_SYSTEM_TFVARS_FILENAME} ]; then
    exit_error "${SAP_SYSTEM_TFVARS_FILENAME} was not found" 2
fi

tfvarsFile="${CONFIG_REPO_PATH}/SYSTEM/${SAP_SYSTEM_FOLDERNAME}/${SAP_SYSTEM_TFVARS_FILENAME}"

cd ${CONFIG_REPO_PATH}

storage_account_parameter=""

start_group "Configure parameters"
echo "Deploying the SAP System defined in ${SAP_SYSTEM_FOLDERNAME}"

dos2unix -q tfvarsFile

deployer_environment=$(echo ${DEPLOYER_FOLDER} | awk -F'-' '{print $1}' | xargs)
echo Deployer Environment: ${deployer_environment}
deployer_location=$(echo ${DEPLOYER_FOLDER} | awk -F'-' '{print $2}' | xargs)
echo Deployer Location: ${deployer_location}

ENVIRONMENT=$(grep -m1 "^environment" "$tfvarsFile" | awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"')
LOCATION=$(grep -m1 "^location" "$tfvarsFile" | awk -F'=' '{print $2}' | tr '[:upper:]' '[:lower:]' | tr -d ' \t\n\r\f"')
NETWORK=$(grep -m1 "^network_logical_name" "$tfvarsFile" | awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"')
SID=$(grep -m1 "^sid" "$tfvarsFile" | awk -F'=' '{print $2}' | tr -d ' \t\n\r\f"')

ENVIRONMENT_IN_FILENAME=$(echo $SAP_SYSTEM_FOLDERNAME | awk -F'-' '{print $1}')
LOCATION_CODE=$(echo ${SAP_SYSTEM_FOLDERNAME} | awk -F'-' '{print $2}' | xargs)
LOCATION_IN_FILENAME=$(region_with_region_map ${LOCATION_CODE})
NETWORK_IN_FILENAME=$(echo $SAP_SYSTEM_FOLDERNAME | awk -F'-' '{print $3}')
SID_IN_FILENAME=$(echo $SAP_SYSTEM_FOLDERNAME | awk -F'-' '{print $4}')

if [ -z "${SAP_SYSTEM_TFVARS_FILENAME}" ]; then
    exit_error "SAP_SYSTEM_TFVARS_FILENAME is not set" 2
fi

end_group

start_group "Validations"

echo "Environment(filename): $ENVIRONMENT"
echo "Location(filename):    $LOCATION_IN_FILENAME"
echo "Network(filename):     $NETWORK"
echo "SID(filename):         $SID"

deployer_environment_file_name=${CONFIG_REPO_PATH}/.sap_deployment_automation/${deployer_environment}${deployer_location}
echo "Deployer Environment File: ${deployer_environment_file_name}"

environment_file_name=${CONFIG_REPO_PATH}/.sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE}${NETWORK}
if [ ! -f $environment_file_name ]; then
    echo -e "$boldred--- $environment_file_name was not found ---${resetformatting}"
    echo "##vso[task.logissue type=error]Please rerun the workload zone deployment. Workload zone configuration file $environment_file_name was not found."
    exit 2
fi


echo -e "$green--- Convert config file to UX format ---$resetformatting"

dos2unix -q ${environment_file_name}

echo -e "$green--- Define variables ---${resetformatting}"

var=$(get_value_with_key "Deployer_State_FileName")
if [ -z ${var} ]; then
    deployer_tfstate_key=$(config_value_with_key "deployer_tfstate_key")
else
    deployer_tfstate_key=${var}
fi
echo "Deployer State File:" $deployer_tfstate_key

var=$(get_value_with_key "Workload_Zone_State_FileName")
if [ -z ${var} ]; then
    landscape_tfstate_key=$(config_value_with_key "landscape_tfstate_key")
else
    landscape_tfstate_key=${var}
fi
echo "Landscape State File:" $landscape_tfstate_key

var=$(get_value_with_key "Deployer_Key_Vault")
if [ -z ${var} ]; then
    key_vault=$(config_value_with_key "keyvault")
else
    key_vault=${var}
fi
echo "Deployer Key Vault: ${key_vault}"

var=$(get_value_with_key "Terraform_Remote_Storage_Account_Name")
if [ -z ${var} ]; then
    REMOTE_STATE_SA=$(config_value_with_key "REMOTE_STATE_SA")
else
    REMOTE_STATE_SA=${var}
fi
echo "Terraform state file storage account: ${REMOTE_STATE_SA}"

var=$(get_value_with_key "Terraform_Remote_Storage_Subscription")
if [ -z ${var} ]; then
    STATE_SUBSCRIPTION=$(config_value_with_key "STATE_SUBSCRIPTION")
else
    STATE_SUBSCRIPTION=${var}
fi
echo "Terraform state file subscription: ${STATE_SUBSCRIPTION}"

if [[ $(get_platform) = devops ]]; then

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "Terraform_Remote_Storage_Subscription.value" | tr -d \")
    if [ -z ${az_var} ]; then
        export STATE_SUBSCRIPTION=$(grep STATE_SUBSCRIPTION ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'Terraform state file subscription' $STATE_SUBSCRIPTION
    else
        export STATE_SUBSCRIPTION=${az_var} ; echo 'Terraform state file subscription' $STATE_SUBSCRIPTION
    fi

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "Terraform_Remote_Storage_Account_Name.value" | tr -d \")
    if [ -z ${az_var} ]; then
        export REMOTE_STATE_SA=$(grep REMOTE_STATE_SA ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'Terraform state file storage account' $REMOTE_STATE_SA
    else
        export REMOTE_STATE_SA=${az_var} ; echo 'Terraform state file storage account' $REMOTE_STATE_SA
    fi

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "Deployer_State_FileName.value" | tr -d \")
    if [ -z ${az_var} ]; then
        export deployer_tfstate_key=$(grep deployer_tfstate_key ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'Deployer State File' $deployer_tfstate_key
    else
        export deployer_tfstate_key=${az_var} ; echo 'Deployer State File' $deployer_tfstate_key
    fi

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "${NETWORK}"Workload_Zone_State_FileName.value | tr -d \")
    if [ -z ${az_var} ]; then
        export landscape_tfstate_key=$(grep keyvault= ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'landscape_tfstate_key' $landscape_tfstate_key
    else
        export landscape_tfstate_key=${az_var} ; echo 'landscape_tfstate_key' $landscape_tfstate_key
    fi

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "Deployer_Key_Vault.value" | tr -d \")
    if [ -z ${az_var} ]; then
        export key_vault=$(grep keyvault= ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'Deployer Key Vault' $key_vault
    else
        export key_vault=${az_var} ; echo 'Deployer Key Vault' $key_vault
    fi

    az_var=$(az pipelines variable-group variable list --group-id ${VARIABLE_GROUP_ID} --query "${NETWORK}"Workload_Key_Vault.value | tr -d \")
    if [ -z ${az_var} ]; then
        export workload_key_vault=$(grep keyvault= ${environment_file_name} | awk -F'=' '{print $2}' | xargs) ; echo 'Workload Key Vault' ${workload_key_vault}
    else
        export workload_key_vault=${az_var} ; echo 'Workload Key Vault' ${workload_key_vault}
    fi

fi

echo -e "$green--- Run the installer script that deploys the SAP System ---${resetformatting}"

cd ${CONFIG_REPO_PATH}/SYSTEM/${SAP_SYSTEM_FOLDERNAME}

$SAP_AUTOMATION_REPO_PATH/deploy/scripts/installer.sh --parameterfile ${SAP_SYSTEM_TFVARS_FILENAME} --type sap_system \
    --state_subscription ${STATE_SUBSCRIPTION} --storageaccountname ${REMOTE_STATE_SA}                                 \
    --deployer_tfstate_key ${deployer_tfstate_key} --landscape_tfstate_key ${landscape_tfstate_key}                    \
    --ado --auto-approve

return_code=$?
if [ 0 != $return_code ]; then
    echo "##vso[task.logissue type=error]Return code from installer $return_code."
    if [ -f ${environment_file_name}.err ]; then
    error_message=$(cat ${environment_file_name}.err)
    echo "##vso[task.logissue type=error]Error message: $error_message."
    fi
fi

# Pull changes if there are other deployment jobs

echo -e "$green--- Pull the latest content from DevOps ---${resetformatting}"
git pull
echo -e "$green--- Add & update files in the DevOps Repository ---${resetformatting}"

added=0

if [ -f ./terraform/terraform.tfstate ]; then
    git add -f .terraform/terraform.tfstate
    added=1
fi

if [ -f sap-parameters.yaml ]; then
    git add sap-parameters.yaml
    added=1
fi

if [ -f ${SID}_hosts.yaml ]; then
    git add -f ${SID}_hosts.yaml
    added=1
fi

if [ -f ${SID}.md ]; then
    git add    ${SID}.md
    added=1
fi

if [ -f ${SID}_inventory.md ]; then
    git add    ${SID}_inventory.md
    added=1
fi

if [ -f ${SID}_resource_names.json ]; then
    git add    ${SID}_resource_names.json
    added=1
fi

if [ -f ${SAP_SYSTEM_TFVARS_FILENAME} ]; then
    git add ${SAP_SYSTEM_TFVARS_FILENAME}
    added=1
fi


set +e
git diff --cached --quiet
git_diff_return_code=$?
set -e

if [ 1 == $git_diff_return_code ]; then
    commit_changes "Added updates from deployment"
fi

if [ -f ${workload_environment_file_name}.md ]; then
    upload_summary ${workload_environment_file_name}.md
fi

if [ 0 != $return_code ]; then
    log_warning "Return code from install_workloadzone $return_code."
    if [ -f ${workload_environment_file_name}.err ]; then
        error_message=$(cat ${workload_environment_file_name}.err)
        exit_error "Error message: $error_message." $return_code
    fi
fi

exit $return_code

# if [ 1 == $added ]; then
#     git config user.email "$(Build.RequestedForEmail)"
#     git config user.name "$(Build.RequestedFor)"
#     git commit -m "Added updates from devops system deployment $(Build.DefinitionName) [skip ci]"

#     git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $(Build.SourceBranchName)
# fi

# if [ -f ${SID}.md ]; then
#     echo "##vso[task.uploadsummary]${CONFIG_REPO_PATH}/SYSTEM/${SAP_SYSTEM_FOLDERNAME}/${SID}.md"
# fi

# file_name=${SID}_inventory.md
# if [ -f ${SID}_inventory.md ]; then
#   az devops configure --defaults organization=$(System.CollectionUri) project='$(System.TeamProject)' --output none

#   # ToDo: Fix this later
#   # WIKI_NAME_FOUND=$(az devops wiki list --query "[?name=='SDAF'].name | [0]")
#   # echo "${WIKI_NAME_FOUND}"
#   # if [ -n "${WIKI_NAME_FOUND}" ]; then
#   #   eTag=$(az devops wiki page show --path "${file_name}" --wiki SDAF --query eTag )
#   #   if [ -n "$eTag" ]; then
#   #     az devops wiki page update --path "${file_name}" --wiki SDAF --file-path ./"${file_name}" --only-show-errors --version $eTag --output none
#   #   else
#   #     az devops wiki page create --path "${file_name}" --wiki SDAF --file-path ./"${file_name}" --output none --only-show-errors
#   #   fi
#   # fi
# fi
# exit $return_code

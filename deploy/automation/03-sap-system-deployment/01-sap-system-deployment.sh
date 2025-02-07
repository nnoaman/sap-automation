#!/usr/bin/env bash

. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/shared_functions.sh
. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/set-colors.sh

function check_deploy_inputs() {

    REQUIRED_VARS=(
        "SAP_AUTOMATION_REPO_PATH"
        "TEST_ONLY"
        "WL_ARM_SUBSCRIPTION_ID"
        "WL_ARM_CLIENT_ID"
        "WL_ARM_CLIENT_SECRET"
        "WL_ARM_TENANT_ID"
        "sap_system_folder"
    )

    case $(get_platform) in
    github)
        REQUIRED_VARS+=("APP_TOKEN")
        ;;

    devops)
        REQUIRED_VARS+=("CONFIG_REPO_PATH")
        REQUIRED_VARS+=("this_agent")
        REQUIRED_VARS+=("PAT")
        REQUIRED_VARS+=("POOL")
        REQUIRED_VARS+=("VARIABLE_GROUP_ID")\
        ;;

    *) ;;
    esac

    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var}" ]]; then
            success=1
            log_warning "Missing required variable: ${var}"
        fi
    done
    return $success
}

start_group "Check all required inputs are set"
check_deploy_inputs
if [ $? == 0 ]; then
    echo "All required variables are set"
else
    exit_error "Missing required variables" 1
fi
end_group

set -euo pipefail

export USE_MSI=false
export VARIABLE_GROUP_ID=${sap_system_folder}
export ARM_CLIENT_ID=$WL_ARM_CLIENT_ID
export ARM_CLIENT_SECRET=$WL_ARM_CLIENT_SECRET
export ARM_TENANT_ID=$WL_ARM_TENANT_ID
export ARM_SUBSCRIPTION_ID=$WL_ARM_SUBSCRIPTION_ID

if [[ $(get_platform) = github ]]; then
    export CONFIG_REPO_PATH=${GITHUB_WORKSPACE}/WORKSPACES
fi

cd ${CONFIG_REPO_PATH}

storage_account_parameter=""

start_group "SAP System Deployment"
echo "Deploying the SAP System defined in ${sap_system_folder}"
ENVIRONMENT=$(echo ${sap_system_folder} | awk -F'-' '{print $1}' | xargs)
echo Environment: ${ENVIRONMENT}
LOCATION=$(echo ${sap_system_folder} | awk -F'-' '{print $2}' | xargs)
echo Location: ${LOCATION}
NETWORK=$(echo ${sap_system_folder} | awk -F'-' '{print $3}' | xargs)
echo Network: ${NETWORK}
SID=$(echo ${sap_system_folder} | awk -F'-' '{print $4}' | xargs)
echo SID: ${SID}

mkdir -p ${CONFIG_REPO_PATH}/.sap_deployment_automation
sap_system_configuration_file = "${CONFIG_REPO_PATH}/SYSTEM/${sap_system_folder}/${sap_system_configuration}"
if [ ! -f ${sap_system_configuration_file} ]; then
    exit_error "File ${sap_system_configuration_file} was not found" 2
fi
end_group

case "$LOCATION" in
    "AUCE") LOCATION_IN_FILENAME="australiacentral" ;;
    "AUC2") LOCATION_IN_FILENAME="australiacentral2" ;;
    "AUEA") LOCATION_IN_FILENAME="australiaeast" ;;
    "AUSE") LOCATION_IN_FILENAME="australiasoutheast" ;;
    "BRSO") LOCATION_IN_FILENAME="brazilsouth" ;;
    "BRSE") LOCATION_IN_FILENAME="brazilsoutheast" ;;
    "BRUS") LOCATION_IN_FILENAME="brazilus" ;;
    "CACE") LOCATION_IN_FILENAME="canadacentral" ;;
    "CAEA") LOCATION_IN_FILENAME="canadaeast" ;;
    "CEIN") LOCATION_IN_FILENAME="centralindia" ;;
    "CEUS") LOCATION_IN_FILENAME="centralus" ;;
    "CEUA") LOCATION_IN_FILENAME="centraluseuap" ;;
    "EAAS") LOCATION_IN_FILENAME="eastasia" ;;
    "EAUS") LOCATION_IN_FILENAME="eastus" ;;
    "EUSA") LOCATION_IN_FILENAME="eastus2euap" ;;
    "EUS2") LOCATION_IN_FILENAME="eastus2" ;;
    "EUSG") LOCATION_IN_FILENAME="eastusstg" ;;
    "FRCE") LOCATION_IN_FILENAME="francecentral" ;;
    "FRSO") LOCATION_IN_FILENAME="francesouth" ;;
    "GENO") LOCATION_IN_FILENAME="germanynorth" ;;
    "GEWE") LOCATION_IN_FILENAME="germanywest" ;;
    "GEWC") LOCATION_IN_FILENAME="germanywestcentral" ;;
    "ISCE") LOCATION_IN_FILENAME="israelcentral" ;;
    "ITNO") LOCATION_IN_FILENAME="italynorth" ;;
    "JAEA") LOCATION_IN_FILENAME="japaneast" ;;
    "JAWE") LOCATION_IN_FILENAME="japanwest" ;;
    "JINC") LOCATION_IN_FILENAME="jioindiacentral" ;;
    "JINW") LOCATION_IN_FILENAME="jioindiawest" ;;
    "KOCE") LOCATION_IN_FILENAME="koreacentral" ;;
    "KOSO") LOCATION_IN_FILENAME="koreasouth" ;;
    "NCUS") LOCATION_IN_FILENAME="northcentralus" ;;
    "NOEU") LOCATION_IN_FILENAME="northeurope" ;;
    "NOEA") LOCATION_IN_FILENAME="norwayeast" ;;
    "NOWE") LOCATION_IN_FILENAME="norwaywest" ;;
    "PLCE") LOCATION_IN_FILENAME="polandcentral" ;;
    "QACE") LOCATION_IN_FILENAME="qatarcentral" ;;
    "SANO") LOCATION_IN_FILENAME="southafricanorth" ;;
    "SAWE") LOCATION_IN_FILENAME="southafricawest" ;;
    "SCUS") LOCATION_IN_FILENAME="southcentralus" ;;
    "SCUG") LOCATION_IN_FILENAME="southcentralusstg" ;;
    "SOEA") LOCATION_IN_FILENAME="southeastasia" ;;
    "SOIN") LOCATION_IN_FILENAME="southindia" ;;
    "SECE") LOCATION_IN_FILENAME="swedencentral" ;;
    "SWNO") LOCATION_IN_FILENAME="switzerlandnorth" ;;
    "SWWE") LOCATION_IN_FILENAME="switzerlandwest" ;;
    "UACE") LOCATION_IN_FILENAME="uaecentral" ;;
    "UANO") LOCATION_IN_FILENAME="uaenorth" ;;
    "UKSO") LOCATION_IN_FILENAME="uksouth" ;;
    "UKWE") LOCATION_IN_FILENAME="ukwest" ;;
    "WCUS") LOCATION_IN_FILENAME="westcentralus" ;;
    "WEEU") LOCATION_IN_FILENAME="westeurope" ;;
    "WEIN") LOCATION_IN_FILENAME="westindia" ;;
    "WEUS") LOCATION_IN_FILENAME="westus" ;;
    "WUS2") LOCATION_IN_FILENAME="westus2" ;;
    "WUS3") LOCATION_IN_FILENAME="westus3" ;;
    *) LOCATION_IN_FILENAME="westeurope" ;;
esac

echo "Environment(filename): $ENVIRONMENT"
echo "Location(filename):    $LOCATION_IN_FILENAME"
echo "Network(filename):     $NETWORK"
echo "SID(filename):         $SID"

environment_file_name=$HOME_CONFIG/.sap_deployment_automation/${ENVIRONMENT}${LOCATION_CODE}${NETWORK}
if [ ! -f $environment_file_name ]; then
    echo -e "$boldred--- $environment_file_name was not found ---$reset"
    echo "##vso[task.logissue type=error]Please rerun the workload zone deployment. Workload zone configuration file $environment_file_name was not found."
    exit 2
fi

echo -e "$green--- Define variables ---$reset"
cd $HOME_CONFIG/SYSTEM/${sap_system_folder}

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

echo -e "$green--- Run the installer script that deploys the SAP System ---$reset"

$SAP_AUTOMATION_REPO_PATH/deploy/scripts/installer.sh --parameterfile $(sap_system_configuration) --type sap_system \
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

cd $HOME_CONFIG/SYSTEM/${sap_system_folder}

echo -e "$green--- Pull the latest content from DevOps ---$reset"
git pull
echo -e "$green--- Add & update files in the DevOps Repository ---$reset"

added=0

if [ -f $.terraform/terraform.tfstate ]; then
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

if [ -f $(sap_system_configuration) ]; then
    git add    $(sap_system_configuration)
    added=1
fi

if [ 1 == $added ]; then
    git config --global user.email "$(Build.RequestedForEmail)"
    git config --global user.name "$(Build.RequestedFor)"
    git commit -m "Added updates from devops system deployment $(Build.DefinitionName) [skip ci]"

    git -c http.extraheader="AUTHORIZATION: bearer $(System.AccessToken)" push --set-upstream origin $(Build.SourceBranchName)
fi

if [ -f ${SID}.md ]; then
    echo "##vso[task.uploadsummary]$HOME_CONFIG/SYSTEM/$(sap_system_folder)/${SID}.md"
fi

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

exit $return_code

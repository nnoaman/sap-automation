#!/usr/bin/env bash

. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/shared_functions.sh
. ${SAP_AUTOMATION_REPO_PATH}/deploy/automation/set-colors.sh
echo "SAP_AUTOMATION_REPO_PATH: ${SAP_AUTOMATION_REPO_PATH}"
function check_deploy_inputs() {
    REQUIRED_VARS=(
        "SAP_AUTOMATION_REPO_PATH"
        "ARM_SUBSCRIPTION_ID"
        "ARM_CLIENT_ID"
        "ARM_CLIENT_SECRET"
        "ARM_TENANT_ID"
        "deployerfolder"
        "SUsername"
        "SPassword"
    )

    case $(get_platform) in
    github) ;;

    devops)
        REQUIRED_VARS+=("variable_group")
        REQUIRED_VARS+=("parent_variable_group")
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

start_group "Check all required inputs are set"
check_deploy_inputs
if [ $? == 0 ]; then
    echo "All required variables are set"
else
    exit_error "Missing required variables" 1
fi
end_group

if [[ $(get_platform) = github ]]; then
    export CONFIG_REPO_PATH=${GITHUB_WORKSPACE}/WORKSPACES
fi

# TODO:
export USE_MSI=false
export VARIABLE_GROUP_ID=${deployerfolder}

start_group "Setup platform dependencies"
# Will return vars which we need to export afterwards
eval "$(setup_dependencies | sed 's/^/export /')"
end_group

echo "Preparing for SAP Software Download"

deployer_environment=$(echo ${deployerfolder} | awk -F'-' '{print $1}' | xargs)
echo Deployer Environment: ${deployer_environment}
deployer_location=$(echo ${deployerfolder} | awk -F'-' '{print $2}' | xargs)

start_group "Details of Key Vault"
echo Deployer Location: ${deployer_location}
kv_name=$(cat .sap_deployment_automation/ ${deployer_environment}${deployer_location} | grep keyvault |awk -F'=' '{print $2}'); echo "Key Vault="$kv_name

export SUsernamefromVault=$(az keyvault secret list --vault-name "${kv_name}" --subscription "${ARM_SUBSCRIPTION_ID}" --query "[].{Name:name} | [? contains(Name,'S-Username')] | [0]"  -o tsv)

if [ $SUsernamefromVault == $SUsername ]; then
    echo "$SUsername present in keyvault. In case of download errors check that user and password are correct"
else
    echo "Setting the S username in key vault"
    az keyvault secret set --name "S-Username" --vault-name $kv_name --value="${SUsername}" --subscription "${ARM_SUBSCRIPTION_ID}" --output none
    echo "$SUsername"
fi

export SPasswordfromVault=$(az keyvault secret list --vault-name "${kv_name}" --subscription "${ARM_SUBSCRIPTION_ID}" --query "[].{Name:name} | [? contains(Name,'S-Password')] | [0]"  -o tsv)
if [ ${SPassword} == $SPasswordfromVault ]; then
    echo "${SPasswordfromVault}"
    echo "Password present in keyvault. In case of download errors check that user and password are correct"
else
    echo "Setting the S user name password in key vault"
    az keyvault secret set --name "S-Password" --vault-name $kv_name --value "${SPassword}" --subscription "${ARM_SUBSCRIPTION_ID}" --output none
    echo "${SPassword}"
fi

exit $return_code

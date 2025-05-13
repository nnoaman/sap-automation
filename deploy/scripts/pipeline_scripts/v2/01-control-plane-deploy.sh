#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Source the shared platform configuration
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/shared_platform_config.sh"
source "${SCRIPT_DIR}/shared_functions.sh"

SCRIPT_NAME="$(basename "$0")"
# Define colors for output
green="\e[1;32m"
reset="\e[0m"
bold_red="\e[1;31m"
cyan="\e[1;36m"

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

DEBUG=false
if [[ "$SYSTEM_DEBUG" == "True" || "$RUNNER_DEBUG" == "1" ]]; then
	set -x
	DEBUG=true
	echo "Environment variables:"
	printenv | sort
fi

export DEBUG
set -eu

# Print the execution environment details
print_header
echo ""

# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then
	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	# Values will be stored in GitHub Environment variables
	echo "Configuring for GitHub Actions"
	export VARIABLE_GROUP_ID="${CONTROL_PLANE_NAME}"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
fi

banner_title="Deploy Control Plane"
print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"

DEPLOYER_FOLDERNAME="${CONTROL_PLANE_NAME}-INFRASTRUCTURE"
DEPLOYER_TFVARS_FILENAME="${CONTROL_PLANE_NAME}-INFRASTRUCTURE.tfvars"
deployer_configuration_file="${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME"

prefix=$(echo "$CONTROL_PLANE_NAME" | cut -d '-' -f1-2)

LIBRARY_FOLDERNAME="$prefix-SAP_LIBRARY"
LIBRARY_TFVARS_FILENAME="$prefix-SAP_LIBRARY.tfvars"
library_configuration_file="${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME"

deployer_environment_file_name="${CONFIG_REPO_PATH}/.sap_deployment_automation/${CONTROL_PLANE_NAME}"
if [ -f "${deployer_environment_file_name}" ]; then
	step=$(grep -m1 "^step=" "${deployer_environment_file_name}" | awk -F'=' '{print $2}' | xargs)
	echo "Step:                                $step"
fi

terraform_storage_account_name=""
terraform_storage_account_resource_group_name=$DEPLOYER_FOLDERNAME

# Print the execution environment details
print_header

# Platform-specific configuration
if [ "$PLATFORM" == "devops" ]; then
	# Configure DevOps
	configure_devops

	if ! get_variable_group_id "$VARIABLE_GROUP" "VARIABLE_GROUP_ID"; then
		echo -e "$bold_red--- Variable group $VARIABLE_GROUP not found ---$reset"
		echo "##vso[task.logissue type=error]Variable group $VARIABLE_GROUP not found."
		exit 2
	fi
	export VARIABLE_GROUP_ID
elif [ "$PLATFORM" == "github" ]; then
	# No specific variable group setup for GitHub Actions
	echo "Configuring for GitHub Actions - using environment variables"
fi

TF_VAR_tf_version="${tf_version:-1.11.3}"
export TF_VAR_tf_version
TF_VAR_PLATFORM="github"
export TF_VAR_PLATFORM

# Check if running on deployer
if [[ ! -f /etc/profile.d/deploy_server.sh ]]; then
	configureNonDeployer "${tf_version:-1.11.3}"

	echo -e "$green--- az login ---$reset"
	if [ "$PLATFORM" == "devops" ]; then
		if ! LogonToAzure false; then
			print_banner "$banner_title" "Login to Azure failed" "error"
			if [ "$PLATFORM" == "devops" ]; then
				echo "##vso[task.logissue type=error]az login failed."
			fi
			exit 2
		fi
	fi
else
	if [ "${USE_MSI:-false}" == "true" ]; then
		TF_VAR_use_spn=false
		export TF_VAR_use_spn
		ARM_USE_MSI=true
		export ARM_USE_MSI
		echo "Deployment using:                    Managed Identity"
		ARM_CLIENT_ID=$(grep -m 1 "export ARM_CLIENT_ID=" /etc/profile.d/deploy_server.sh | awk -F'=' '{print $2}' | xargs)
		export ARM_CLIENT_ID
	else
		TF_VAR_use_spn=true
		export TF_VAR_use_spn
		ARM_USE_MSI=false
		export ARM_USE_MSI
		echo "Deployment using:                    Service Principal"

		# Get SPN ID differently per platform
		if [ "$PLATFORM" == "devops" ]; then
			TF_VAR_spn_id=$(getVariableFromVariableGroup "${VARIABLE_GROUP_ID}" "ARM_OBJECT_ID" "${deployer_environment_file_name}" "ARM_OBJECT_ID")
		elif [ "$PLATFORM" == "github" ]; then
			# Use value from env or from GitHub environment
			TF_VAR_spn_id=${OBJECT_ID:-$TF_VAR_spn_id}
		fi

		if [ -n "$TF_VAR_spn_id" ]; then
			if is_valid_guid "$TF_VAR_spn_id"; then
				export TF_VAR_spn_id
				echo "Service Principal Object id:         $TF_VAR_spn_id"
			fi
		fi
	fi

fi

cd "$CONFIG_REPO_PATH" || exit

TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID
export TF_VAR_subscription_id
if [ -z "${TF_VAR_ansible_core_version:-}" ]; then
	export TF_VAR_ansible_core_version=2.16
fi

az account set --subscription "$ARM_SUBSCRIPTION_ID"
echo "Deployer subscription:               $ARM_SUBSCRIPTION_ID"

APPLICATION_CONFIGURATION_ID=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$APPLICATION_CONFIGURATION_NAME' | project id, name, subscription" --query data[0].id --output tsv)

key_vault_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_KeyVaultResourceId" "${CONTROL_PLANE_NAME}")
if [ -z "$key_vault_id" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Key '${CONTROL_PLANE_NAME}_KeyVaultResourceId' was not found in the application configuration ( '$application_configuration_name' )."
	else
		echo "ERROR: Key '${CONTROL_PLANE_NAME}_KeyVaultResourceId' was not found in the application configuration."
	fi
fi
tfstate_resource_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_TerraformRemoteStateStorageAccountId" "${CONTROL_PLANE_NAME}")

TF_VAR_deployer_kv_user_arm_id=${key_vault_id}
export TF_VAR_deployer_kv_user_arm_id

echo ""
echo -e "${green}Terraform parameter information:"
echo -e "-------------------------------------------------------------------------------$reset"

echo "Control Plane Name:                  $CONTROL_PLANE_NAME"
echo ""
echo "Deployer Folder:                     $DEPLOYER_FOLDERNAME"
echo "Deployer tfVars:                     $DEPLOYER_TFVARS_FILENAME"
echo "Library Folder:                      $LIBRARY_FOLDERNAME"
echo "Library tfVars:                      $LIBRARY_TFVARS_FILENAME"

if [ -n "${DEPLOYER_KEYVAULT}" ]; then
	echo "Deployer Key Vault:                  ${DEPLOYER_KEYVAULT}"
	keyvault_parameter=" --keyvault ${DEPLOYER_KEYVAULT} "
else
	echo "Deployer Key Vault:                  undefined"
	exit 2
fi

terraform_storage_account_subscription_id=$ARM_SUBSCRIPTION_ID

echo "Terraform state subscription:        $terraform_storage_account_subscription_id"

if [ -n "$tfstate_resource_id" ]; then
	terraform_storage_account_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 9)
	terraform_storage_account_resource_group_name=$(echo "$tfstate_resource_id" | cut -d '/' -f 5)
	terraform_storage_account_subscription_id=$(echo "$tfstate_resource_id" | cut -d '/' -f 3)
	echo "Terraform storage account:           $terraform_storage_account_name"
	storage_account_parameter=" --terraform_storage_account_name ${terraform_storage_account_name} "

	export terraform_storage_account_name
	export terraform_storage_account_resource_group_name
	export terraform_storage_account_subscription_id
	export tfstate_resource_id

else
	echo "Terraform storage account:            undefined"
	storage_account_parameter=
fi

if [ "$PLATFORM" == "devops" ]; then
	pass=${SYSTEM_COLLECTIONID//-/}
elif [ "$PLATFORM" == "github" ]; then
	pass=${GITHUB_REPOSITORY//-/}
else
	pass="localpassword"
fi


cd "${CONFIG_REPO_PATH}" || exit
mkdir -p .sap_deployment_automation

start_group "Decrypting state files"
# Import PGP key if it exists, otherwise generate it
if [ -f ${CONFIG_REPO_PATH}/private.pgp ]; then
		echo "Importing PGP key"
    set +e
    gpg --list-keys sap-azure-deployer@example.com
    return_code=$?
    set -e

    if [ ${return_code} != 0 ]; then
        echo ${pass} | gpg --batch --passphrase-fd 0 --import ${CONFIG_REPO_PATH}/private.pgp
    fi
else
    exit_error "Private PGP key not found." 3
fi

git pull -q

if [ -f "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/state.gpg" ]; then
	echo "Decrypting state file"
	echo "${pass}" |
		gpg --batch \
			--passphrase-fd 0 \
			--output "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/terraform.tfstate" \
			--decrypt "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/state.gpg"
fi

if [ -f "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" ]; then
	echo "Unzipping the deployer state file"
	unzip -o -qq -P "${pass}" "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" -d "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME"
fi

# Handle state.zip differently per platform
if [ -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.zip" ]; then
	echo "Unzipping the library state file"
	unzip -o -qq -P "${pass}" "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.zip" -d "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME"
fi
if [ -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.gpg" ]; then
	echo "Decrypting state file"
	echo "${pass}" |
		gpg --batch \
			--passphrase-fd 0 \
			--output "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate" \
			--decrypt "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.gpg"
fi

end_group

export TF_LOG_PATH="${CONFIG_REPO_PATH}/.sap_deployment_automation/terraform.log"

print_banner "$banner_title" "Calling deploy_control_plane_v2" "info"

msi_flag=""
if [ "${USE_MSI:-false}" == "true" ]; then
	msi_flag=" --msi "
	TF_VAR_use_spn=false
	export TF_VAR_use_spn
	echo "Deployer using:                      Managed Identity"
else
	TF_VAR_use_spn=true
	export TF_VAR_use_spn
	echo "Deployer using:                      Service Principal"
fi

if [ "$DEBUG" == True ]; then
	echo "ARM Environment variables:"
	printenv | grep ARM_
fi
echo -e "$green--- Control Plane deployment---$reset"

# Platform-specific flags
if [ "$PLATFORM" == "devops" ]; then
	platform_flag="--ado"
elif [ "$PLATFORM" == "github" ]; then
	platform_flag="--github"
else
	platform_flag=""
fi

cd "$CONFIG_REPO_PATH" || exit

if
	"${SAP_AUTOMATION_REPO_PATH}/deploy/scripts/deploy_control_plane_v2.sh" \
		--control_plane_name "$CONTROL_PLANE_NAME" \
	  --auto-approve ${msi_flag}
then
	return_code=$?
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=warning]Return code from deploy_control_plane_v2 $return_code."
	fi
	echo "Return code from deploy_control_plane_v2 $return_code."
else
	return_code=$?
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.logissue type=error]Return code from deploy_control_plane_v2 $return_code."
	fi
	echo "Return code from deploy_control_plane_v2 $return_code."
fi

echo -e "$green--- Pushing the changes to the repository ---$reset"
added=0
cd "${CONFIG_REPO_PATH}" || exit

# Pull latest changes from appropriate branch
if [ "$PLATFORM" == "devops" ]; then
    git pull -q origin "$BUILD_SOURCEBRANCHNAME"
elif [ "$PLATFORM" == "github" ]; then
    git pull -q origin "$GITHUB_REF_NAME"
fi

echo -e "$green--- Update repo ---$reset"
if [ -f ".sap_deployment_automation/$CONTROL_PLANE_NAME" ]; then
    git add ".sap_deployment_automation/$CONTROL_PLANE_NAME"
    added=1
fi

if [ -f ".sap_deployment_automation/${CONTROL_PLANE_NAME}.md" ]; then
    git add ".sap_deployment_automation/${CONTROL_PLANE_NAME}.md"
    added=1
fi

if [ -f "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME" ]; then
    git add -f "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME"
    added=1
fi

if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate" ]; then
    git add -f "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate"
    added=1

    # || true suppresses the exitcode of grep. To not trigger the strict exit on error
    local_backend=$(grep "\"type\": \"local\"" "DEPLOYER/$DEPLOYER_FOLDERNAME/.terraform/terraform.tfstate" || true)

    if [ -n "$local_backend" ]; then
        echo "Deployer Terraform state:              local"

        if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate" ]; then
            echo "Compressing the deployer state file"
            if [ "$PLATFORM" == "devops" ]; then
                sudo apt-get install zip -y
                pass=${SYSTEM_COLLECTIONID//-/}
                zip -q -j -P "${pass}" "DEPLOYER/$DEPLOYER_FOLDERNAME/state" "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate"
                git add -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip"
            elif [ "$PLATFORM" == "github" ]; then
                rm DEPLOYER/$DEPLOYER_FOLDERNAME/state.gpg >/dev/null 2>&1 || true

                echo "Encrypting state file"
                gpg --batch \
                    --output DEPLOYER/$DEPLOYER_FOLDERNAME/state.gpg \
                    --encrypt \
                    --disable-dirmngr --recipient sap-azure-deployer@example.com \
                    --trust-model always \
                    DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate
                git add -f DEPLOYER/$DEPLOYER_FOLDERNAME/state.gpg
            else
                pass="localpassword"
            fi

            added=1
        fi
    else
        echo "Deployer Terraform state:              remote"
        if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate" ]; then
            git rm -q --ignore-unmatch -f "DEPLOYER/$DEPLOYER_FOLDERNAME/terraform.tfstate"
            echo "Removed the deployer state file"
            added=1
        fi
        if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" ]; then
            if [ 0 == $return_code ]; then
                echo "Removing the deployer state zip file"
                git rm -q --ignore-unmatch -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip"
                added=1
            fi
        fi
        if [ -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.gpg" ]; then
            if [ 0 == $return_code ]; then
                echo "Removing the deployer state gpg file"
                git rm -q --ignore-unmatch -f "DEPLOYER/$DEPLOYER_FOLDERNAME/state.gpg"
                added=1
            fi
        fi
    fi
fi

if [ -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME" ]; then
    git add -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME"
    added=1
fi

if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate" ]; then
    git add -f "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate"
    added=1
    # || true suppresses the exitcode of grep. To not trigger the strict exit on error
    local_backend=$(grep "\"type\": \"local\"" "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate" || true)
    if [ -n "$local_backend" ]; then
        echo "Library Terraform state:               local"
        if [ "$PLATFORM" == "devops" ]; then
            sudo apt-get install zip -y
            pass=${SYSTEM_COLLECTIONID//-/}
            zip -q -j -P "${pass}" "LIBRARY/$LIBRARY_FOLDERNAME/state" "LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate"
            git add -f "LIBRARY/$LIBRARY_FOLDERNAME/state.zip"
        elif [ "$PLATFORM" == "github" ]; then
            rm LIBRARY/$LIBRARY_FOLDERNAME/state.gpg >/dev/null 2>&1 || true
            echo "Encrypting state file"
            gpg --batch \
                --output LIBRARY/$LIBRARY_FOLDERNAME/state.gpg \
                --encrypt \
                --disable-dirmngr --recipient sap-azure-deployer@example.com \
                --trust-model always \
                LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate
            git add -f LIBRARY/$LIBRARY_FOLDERNAME/state.gpg
        else
            pass="localpassword"
        fi
        added=1
    else
        echo "Library Terraform state:               remote"
        if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate" ]; then
            if [ 0 == $return_code ]; then
                echo "Removing the library state file"
                git rm -q -f --ignore-unmatch "LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate"
                added=1
            fi
        fi
        if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/state.zip" ]; then
            echo "Removing the library state zip file"
            git rm -q --ignore-unmatch -f "LIBRARY/$LIBRARY_FOLDERNAME/state.zip"
            added=1
        fi
        if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/state.gpg" ]; then
            echo "Removing the library state gpg file"
            git rm -q --ignore-unmatch -f "LIBRARY/$LIBRARY_FOLDERNAME/state.gpg"
            added=1
        fi
    fi
fi

# Commit changes based on platform
if [ 1 = $added ]; then
    if [ "$PLATFORM" == "devops" ]; then
        git config --global user.email "$BUILD_REQUESTEDFOREMAIL"
        git config --global user.name "$BUILD_REQUESTEDFOR"
        commit_message="Added updates from Control Plane Deployment for $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME $BUILD_BUILDNUMBER [skip ci]"
    elif [ "$PLATFORM" == "github" ]; then
        git config --global user.email "github-actions@github.com"
        git config --global user.name "GitHub Actions"
        commit_message="Added updates from Control Plane Deployment for $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME [skip ci]"
    else
        git config --global user.email "local@example.com"
        git config --global user.name "Local User"
        commit_message="Added updates from Control Plane Deployment for $DEPLOYER_FOLDERNAME $LIBRARY_FOLDERNAME [skip ci]"
    fi

    if [ $DEBUG = True ]; then
        git status --verbose
        if git commit -m "$commit_message" || true; then
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
        if git commit -m "$commit_message" || true; then
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

# Add variables to storage based on platform
echo -e "$green--- Adding variables to storage ---$reset"
if [ 0 = $return_code ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo -e "$green--- Adding variables to the variable group: $VARIABLE_GROUP ---$reset"
		if saveVariableInVariableGroup "${VARIABLE_GROUP_ID}" "CONTROL_PLANE_NAME" "$CONTROL_PLANE_NAME"; then
			echo "Variable CONTROL_PLANE_NAME was added to the $VARIABLE_GROUP variable group."
		else
			echo "##vso[task.logissue type=error]Variable CONTROL_PLANE_NAME was not added to the $VARIABLE_GROUP variable group."
			echo "Variable CONTROL_PLANE_NAME was not added to the $VARIABLE_GROUP variable group."
		fi
	elif [ "$PLATFORM" == "github" ]; then
		# Set output variables for GitHub Actions
		echo "Setting output variable for GitHub Actions"
		set_output_variable "control_plane_name" "$CONTROL_PLANE_NAME"
		set_output_variable "deployer_keyvault" "$DEPLOYER_KEYVAULT"
	fi
fi

# Platform-specific summary handling
if [ -f "$CONFIG_REPO_PATH/.sap_deployment_automation/${CONTROL_PLANE_NAME}.md" ]; then
	if [ "$PLATFORM" == "devops" ]; then
		echo "##vso[task.uploadsummary]$CONFIG_REPO_PATH/.sap_deployment_automation/${CONTROL_PLANE_NAME}.md"
	elif [ "$PLATFORM" == "github" ]; then
		cat "$CONFIG_REPO_PATH/.sap_deployment_automation/${CONTROL_PLANE_NAME}.md" >>$GITHUB_STEP_SUMMARY
	fi
fi

print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

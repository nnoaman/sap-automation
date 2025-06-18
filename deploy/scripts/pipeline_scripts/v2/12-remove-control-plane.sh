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

banner_title="Remove Control Plane"

print_banner "$banner_title" "Entering $SCRIPT_NAME" "info"

# Print the execution environment details
print_header
echo ""

if [ -z "$CONTROL_PLANE_NAME" ]; then
	if [ -v DEPLOYER_FOLDERNAME ]; then

		CONTROL_PLANE_NAME=$(echo "$DEPLOYER_FOLDERNAME" | cut -d'-' -f1-3)
		export "CONTROL_PLANE_NAME"
	fi
fi

if [ -v APPLICATION_CONFIGURATION_NAME ]; then
	APPLICATION_CONFIGURATION_ID=$(az graph query -q "Resources | join kind=leftouter (ResourceContainers | where type=='microsoft.resources/subscriptions' | project subscription=name, subscriptionId) on subscriptionId | where name == '$APPLICATION_CONFIGURATION_NAME' | project id, name, subscription" --query data[0].id --output tsv)
	export APPLICATION_CONFIGURATION_ID
fi

if [ -z "$CONTROL_PLANE_NAME" ]; then
	echo "##vso[task.logissue type=error]CONFIG_REPO_PATH is not set."
	exit 2
fi

VARIABLE_GROUP="SDAF-${CONTROL_PLANE_NAME}"

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
	export VARIABLE_GROUP_ID="${CONTROL_PLANE_NAME}"
	git config --global --add safe.directory "$CONFIG_REPO_PATH"
	platform_flag="--github"
else
	platform_flag=""
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

prefix=$(echo "$CONTROL_PLANE_NAME" | cut -d '-' -f1-2)

DEPLOYER_FOLDERNAME="$CONTROL_PLANE_NAME-INFRASTRUCTURE"
DEPLOYER_TFVARS_FILENAME="$CONTROL_PLANE_NAME-INFRASTRUCTURE.tfvars"
LIBRARY_FOLDERNAME="$prefix-SAP_LIBRARY"
LIBRARY_TFVARS_FILENAME="$prefix-SAP_LIBRARY.tfvars"

deployerTFvarsFile="${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/$DEPLOYER_TFVARS_FILENAME"
libraryTFvarsFile="${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME"
deployer_tfstate_key="$DEPLOYER_FOLDERNAME.terraform.tfstate"
deployer_environment_file_name="${CONFIG_REPO_PATH}/.sap_deployment_automation/$CONTROL_PLANE_NAME"

TF_VAR_deployer_tfstate_key="$deployer_tfstate_key"
export TF_VAR_deployer_tfstate_key

if [ ! -f "$deployerTFvarsFile" ]; then
	print_banner "$banner_title" "$deployerTFvarsFile was not found" "error"
	echo "##vso[task.logissue type=error]File $deployerTFvarsFile was not found."
	exit 2
fi

if [ ! -f "${libraryTFvarsFile}" ]; then
	print_banner "$banner_title" "$libraryTFvarsFile was not found" "error"
	echo "##vso[task.logissue type=error]File LIBRARY/$LIBRARY_FOLDERNAME/$LIBRARY_TFVARS_FILENAME was not found."
	exit 2
fi

if [ -z "$ARM_SUBSCRIPTION_ID" ]; then
	echo "##vso[task.logissue type=error]Variable ARM_SUBSCRIPTION_ID was not defined."
	exit 2
fi

az account set --subscription "$ARM_SUBSCRIPTION_ID"

start_group "Decrypting state files"
# Handle state.zip differently per platform

cd "${CONFIG_REPO_PATH}" || exit

if [ "$PLATFORM" == "devops" ]; then
	pass=${SYSTEM_COLLECTIONID//-/}
	if [ -f "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" ]; then
		echo "Unzipping the deployer state file"
		unzip -o -qq -P "${pass}" "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME/state.zip" -d "${CONFIG_REPO_PATH}/DEPLOYER/$DEPLOYER_FOLDERNAME"
	fi

	if [ -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.zip" ]; then
		echo "Unzipping the library state file"
		unzip -o -qq -P "${pass}" "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.zip" -d "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME"
	fi

elif [ "$PLATFORM" == "github" ]; then
	pass=${GITHUB_REPOSITORY//-/}
	# Import PGP key if it exists, otherwise generate it
	if [ -f "${CONFIG_REPO_PATH}/private.pgp" ]; then
		echo "Importing PGP key"
		set +e
		gpg --list-keys sap-azure-deployer@example.com
		return_code=$?
		set -e

		if [ ${return_code} != 0 ]; then
			echo "${pass}" | gpg --batch --passphrase-fd 0 --import "${CONFIG_REPO_PATH}/private.pgp"
		fi
		if [ -f "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/state.gpg" ]; then
			echo "Decrypting state file"
			echo "${pass}" |
				gpg --batch \
					--passphrase-fd 0 \
					--output "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/terraform.tfstate" \
					--decrypt "${CONFIG_REPO_PATH}/DEPLOYER/${DEPLOYER_FOLDERNAME}/state.gpg"
		fi
		if [ -f "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.gpg" ]; then
			echo "Decrypting state file"
			echo "${pass}" |
				gpg --batch \
					--passphrase-fd 0 \
					--output "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate" \
					--decrypt "${CONFIG_REPO_PATH}/LIBRARY/$LIBRARY_FOLDERNAME/state.gpg"
		fi
	else
		exit_error "Private PGP key not found." 3
	fi
	pass="localpassword"
fi

end_group

echo -e "$green--- Running the remove remove_control_plane_v2 that destroys SAP library ---$reset_formatting"

# Platform-specific flags
if [ "$PLATFORM" == "devops" ]; then
	platform_flag=" --ado"
elif [ "$PLATFORM" == "github" ]; then
	platform_flag=" --github"
else
	platform_flag=""
fi

if "$SAP_AUTOMATION_REPO_PATH/deploy/scripts/remove_control_plane_v2.sh" \
	--deployer_parameter_file "$deployerTFvarsFile" \
	--library_parameter_file "$libraryTFvarsFile" \
	"$platform_flag" --auto-approve --keep_agent; then
	return_code=$?
	print_banner "$banner_title" "Control Plane ${CONTROL_PLANE_NAME} removal step 1 completed" "success"

	echo "##vso[task.logissue type=warning]Control Plane ${CONTROL_PLANE_NAME} removal step 1 completed."
else
	return_code=$?
	print_banner "$banner_title" "Control Plane ${CONTROL_PLANE_NAME} removal step 1 failed" "error"
fi

echo "Return code from remove_control_plane_v2: $return_code."

echo -e "$green--- Remove Control Plane Part 1 ---$reset_formatting"
cd "$CONFIG_REPO_PATH" || exit
# Pull latest changes from appropriate branch
if [ "$PLATFORM" == "devops" ]; then
	git pull -q origin "$BUILD_SOURCEBRANCHNAME"
elif [ "$PLATFORM" == "github" ]; then
	git pull -q origin "$GITHUB_REF_NAME"
fi

changed=0
if [ -f "$deployer_environment_file_name" ]; then
	git add "$deployer_environment_file_name"
	changed=1
fi

if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/$libraryTFvarsFile" ]; then
	sed -i /"custom_random_id"/d "LIBRARY/$LIBRARY_FOLDERNAME/$libraryTFvarsFile"
	git add -f "LIBRARY/$LIBRARY_FOLDERNAME/$libraryTFvarsFile"
	changed=1
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

if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate" ]; then
	git add -f "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate"
	added=1

	# || true suppresses the exitcode of grep. To not trigger the strict exit on error
	local_backend=$(grep "\"type\": \"local\"" "LIBRARY/$LIBRARY_FOLDERNAME/.terraform/terraform.tfstate" || true)

	if [ -n "$local_backend" ]; then
		echo "Deployer Terraform state:              local"

		if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/terraform.tfstate" ]; then
			echo "Compressing the library state file"
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
		fi
	fi
fi

if [ -f "LIBRARY/$LIBRARY_FOLDERNAME/backend-config.tfvars" ]; then
	git rm -q --ignore-unmatch "LIBRARY/$LIBRARY_FOLDERNAME/backend-config.tfvars"
	changed=1
fi

# Commit changes based on platform
if [ 1 == $changed ]; then
	if [ "$PLATFORM" == "devops" ]; then
		git config --global user.email "$BUILD_REQUESTEDFOREMAIL"
		git config --global user.name "$BUILD_REQUESTEDFOR"
		commit_message="Added updates from Control Plane Deployment for ${CONTROL_PLANE_NAME} $BUILD_BUILDNUMBER [skip ci]"
	elif [ "$PLATFORM" == "github" ]; then
		git config --global user.email "github-actions@github.com"
		git config --global user.name "GitHub Actions"
		commit_message="Added updates from Control Plane Deployment for ${CONTROL_PLANE_NAME} [skip ci]"
	else
		git config --global user.email "local@example.com"
		git config --global user.name "Local User"
		commit_message="Added updates from Control Plane Deployment for ${CONTROL_PLANE_NAME} [skip ci]"
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
print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

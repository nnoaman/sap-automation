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

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
banner_title="SAP Configuration and Installation - Ansible"

#call stack has full script name when using source
# shellcheck disable=SC1091
source "${parent_directory}/deploy_utils.sh"

#call stack has full script name when using source
source "${script_directory}/helper.sh"

DEBUG=False

if [ "$SYSTEM_DEBUG" = True ]; then
	set -x
	DEBUG=True
	echo "Environment variables:"
	printenv | sort

fi
export DEBUG
set -eu

print_banner "$banner_title" "Starting $SCRIPT_NAME" "info"
#Stage could be executed on a different machine by default, need to login again for ansible
#If the deployer_file exists we run on a deployer configured by the framework instead of a azdo hosted one

if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then

	control_plane_subscription=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_SubscriptionId" "${CONTROL_PLANE_NAME}")

fi
export control_plane_subscription

deployer_file=/etc/profile.d/deploy_server.sh

if [ $USE_MSI != "true" ]; then
	echo "##[section]Running on a deployer..."
	source /etc/profile.d/deploy_server.sh
	noAccess=$(az account show --query name | grep "N/A(tenant level account)")

	if [ -z "$noAccess" ]; then
		az account set --subscription $AZURE_SUBSCRIPTION_ID --output none
	fi
else
	echo "##[section]Running on an Azure DevOps agent..."

	if [ '$(ARM_CLIENT_ID)' == $AZURE_CLIENT_ID ]; then
		source /etc/profile.d/deploy_server.sh
		noAccess=$(az account show --query name | grep "N/A(tenant level account)")

		if [ -z "$noAccess" ]; then
			az account set --subscription $AZURE_SUBSCRIPTION_ID --output none
		fi
	else
		az login --service-principal -u $AZURE_CLIENT_ID -p=$AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID --output none
		az account set --subscription $AZURE_SUBSCRIPTION_ID --output none
	fi

	az account set --subscription $AZURE_SUBSCRIPTION_ID --output none

fi

set -eu

if [ ! -f $PARAMETERS_FOLDER/sshkey ]; then
	echo "##[section]Retrieving sshkey..."
	az keyvault secret show --name "$SSH_KEY_NAME" --vault-name "$VAULT_NAME" --subscription "$CONTROL_PLANE_SUBSCRIPTION_ID" --query value --output tsv >"$PARAMETERS_FOLDER/sshkey"
	sudo chmod 600 "$PARAMETERS_FOLDER"/sshkey
fi

password_secret=$(az keyvault secret show --name "$PASSWORD_KEY_NAME" --vault-name "$VAULT_NAME" --query value --output tsv)

echo "Extra parameters passed: " "$EXTRA_PARAMS"

base=$(basename "$ANSIBLE_FILE_PATH")

filename_without_prefix=$(echo "$base" | awk -F'.' '{print $1}')
filename=./config/Ansible/"${filename_without_prefix}"_pre.yml
return_code=0

echo "Extra parameters passed: " $EXTRA_PARAMS
echo "Check for file: ${filename}"

command="ansible --version"
eval $command

EXTRA_PARAM_FILE=""

if [ -f $PARAMETERS_FOLDER/extra-params.yaml ]; then
	echo "Extra parameter file passed: " $PARAMETERS_FOLDER/extra-params.yaml

	EXTRA_PARAM_FILE="-e @$PARAMETERS_FOLDER/extra-params.yaml"
fi

############################################################################################
#                                                                                          #
# Run Pre tasks if Ansible playbook with the correct naming exists                         #
#                                                                                          #
############################################################################################

if [ -f "${filename}" ]; then
	echo "##[group]- preconfiguration"

	redacted_command="ansible-playbook -i $INVENTORY -e @$SAP_PARAMS "$EXTRA_PARAMS" $EXTRA_PARAM_FILE ${filename} -e 'kv_name=$VAULT_NAME'"
	echo "##[section]Executing [$redacted_command]..."

	command="ansible-playbook -i $INVENTORY --private-key $PARAMETERS_FOLDER/sshkey  -e 'kv_name=$VAULT_NAME' \
            -e @$SAP_PARAMS -e 'download_directory=$AGENT_TEMPDIRECTORY' -e '_workspace_directory=$PARAMETERS_FOLDER' "$EXTRA_PARAMS"  \
            -e ansible_ssh_pass='${password_secret}' $EXTRA_PARAM_FILE ${filename}"

	eval $command
	return_code=$?
	echo "##[section]Ansible playbook ${filename} execution completed with exit code [$return_code]"
	echo "##[endgroup]"

fi

command="ansible-playbook -i $INVENTORY --private-key $PARAMETERS_FOLDER/sshkey   -e 'kv_name=$VAULT_NAME'   \
      -e @$SAP_PARAMS -e 'download_directory=$AGENT_TEMPDIRECTORY' -e '_workspace_directory=$PARAMETERS_FOLDER' \
      -e ansible_ssh_pass='${password_secret}' "$EXTRA_PARAMS" $EXTRA_PARAM_FILE                                  \
       $ANSIBLE_FILE_PATH"

redacted_command="ansible-playbook -i $INVENTORY -e @$SAP_PARAMS "$EXTRA_PARAMS" $EXTRA_PARAM_FILE $ANSIBLE_FILE_PATH  -e 'kv_name=$VAULT_NAME'"

echo "##[section]Executing [$redacted_command]..."
echo "##[group]- output"
eval $command
return_code=$?
echo "##[section]Ansible playbook execution completed with exit code [$return_code]"
echo "##[endgroup]"

filename=./config/Ansible/"${filename_without_prefix}"_post.yml
echo "Check for file: ${filename}"

############################################################################################
#                                                                                          #
# Run Post tasks if Ansible playbook with the correct naming exists                        #
#                                                                                          #
############################################################################################

if [ -f ${filename} ]; then

	echo "##[group]- postconfiguration"
	redacted_command="ansible-playbook -i "$INVENTORY" -e @"$SAP_PARAMS" "$EXTRA_PARAMS" $EXTRA_PARAM_FILE "${filename}"  -e 'kv_name=$VAULT_NAME'"
	echo "##[section]Executing [$redacted_command]..."

	command="ansible-playbook -i "$INVENTORY" --private-key $PARAMETERS_FOLDER/sshkey   -e 'kv_name=$VAULT_NAME'      \
            -e @$SAP_PARAMS -e 'download_directory=$AGENT_TEMPDIRECTORY' -e '_workspace_directory=$PARAMETERS_FOLDER' \
            -e ansible_ssh_pass='${password_secret}' ${filename}  "$EXTRA_PARAMS" $EXTRA_PARAM_FILE"

	eval $command
	return_code=$?
	echo "##[section]Ansible playbook ${filename} execution completed with exit code [$return_code]"
	echo "##[endgroup]"

fi

print_banner "$banner_title" "Exiting $SCRIPT_NAME" "info"

exit $return_code

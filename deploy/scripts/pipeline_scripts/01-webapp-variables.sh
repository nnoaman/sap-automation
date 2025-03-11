#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.


full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"

source "${parent_directory}/deploy_utils.sh"
source "${script_directory}/helper.sh"

if ! az extension list --query "[?contains(name, 'azure-devops')].name" --output tsv; then
	az extension add --name azure-devops --output none --only-show-errors
fi

az devops configure --defaults organization=$SYSTEM_COLLECTIONURI project=$
app_service_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_AppServiceId" "${CONTROL_PLANE_NAME}")
if [ -n "$app_service_id" ]; then
  app_service_name=$(echo $app_service_id | cut -d'/' -f9)
	print_banner "Web App Preparation" "Setting the output variables" "info"
  echo "##vso[task.setvariable variable=APPSERVICE_NAME;isOutput=true]$app_service_name"
  echo "##vso[task.setvariable variable=HAS_WEBAPP;isOutput=true]true"
else
  echo "##vso[task.setvariable variable=HAS_WEBAPP;isOutput=true]false"
fi
exit 0

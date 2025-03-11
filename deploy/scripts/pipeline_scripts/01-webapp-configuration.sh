#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"

source "${parent_directory}/deploy_utils.sh"
source "${script_directory}/helper.sh"

app_service_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_AppServiceId" "${CONTROL_PLANE_NAME}")
app_service_identity_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_AppServiceIdentityId" "${CONTROL_PLANE_NAME}")
deployer_msi_id=$(getVariableFromApplicationConfiguration "$APPLICATION_CONFIGURATION_ID" "${CONTROL_PLANE_NAME}_Deployer_MSI_Id" "${CONTROL_PLANE_NAME}")
app_service_name=$(echo "$app_service_id" | cut -d '/' -f 9)

printf "Configure the Web Application authentication using the following script.\n" >"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "\n\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "az ad app update --id %s --web-home-page-url https://%s.azurewebsites.net --web-redirect-uris https://%s.azurewebsites.net/ https://%s.azurewebsites.net/.auth/login/aad/callback\n\n" "$(APP_REGISTRATION_APP_ID)" "$app_service_name" "$app_service_name" "$app_service_name" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "az role assignment create --assignee %s --role reader --subscription %s --scope /subscriptions/%s\n" "$app_service_identity_id" "$ARM_SUBSCRIPTION_ID" "$ARM_SUBSCRIPTION_ID" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "Run the above command for all subscriptions you want to use in the Web Application\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "az role assignment create --assignee %s --role 'Storage Blob Data Contributor' --subscription %s --scope /subscriptions/%s/resourceGroups/%s\n" "$app_service_identity_id" "$ARM_SUBSCRIPTION_ID" "$ARM_SUBSCRIPTION_ID" "$(Terraform_Remote_Storage_Resource_Group_Name)" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "az role assignment create --assignee %s --role 'Storage Table Data Contributor' --subscription %s --scope /subscriptions/%s/resourceGroups/%s \n\n" "$app_service_identity_id" "$ARM_SUBSCRIPTION_ID" "$ARM_SUBSCRIPTION_ID" "$(Terraform_Remote_Storage_Resource_Group_Name)" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "az rest --method POST --uri \"https://graph.microsoft.com/beta/applications/%s/federatedIdentityCredentials\" --body \"{'name': 'ManagedIdentityFederation', 'issuer': 'https://login.microsoftonline.com/%s/v2.0', 'subject': '%s', 'audiences': [ 'api://AzureADTokenExchange' ]}\"" "$(APP_REGISTRATION_OBJECTID)" "$ARM_TENANT_ID" "$deployer_msi_id" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "az webapp restart --ids %s\n\n $(WEBAPP_ID)" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"
printf "\n\n" >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

printf "[Access the Web App](https://%s.azurewebsites.net) \n\n" $app_service_name >>"$(Build.Repository.LocalPath)/Web Application Configuration.md"

echo "##vso[task.uploadsummary]$(Build.Repository.LocalPath)/Web Application Configuration.md"
exit 0

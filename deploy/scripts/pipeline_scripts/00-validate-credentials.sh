#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

if ! az extension list --query "[?contains(name, 'azure-devops')].name" --output tsv; then
	az extension add --name azure-devops --output none --only-show-errors
fi

az devops configure --defaults organization=$SYSTEM_COLLECTIONURI project=$SYSTEM_TEAMPROJECTID

VARIABLE_GROUP_ID=$(az pipelines variable-group list --query "[?name=='$VARIABLE_GROUP'].id | [0]")
if [ -n "${VARIABLE_GROUP_ID}" ]; then
	echo '$VARIABLE_GROUP id: ' $VARIABLE_GROUP_ID

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "APPLICATION_CONFIGURATION_ID.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=APPLICATION_CONFIGURATION_ID;isOutput=true]$az_var"
	else
		if printenv APPLICATION_CONFIGURATION_ID; then
			echo "##vso[task.setvariable variable=APPLICATION_CONFIGURATION_ID;isOutput=true]$APPLICATION_CONFIGURATION_ID"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "CONTROL_PLANE_NAME.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=CONTROL_PLANE_NAME;isOutput=true]$az_var"
	else
		if printenv CONTROL_PLANE_NAME; then
			echo "##vso[task.setvariable variable=CONTROL_PLANE_NAME;isOutput=true]$CONTROL_PLANE_NAME"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_SUBSCRIPTION_ID.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$az_var"
	else
		if printenv ARM_SUBSCRIPTION_ID; then
			echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_SUBSCRIPTION_ID"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_CLIENT_ID.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=ARM_CLIENT_ID;isOutput=true]$az_var"
	else
		if printenv ARM_CLIENT_ID; then
			echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_CLIENT_ID"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_CLIENT_SECRET.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=ARM_CLIENT_SECRET;isOutput=true;issecret=true]$az_var"
	else
		if printenv ARM_CLIENT_SECRET; then
			echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_CLIENT_SECRET"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_TENANT_ID.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=ARM_TENANT_ID;isOutput=true]$az_var"
	else
		if printenv ARM_TENANT_ID; then
			echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_TENANT_ID"
		fi
	fi

	az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_OBJECT_ID.value")
	if [ -n "${az_var}" ]; then
		echo "##vso[task.setvariable variable=ARM_OBJECT_ID;isOutput=true]$az_var"
	else
		if printenv ARM_OBJECT_ID; then
			echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_OBJECT_ID"
		fi
	fi
fi

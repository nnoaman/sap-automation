#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

VARIABLE_GROUP_ID=$(az pipelines variable-group list --query "[?name=='$VARIABLE_GROUP'].id | [0]")
echo '$VARIABLE_GROUP id: ' $VARIABLE_GROUP_ID

az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_SUBSCRIPTION_ID.value")
if [ -n "${az_var}" ]; then
	echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$az_var"
fi

az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_CLIENT_ID.value")
if [ -n "${az_var}" ]; then
	echo "##vso[task.setvariable variable=ARM_CLIENT_ID;isOutput=true]$az_var"
fi

az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_CLIENT_SECRET.value")
if [ -n "${az_var}" ]; then
	echo "##vso[task.setvariable variable=ARM_CLIENT_SECRET;isOutput=true]$az_var"
fi

az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_TENANT_ID.value")
if [ -n "${az_var}" ]; then
	echo "##vso[task.setvariable variable=ARM_TENANT_ID;isOutput=true]$az_var"
fi

az_var=$(az pipelines variable-group variable list --group-id "${VARIABLE_GROUP_ID}" --query "ARM_OBJECT_ID.value")
if [ -n "${az_var}" ]; then
	echo "##vso[task.setvariable variable=ARM_OBJECT_ID;isOutput=true]$az_var"
fi

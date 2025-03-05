#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Description: This script validates the credentials and sets the output variables for the pipeline.
if [ "${CHECK_ARM_SUBSCRIPTION_ID:0:2}" != '$(' ]; then
	echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$CHECK_ARM_SUBSCRIPTION_ID"
else
	test=$(printenv ARM_SUBSCRIPTION_ID)
	if [ -n "$test" ]; then
		echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$ARM_SUBSCRIPTION_ID"
	else
		echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]"
	fi
fi

if [ "${CHECK_ARM_CLIENT_ID:0:2}" != '$(' ]; then
	echo "##vso[task.setvariable variable=ARM_SUBSCRIPTION_ID;isOutput=true]$CHECK_ARM_CLIENT_ID"
else
	test=$(printenv ARM_CLIENT_ID)
	if [ -n "$test" ]; then
		echo "##vso[task.setvariable variable=ARM_CLIENT_ID;isOutput=true]$ARM_CLIENT_ID"
	else
		echo "##vso[task.setvariable variable=ARM_CLIENT_ID;isOutput=true]"
	fi
fi

if [ "${CHECK_ARM_CLIENT_SECRET:0:2}" != '$(' ]; then
	echo "##vso[task.setvariable variable=ARM_CLIENT_SECRET;isOutput=true]$CHECK_ARM_CLIENT_SECRET"
else
	test=$(printenv ARM_CLIENT_SECRET)
	if [ -n "$test" ]; then
		echo "##vso[task.setvariable variable=ARM_CLIENT_SECRET;isOutput=true]$ARM_CLIENT_SECRET"
	else
		echo "##vso[task.setvariable variable=ARM_CLIENT_SECRET;isOutput=true]"
	fi
fi

if [ "${CHECK_ARM_TENANT_ID:0:2}" != '$(' ]; then
	echo "##vso[task.setvariable variable=ARM_TENANT_ID;isOutput=true]$CHECK_ARM_TENANT_ID"
else
	test=$(printenv ARM_TENANT_ID)
	if [ -n "$test" ]; then
		echo "##vso[task.setvariable variable=ARM_TENANT_ID;isOutput=true]$ARM_TENANT_ID"
	else
		echo "##vso[task.setvariable variable=ARM_TENANT_ID;isOutput=true]"
	fi
fi

if [ "${CHECK_ARM_OBJECT_ID:0:2}" != '$(' ]; then
	echo "##vso[task.setvariable variable=ARM_OBJECT_ID;isOutput=true]$CHECK_ARM_OBJECT_ID"
else
	test=$(printenv ARM_OBJECT_ID)
	if [ -n "$test" ]; then
		echo "##vso[task.setvariable variable=ARM_OBJECT_ID;isOutput=true]$ARM_OBJECT_ID"
	else
		echo "##vso[task.setvariable variable=ARM_OBJECT_ID;isOutput=true]"
	fi
fi

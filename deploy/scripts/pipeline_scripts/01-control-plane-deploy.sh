#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

if printenv APPLICATION_CONFIGURATION_ID; then
	v2/01-control-plane-deploy.sh "$@"
else
	v1/01-control-plane-deploy.sh "$@"
fi

#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

if printenv APPLICATION_CONFIGURATION_ID ; then
	"${script_directory}/v2/01-control-plane-deploy.sh" "$@"
else
	"${script_directory}/v1/01-control-plane-deploy.sh" "$@"
fi

#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

if printenv APPLICATION_CONFIGURATION_ID ; then
	"${script_directory}/v2/02-sap-workload-zone" "$@"
else
	"${script_directory}/v1/02-sap-workload-zone" "$@"
fi

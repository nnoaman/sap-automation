#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"

source "${parent_directory}/deploy_utils.sh"

if printenv APPLICATION_CONFIGURATION_ID; then
	if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then
		echo "Running v2 script"
		"${script_directory}/v2/02-sap-workload-zone.sh" "$@"
	else
		echo "Running v1 script"
		"${script_directory}/v1/02-sap-workload-zone.sh" "$@"
	fi
else
	echo "Running v1 script"
	"${script_directory}/v1/02-sap-workload-zone.sh" "$@"
fi

#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"

if printenv APPLICATION_CONFIGURATION_ID ; then
  echo "Running v2 script"
	# list parameters being passed to the script
	echo "List Parameters: $*"

	"${script_directory}/v2/02-sap-workload-zone.sh" "$@"
else
	echo "Running v1 script"
	"${script_directory}/v1/02-sap-workload-zone.sh" "$@"
fi

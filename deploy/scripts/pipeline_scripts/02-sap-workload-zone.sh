#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

source "${parent_directory}/deploy_utils.sh"

return_code=0

if printenv APPLICATION_CONFIGURATION_ID; then
	if is_valid_id "$APPLICATION_CONFIGURATION_ID" "/providers/Microsoft.AppConfiguration/configurationStores/"; then

		resCheck=$(az resource show --ids "$APPLICATION_CONFIGURATION_ID" --query "id" --output tsv)
		if [ -z "$resCheck" ]; then
			echo ""
			echo "Running v1 script"
			echo ""
			if ! "${script_directory}/v1/$SCRIPT_NAME" "$@"; then
				return_code$?
			fi
		else
			echo ""
			echo "Running v2 script"
			echo ""
			if ! "${script_directory}/v2/$SCRIPT_NAME" "$@"; then
				return_code$?
			fi
		fi
	else
		echo ""
		echo "Running v1 script"
		echo ""
		if ! "${script_directory}/v1/$SCRIPT_NAME" "$@"; then
			return_code$?
		fi
	fi
else
	echo ""
	echo "Running v1 script"
	echo ""
	if ! "${script_directory}/v1/$SCRIPT_NAME" "$@"; then
		return_code$?
	fi
fi

echo "Return code: $return_code"

exit $return_code

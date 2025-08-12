#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

full_script_path="$(realpath "${BASH_SOURCE[0]}")"
script_directory="$(dirname "${full_script_path}")"
parent_directory="$(dirname "$script_directory")"
SCRIPT_NAME="$(basename "$0")"

#call stack has full script name when using source
source "${script_directory}/helper.sh"
source "${parent_directory}/deploy_utils.sh"
	echo "Environment variables:"
	printenv | sort

set -eu
DEBUG=false
set -o pipefail

if [ "${SYSTEM_DEBUG:-false}" = true ]; then
	set -x
	DEBUG=true
	echo "Environment variables:"
	printenv | sort
fi
export DEBUG

return_code=0

if checkforDevOpsVar APPLICATION_CONFIGURATION_NAME; then
	echo ""
	echo "Running v2 script"
	export SDAFWZ_CALLER_VERSION="v2"
	echo ""
	echo "${SYSTEM_DEBUG:-false}"
  echo "${DEBUG:-false}"
	"${script_directory}/v2/$SCRIPT_NAME"
else
	echo ""
	echo "Running v1 script"
	export SDAFWZ_CALLER_VERSION="v1"
	echo ""
	"${script_directory}/v1/$SCRIPT_NAME"
fi

echo "Return code: $return_code"

exit $return_code

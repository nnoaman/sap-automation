#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

echo "##vso[task.setvariable variable=HAS_WEBAPP;isOutput=true]$(HAS_APPSERVICE_DEPLOYED)"

exit 0

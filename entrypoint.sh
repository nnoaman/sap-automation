#!/bin/bash
set -e

# Ensure GitHub Actions directories exist
mkdir -p /__w/_temp/_runner_file_commands /__w/_actions /github/home /github/workflow

# Fix ownership and permissions for current user
chown -R $(id -u):$(id -g) /__w /github || true
chmod -R 770 /__w /github || true

# Execute the original command
exec "$@"

#!/usr/bin/env bash

function setup_dependencies() {
    git config --global --add safe.directory ${GITHUB_WORKSPACE}

    # Install Azure CLI extensions if needed
    az config set extension.use_dynamic_install=yes_without_prompt > /dev/null 2>&1

    echo "Working with environment: ${CONTROL_PLANE_NAME}"
}

function exit_error() {
    MESSAGE="$(caller | awk '{print $2":"$1} ') $1"
    ERROR_CODE=$2

    echo "::error::${MESSAGE}"
    exit $ERROR_CODE
}

function log_warning() {
    MESSAGE=$1

    echo "::warning::${MESSAGE}"
}

function start_group() {
    MESSAGE=$1

    echo "::group::${MESSAGE}"
}

function end_group() {
    echo "::endgroup::"
}

function commit_changes() {
    message=$1
    is_custom_message=${2:-false}

    git config --global user.email github-actions@github.com
    git config --global user.name github-actions

    if [[ $is_custom_message == "true" ]]; then
        git commit -m "${message}"
    else
        git commit -m "${message} - Workflow: ${GITHUB_WORKFLOW}:${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT} [skip ci]"
    fi

    git push
}

function __get_value_with_key() {
    key=$1
    env=${2:-$CONTROL_PLANE_NAME}

    # Extract owner and repo from GITHUB_REPOSITORY
    REPO_OWNER=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 1)
    REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 2)

    value=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/variables/${key}" | jq -r '.value // empty')

    echo $value
}

function __set_value_with_key() {
    key=$1
    new_value=$2
    env=${3:-$CONTROL_PLANE_NAME}

    # Extract owner and repo from GITHUB_REPOSITORY
    REPO_OWNER=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 1)
    REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d '/' -f 2)

    echo "Saving value for key in environment $env: ${key}"

    # First, ensure the environment exists (GitHub API doesn't create it automatically)
    env_check=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}")

    if [[ $(echo $env_check | jq -r '.message // empty') == "Not Found" ]]; then
        echo "Environment ${env} doesn't exist. Creating it first..."
        create_result=$(curl -s \
            -X PUT \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${APP_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}" \
            -d "{}")

        if [[ $(echo $create_result | jq -r '.message // empty') == "Not Found" ]]; then
            echo "Failed to create environment. Check APP_TOKEN permissions."
            return 1
        fi
    fi

    # Check if variable already exists
    response=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/variables/${key}")

    error_message=$(echo $response | jq -r '.message // empty')

    if [[ $error_message == "Not Found" ]]; then
        # Variable doesn't exist, create it
        echo "Creating new variable ${key}"
        result=$(curl -s \
            -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${APP_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/variables" \
            -d "{\"name\":\"${key}\", \"value\":\"${new_value}\"}")

        error_message=$(echo $result | jq -r '.message // empty')
        if [[ -n "$error_message" ]]; then
            echo "Error creating variable: ${error_message}"
            # Also output to GitHub Actions log as an error
            echo "::error::Failed to create variable ${key}: ${error_message}"
            return 1
        fi
    else
        # Variable exists, update it
        current_value=$(echo $response | jq -r '.value // empty')
        if [[ "$current_value" != "$new_value" ]]; then
            echo "Updating existing variable ${key}"
            result=$(curl -s \
                -X PATCH \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer ${APP_TOKEN}" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/variables/${key}" \
                -d "{\"name\":\"${key}\", \"value\":\"${new_value}\"}")

            error_message=$(echo $result | jq -r '.message // empty')
            if [[ -n "$error_message" ]]; then
                echo "Error updating variable: ${error_message}"
                echo "::error::Failed to update variable ${key}: ${error_message}"
                return 1
            fi
        else
            echo "Variable ${key} already has the correct value"
        fi
    fi

    # Also set the variable for the current job output
    echo "${key}=${new_value}" >> $GITHUB_ENV
}

function __get_secret_with_key() {
    key=$1
    env=${2:-$CONTROL_PLANE_NAME}

    # GitHub Actions doesn't allow direct access to secrets via API
    # We can only check if the secret exists
    status_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/secrets/${key}")

    if [[ $status_code == "200" ]]; then
        echo "REDACTED_SECRET_EXISTS"
    else
        echo ""
    fi
}

function __set_secret_with_key() {
    key=$1
    value=$2
    env=${3:-$CONTROL_PLANE_NAME}

    echo "Saving secret value for key in environment ${env}: ${key}"

    # First, ensure the environment exists (GitHub API doesn't create it automatically)
    env_check=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}")

    if [[ $(echo $env_check | jq -r '.message // empty') == "Not Found" ]]; then
        echo "Environment ${env} doesn't exist. Creating it first..."
        create_result=$(curl -s \
            -X PUT \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${APP_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}" \
            -d "{}")

        if [[ $(echo $create_result | jq -r '.message // empty') == "Not Found" ]]; then
            echo "Failed to create environment. Check APP_TOKEN permissions."
            return 1
        fi
    fi

    # Get public key for the repository to encrypt the secret
    public_key_response=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${APP_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/secrets/public-key")

    public_key=$(echo $public_key_response | jq -r .key)
    public_key_id=$(echo $public_key_response | jq -r .key_id)

    if [[ -z "$public_key" || "$public_key" == "null" ]]; then
        echo "Error retrieving public key: $(echo $public_key_response | jq -r '.message // empty')"
        echo "::error::Failed to retrieve environment public key. Check APP_TOKEN permissions."
        return 1
    fi

    # For GitHub Actions secrets, we need to use sodium to encrypt the value
    # This is a simplified version - in production you should use proper encryption
    # We'll use GitHub CLI if available as it handles encryption for us
    if command -v gh &>/dev/null; then
        # Check if secret exists
        if gh api "/repos/${GITHUB_REPOSITORY}/environments/${env}/secrets/${key}" --silent 2>/dev/null; then
            # Update existing secret
            echo "Updating existing secret ${key} using GitHub CLI"
            echo "$value" | gh secret set "$key" --env "$env" --repo "${GITHUB_REPOSITORY}"
        else
            # Create new secret
            echo "Creating new secret ${key} using GitHub CLI"
            echo "$value" | gh secret set "$key" --env "$env" --repo "${GITHUB_REPOSITORY}"
        fi
    else
        echo "::warning::GitHub CLI not available. Cannot securely encrypt and set secret. Install gh CLI for better secret handling."
        echo "::warning::Setting a placeholder for ${key} only to indicate it should exist."

        # Check if secret exists
        status_code=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${APP_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/secrets/${key}")

        method="PUT"
        if [[ $status_code != "200" ]]; then
            method="POST"
        fi

        # Note: In production code, you should properly encrypt the value using sodium
        # This is just a placeholder that won't work for actual secret setting
        curl -s -o /dev/null \
            -X $method \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${APP_TOKEN}" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -L "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/environments/${env}/secrets/${key}" \
            -d "{\"encrypted_value\":\"PLACEHOLDER\", \"key_id\":\"${public_key_id}\"}"
    fi
}

function upload_summary() {
    summary=$1
    if [[ -f $GITHUB_STEP_SUMMARY ]]; then
        cat $summary >> $GITHUB_STEP_SUMMARY
    else
        echo $summary >> $GITHUB_STEP_SUMMARY
    fi
}

function output_variable() {
    name=$1
    value=$2

    echo "${name}=${value}" >> $GITHUB_OUTPUT
}

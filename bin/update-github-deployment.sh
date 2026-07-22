#!/bin/bash

set -euo pipefail

# Default values
STATE=""
ENVIRONMENT=""
DESCRIPTION=""
DEPLOYMENT_ID=""
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO=""
REF=""
# Generate unique deployment ID file path based on GoCD variables
# Falls back to simple path if GoCD variables not available
if [[ -n "${GO_PIPELINE_NAME:-}" && -n "${GO_PIPELINE_COUNTER:-}" ]]; then
    DEFAULT_DEPLOYMENT_FILE="/tmp/github_deployment_${GO_PIPELINE_NAME}_${GO_PIPELINE_COUNTER}.txt"
else
    DEFAULT_DEPLOYMENT_FILE="/tmp/github_deployment_id.txt"
fi

DEPLOYMENT_ID_FILE="${DEPLOYMENT_ID_FILE:-$DEFAULT_DEPLOYMENT_FILE}"

# GitHub API settings
GITHUB_API_URL="https://api.github.com"
ACCEPT_HEADER="application/vnd.github+json"
API_VERSION="2026-03-10"

# Helper Functions

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

show_usage() {
    cat << EOF
Usage: $0 --state <state> --environment <env> [options]

Required Arguments:
  --state <state>           Deployment state: pending, success, failure, error, inactive, in_progress, queued
  --environment <env>       Deployment environment (e.g., live, uat, playground)

Optional Arguments:
  --description <desc>      Description of the deployment
  --deployment-id <id>      Existing deployment ID (for updates only)
  --github-token <token>    GitHub personal access token
  --repo <owner/repo>       GitHub repository (owner/repo format)
  --ref <ref>               Git reference to deploy (default: current commit SHA)
  --help                    Show this help message

Environment Variables:
  GITHUB_TOKEN              GitHub personal access token (required)
  GO_REPOSITORY_NAME        GitHub repository (owner/repo format)
  GO_PIPELINE_NAME          GoCD pipeline name (for unique file & description)
  GO_STAGE_NAME             GoCD stage name (for description)
  GO_REVISION               Git commit SHA (for deployment ref)
  GO_PIPELINE_COUNTER       Pipeline run counter (for unique file & description)
  DEPLOYMENT_ID_FILE        Custom path to deployment ID file
                            (auto-generated if not set:
                             /tmp/github_deployment_PIPELINE_COUNTER.txt)
EOF
}

# Parse Command Line Arguments

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --state)
                STATE="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --description)
                DESCRIPTION="$2"
                shift 2
                ;;
            --deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            --github-token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --repo)
                REPO="$2"
                shift 2
                ;;
            --ref)
                REF="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 0  # Exit 0 to not break pipeline
                ;;
        esac
    done
}

# Validation Functions

validate_inputs() {
    # Check required state parameter
    if [[ -z "$STATE" ]]; then
        log_error "Missing required argument: --state"
        show_usage
        return 1
    fi

    # Check required environment parameter
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Missing required argument: --environment"
        log_error "You must specify the deployment environment (e.g., --environment live, --environment uat, --environment playground)"
        show_usage
        return 1
    fi

    # Validate state value
    local valid_states=("pending" "success" "failure" "error" "inactive" "in_progress" "queued")
    local state_valid=false
    for valid_state in "${valid_states[@]}"; do
        if [[ "$STATE" == "$valid_state" ]]; then
            state_valid=true
            break
        fi
    done

    if [[ "$state_valid" == false ]]; then
        log_error "Invalid state: $STATE. Must be one of: ${valid_states[*]}"
        return 1
    fi

    # Check GitHub token
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_error "GitHub token not provided. Set GITHUB_TOKEN environment variable or use --github-token"
        return 1
    fi

    return 0
}

# Auto-detect Repository Information

detect_repo() {
    if [[ -n "$REPO" ]]; then
        log_info "Using provided repository: $REPO"
        return 0
    fi

    # Try GoCD environment variable first
    if [[ -n "${GO_REPOSITORY_NAME:-}" ]]; then
        REPO="$GO_REPOSITORY_NAME"
        log_info "Using GO_REPOSITORY_NAME: $REPO"
        return 0
    fi

    # Try to get repo from git remote
    if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null; then
        local remote_url
        remote_url=$(git config --get remote.origin.url 2>/dev/null || echo "")

        if [[ -n "$remote_url" ]]; then
            # Extract owner/repo from various Git URL formats
            # SSH: git@github.com:owner/repo.git
            # HTTPS: https://github.com/owner/repo.git
            REPO=$(echo "$remote_url" | sed -E 's/.*[:/]([^/]+\/[^/]+)\.git$/\1/' | sed 's/\.git$//')
            log_info "Auto-detected repository from git remote: $REPO"
            return 0
        fi
    fi

    log_error "Could not detect repository. Please provide --repo owner/repo or set GO_REPOSITORY_NAME"
    return 1
}

detect_ref() {
    if [[ -n "$REF" ]]; then
        log_info "Using provided ref: $REF"
        return 0
    fi

    # Try GoCD environment variable first
    if [[ -n "${GO_REVISION:-}" ]]; then
        REF="$GO_REVISION"
        log_info "Using GO_REVISION: $REF"
        return 0
    fi

    # Fall back to current git commit
    if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null; then
        REF=$(git rev-parse HEAD 2>/dev/null || echo "")
        if [[ -n "$REF" ]]; then
            log_info "Using current git commit: $REF"
            return 0
        fi
    fi

    log_error "Could not detect git reference. Please provide --ref"
    return 1
}

# Build Description from GoCD Variables

build_description() {
    if [[ -n "$DESCRIPTION" ]]; then
        echo "$DESCRIPTION"
        return 0
    fi

    local desc=""

    if [[ -n "${GO_PIPELINE_NAME:-}" ]]; then
        desc="Pipeline: ${GO_PIPELINE_NAME}"
    fi

    if [[ -n "${GO_STAGE_NAME:-}" ]]; then
        if [[ -n "$desc" ]]; then
            desc="${desc} | Stage: ${GO_STAGE_NAME}"
        else
            desc="Stage: ${GO_STAGE_NAME}"
        fi
    fi

    if [[ -n "${GO_PIPELINE_COUNTER:-}" ]]; then
        if [[ -n "$desc" ]]; then
            desc="${desc} | Run: #${GO_PIPELINE_COUNTER}"
        else
            desc="Run: #${GO_PIPELINE_COUNTER}"
        fi
    fi

    # If no GoCD variables available, use a default description
    if [[ -z "$desc" ]]; then
        desc="Deployment to ${ENVIRONMENT}"
    fi

    echo "$desc"
}

# Load Deployment ID from File

load_deployment_id() {
    if [[ -n "$DEPLOYMENT_ID" ]]; then
        log_info "Using provided deployment ID: $DEPLOYMENT_ID"
        return 0
    fi

    if [[ -f "$DEPLOYMENT_ID_FILE" ]]; then
        DEPLOYMENT_ID=$(cat "$DEPLOYMENT_ID_FILE" 2>/dev/null || echo "")
        if [[ -n "$DEPLOYMENT_ID" ]]; then
            log_info "Loaded deployment ID from file: $DEPLOYMENT_ID"
            return 0
        fi
    fi

    return 0  # It's okay if no deployment ID exists (for creation)
}

# Save Deployment ID to File

save_deployment_id() {
    local deployment_id="$1"

    echo "$deployment_id" > "$DEPLOYMENT_ID_FILE" 2>/dev/null || {
        log_warn "Failed to save deployment ID to file: $DEPLOYMENT_ID_FILE"
        return 1
    }

    log_info "Saved deployment ID to file: $DEPLOYMENT_ID_FILE"
    return 0
}

# Create GitHub Deployment

create_deployment() {
    log_info "Creating GitHub deployment for $REPO (ref: $REF, env: $ENVIRONMENT)"

    local description
    description=$(build_description)

    local payload
    payload=$(cat <<EOF
{
  "ref": "$REF",
  "environment": "$ENVIRONMENT",
  "description": "$description",
  "auto_merge": false,
  "required_contexts": []
}
EOF
)

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Accept: $ACCEPT_HEADER" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$GITHUB_API_URL/repos/$REPO/deployments" 2>&1) || {
        log_error "Failed to execute curl command"
        return 1
    }

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        local new_deployment_id
        new_deployment_id=$(echo "$body" | grep -o '"id":[[:space:]]*[0-9]*' | head -1 | cut -d':' -f2 | tr -d '[:space:]')

        if [[ -z "$new_deployment_id" ]]; then
            log_error "Failed to extract deployment ID from response"
            log_error "Response: $body"
            return 1
        fi

        log_info "Created deployment successfully (ID: $new_deployment_id)"
        save_deployment_id "$new_deployment_id"
        DEPLOYMENT_ID="$new_deployment_id"

        # Now create the initial status
        create_deployment_status "$STATE"
        return $?
    else
        log_error "Failed to create deployment (HTTP $http_code)"
        log_error "Response: $body"
        return 1
    fi
}

# Create/Update Deployment Status

create_deployment_status() {
    local status_state="$1"

    if [[ -z "$DEPLOYMENT_ID" ]]; then
        log_error "No deployment ID available. Cannot create status."
        return 1
    fi

    log_info "Updating deployment status to '$status_state' (deployment ID: $DEPLOYMENT_ID)"

    local description
    description=$(build_description)

    local payload
    payload=$(cat <<EOF
{
  "state": "$status_state",
  "description": "$description",
  "environment": "$ENVIRONMENT",
  "auto_inactive": true
}
EOF
)

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Accept: $ACCEPT_HEADER" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$GITHUB_API_URL/repos/$REPO/deployments/$DEPLOYMENT_ID/statuses" 2>&1) || {
        log_error "Failed to execute curl command"
        return 1
    }

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        log_info "Updated deployment status to '$status_state' successfully"
        return 0
    else
        log_error "Failed to update deployment status (HTTP $http_code)"
        log_error "Response: $body"
        return 1
    fi
}

# Main Logic

main() {
    log_info "GitHub Deployment Status Update Script"
    log_info "========================================"
    log_info "Using deployment ID file: $DEPLOYMENT_ID_FILE"

    # Parse arguments
    parse_arguments "$@"

    # Validate inputs (but don't exit on failure)
    if ! validate_inputs; then
        log_error "Validation failed, exiting gracefully"
        exit 0  # Exit 0 to not break pipeline
    fi

    # Auto-detect repository
    if ! detect_repo; then
        log_error "Failed to detect repository, exiting gracefully"
        exit 0
    fi

    # Auto-detect git reference
    if ! detect_ref; then
        log_error "Failed to detect git reference, exiting gracefully"
        exit 0
    fi

    # Load existing deployment ID if available
    load_deployment_id

    # Determine action based on deployment ID and state
    if [[ -z "$DEPLOYMENT_ID" && "$STATE" == "pending" ]]; then
        # Create new deployment (which also sets initial status)
        if ! create_deployment; then
            log_warn "Failed to create deployment, but continuing pipeline"
            exit 0  # Exit 0 to not break pipeline
        fi
    elif [[ -n "$DEPLOYMENT_ID" ]]; then
        # Update existing deployment status
        if ! create_deployment_status "$STATE"; then
            log_warn "Failed to update deployment status, but continuing pipeline"
            exit 0  # Exit 0 to not break pipeline
        fi
    else
        # No deployment ID and not creating new one
        log_warn "No deployment ID found and state is not 'pending'. Cannot update status."
        log_warn "To create a new deployment, use --state pending first"
        exit 0  # Exit 0 to not break pipeline
    fi

    log_info "Script completed successfully"
    exit 0
}

# Error Handling Wrapper

# Wrap main in error handler to ensure we always exit 0
if ! main "$@"; then
    log_error "Script encountered an error, but exiting with code 0 to not break pipeline"
    exit 0
fi

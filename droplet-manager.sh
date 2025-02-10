#!/usr/bin/env bash
set -eo pipefail

SCRIPT_NAME="do-droplet-manager"
TF_DIR="$(pwd)/terraform/environments/dev"
ANSIBLE_PLAYBOOK="${TF_DIR}/deploy.yml"
LOG_FILE="${TF_DIR}/droplet-manager.log"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize logging
exec > >(tee -a "${LOG_FILE}") 2>&1

# Initialize variables with defaults
# Get current branch from the activist repo
local_path=$(yq -r e '.deploy.local_path' config.yml) || {
    echo "ERROR: Failed to read local_path from config.yml"
    exit 1
}

# Add debug output
echo "DEBUG: Activist repo path: ${local_path}"
echo "DEBUG: Current directory: $(pwd)"

# Save current directory
current_dir=$(pwd)

# Explicitly cd to activist repo and get branch
BRANCH=$(cd "${local_path}" && git branch --show-current) || {
    echo "ERROR: Failed to detect current branch in activist repository at ${local_path}"
    echo "Please ensure:"
    echo "1. The path in config.yml deploy.local_path is correct (current: ${local_path})"
    echo "2. The directory exists and is a git repository"
    echo "3. You are on a valid git branch"
    exit 1
}

# Return to original directory
cd "${current_dir}"

echo "Local activist branch detected: ${BRANCH}"

# Parse branch parameter
parse_params() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch)
                echo "Branch override specified: $2"
                BRANCH="$2"  # Override detected branch if explicitly specified
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
}

show_help() {
  cat <<EOF
${SCRIPT_NAME} - DigitalOcean Droplet Management

Usage:
  $0 [COMMAND] [OPTIONS]

Commands:
  --create     Create droplet and deploy configuration
  --destroy     Destroy droplet and clean up resources
  --delete-all  Delete all droplets and domains
  --check      Validate Terraform/Ansible configurations
  --dry-run    Show execution plans without making changes
  --help       Show this help message

Options:
  --token TOKEN  Override DO_TOKEN environment variable
  --branch BRANCH  Override deployment branch (defaults to main)

Required Environment Variables:
  DO_TOKEN       DigitalOcean API token

EOF
}

validate_environment() {
  local missing=()
  [[ -z "${DO_TOKEN}" ]] && missing+=("DO_TOKEN")
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}"
    exit 1
  fi
}

check_dependencies() {
  local missing=()
  for cmd in doctl terraform yq; do
    if ! command -v $cmd &> /dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing required dependencies:"
    for dep in "${missing[@]}"; do
      case $dep in
        yq) echo "- yq: YAML processor (install with 'brew install yq' or 'sudo apt install yq')" ;;
        *) echo "- $dep" ;;
      esac
    done
    exit 1
  fi
}

validate_configs() {
  echo "Validating configurations..."
  
  # Terraform validation
  (cd "${TF_DIR}" && terraform fmt -check && terraform validate)
  
  # Ansible validation
  ansible-lint "${ANSIBLE_PLAYBOOK}"
  ansible-playbook --syntax-check "${ANSIBLE_PLAYBOOK}" > /dev/null
}

run_dry_run() {
  echo "DRY RUN: Showing execution plans"
  
  # Terraform plan
  (cd "${TF_DIR}" && terraform plan -var="do_token=${DO_TOKEN}")
  
  # Ansible check mode
  echo "Ansible dry run (check mode) - Using localhost as a placeholder"
  ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -i "localhost," \
    -c local \
    -K \
    --check \
    "${ANSIBLE_PLAYBOOK}"
}

validate_branch() {
  local branch=$1
  local repo_url
  local local_path
  local current_dir

  # Store current directory
  current_dir=$(pwd)

  # Use -r flag with echo to properly handle backslashes
  repo_url=$(yq -r e '.deploy.repository' config.yml)
  local_path=$(yq -r e '.deploy.local_path' config.yml)
  
  echo "Checking repository at ${local_path}"
  
  # Improve directory existence check
  if [[ ! -d "${local_path}" ]]; then
    echo -e "\nERROR: Local repository path does not exist: ${local_path}"
    echo "Please check deploy.local_path in config.yml"
    return 1
  fi
  
  cd "${local_path}" || {
    echo "ERROR: Failed to change to directory: ${local_path}"
    return 1
  }
  
  # Verify this is a git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: $local_path is not a git repository"
    cd "${current_dir}"
    return 1
  fi

  # Verify remote exists and matches config
  local actual_remote
  actual_remote=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "${actual_remote}" != "${repo_url}" ]]; then
    echo "ERROR: Repository mismatch"
    echo "Expected: ${repo_url}"
    echo "Found:    ${actual_remote}"
    cd "${current_dir}"
    return 1
  fi

  # Check for uncommitted changes
  if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "\nERROR: You have uncommitted changes in your working directory."
    echo "Please commit or stash your changes before deploying."
    git status --short
    cd "${current_dir}"
    return 1
  fi

  # Fetch latest from remote to ensure we have current branch information
  echo "Fetching latest from remote..."
  if ! git fetch origin --quiet; then
    echo "ERROR: Failed to fetch from remote repository"
    cd "${current_dir}"
    return 1
  fi

  # Check if branch exists on remote
  if ! git ls-remote --heads origin "${branch}" | grep -q "${branch}"; then
    echo "ERROR: Branch '${branch}' does not exist on remote repository"
    echo "Please push your branch to remote before deploying"
    cd "${current_dir}"
    return 1
  fi

  # Return to original directory
  cd "${current_dir}"
}

create_droplet() {
  echo "Creating droplet..."
  
  # Validate branch existence before proceeding
  echo "Validating branch: ${BRANCH}"
  validate_branch "${BRANCH}"
  
  echo "Proceeding with deployment using branch: ${BRANCH}"
  cd "${TF_DIR}"
  rm -rf .terraform* terraform.tfstate*
  terraform init
  terraform apply -auto-approve \
    -var="do_token=${DO_TOKEN}" \
    -var="config_path=${PROJECT_ROOT}/config.yml" \
    -var="branch=${BRANCH}"
  
  # Get droplet IP through Terraform and verify it
  DROPLET_IP=$(terraform output -raw droplet_ip)
  if [[ -z "$DROPLET_IP" ]]; then
    echo "Error: Failed to get droplet IP from terraform output"
    exit 1
  fi
  export DROPLET_IP
  echo "Droplet IP: $DROPLET_IP"

  # Wait for SSH availability using ssh instead of nc
  echo -n "Waiting for SSH readiness..."
  for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$DROPLET_IP" 'exit' 2>/dev/null; then
      echo " OK"
      break
    fi
    sleep 2
    echo -n "."
  done

  # Run Ansible deployment
  echo "Starting Ansible deployment..."
  if [ -f "${PROJECT_ROOT}/ansible/run-ansible.sh" ]; then
    chmod +x "${PROJECT_ROOT}/ansible/run-ansible.sh"
    ANSIBLE_TEMPLATES_PATH="${PROJECT_ROOT}/ansible/templates" \
    BRANCH="${BRANCH}" \
    "${PROJECT_ROOT}/ansible/run-ansible.sh" "$DROPLET_IP"
  else
    echo "Error: run-ansible.sh not found in ${PROJECT_ROOT}/ansible/"
    exit 1
  fi

  # Only proceed with tunnel setup if Ansible was successful
  if [ $? -eq 0 ]; then
    # Verify the deployment
    echo "Verifying deployment..."
    if ! check_and_start_tunnel "$DROPLET_IP"; then
      echo "Deployment verification failed"
      exit 1
    fi

    # Ensure secure config directory exists
    CONFIG_DIR="${HOME}/.config"
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Update IP in config file
    echo "DROPLET_IP=$DROPLET_IP" > "$CONFIG_DIR/ssh-tunnel.env"
    chmod 600 "$CONFIG_DIR/ssh-tunnel.env"

    # Start dev-sync automatically
    echo "Starting development file sync..."
    if command -v dev-sync &> /dev/null; then
      dev-sync start &
      echo "Development sync started in background"
    else
      echo "Warning: dev-sync command not found. File syncing not enabled."
    fi

    echo "Deployment complete! SSH tunnel and file sync are running..."
  else
    echo "Ansible deployment failed. Check the logs for details."
    exit 1
  fi
}

check_and_start_tunnel() {
  local droplet_ip=$1
  echo "Checking remote ports and starting tunnel..."

  echo "Using droplet IP: $droplet_ip"

  # Initial wait for services to start
  echo "Waiting for services to start..."
  sleep 30

  # Check port 3000 with better progress indication
  echo -n "Checking port 3000: "
  timeout 60 bash -c "until nc -z -w5 $droplet_ip 3000 2>/dev/null; do echo -n '.'; sleep 5; done" || {
    echo -e "\nPort 3000 not accessible after 60 seconds"
    return 1
  }
  echo " OK"

  # Check port 8000 with better progress indication
  echo -n "Checking port 8000: "
  timeout 60 bash -c "until nc -z -w5 $droplet_ip 8000 2>/dev/null; do echo -n '.'; sleep 5; done" || {
    echo -e "\nPort 8000 not accessible after 60 seconds"
    return 1
  }
  echo " OK"

  echo "Both ports are accessible. Starting tunnel..."
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  echo "Total deployment time: $((DURATION/60))m:$((DURATION%60))s"
  "${PROJECT_ROOT}/ssh-tunnel.sh" start

  # Kill any existing tunnels more thoroughly
  pkill -f "autossh.*:3000" || true
  pkill -f "ssh.*:3000" || true
  pkill -f "autossh.*:8000" || true
  pkill -f "ssh.*:8000" || true
  sleep 5

  # Start new tunnel with additional SSH options
  autossh -M 0 -N \
    -o "ServerAliveInterval=30" \
    -o "ServerAliveCountMax=3" \
    -o "ExitOnForwardFailure=yes" \
    -L localhost:3000:0.0.0.0:3000 \
    -L localhost:8000:0.0.0.0:8000 \
    root@"$droplet_ip"

  # More thorough tunnel verification
  echo "Verifying tunnel..."
  for i in {1..12}; do
    if nc -z localhost 3000 && nc -z localhost 8000; then
      echo "Tunnel verified - both ports accessible locally"
      return 0
    fi
    echo -n "."
    sleep 5
  done

  echo "Failed to verify tunnel after 60 seconds"
  return 1
}

destroy_droplet() {
  echo "Running terraform destroy..."
  cd "${TF_DIR}"
  terraform init -reconfigure
  terraform destroy -auto-approve -var="do_token=${DO_TOKEN}"
}

delete_all() {
  echo "Initializing doctl authentication..."
  doctl auth init -t "$DO_TOKEN"
  
  echo "Listing all droplets before cleanup..."
  doctl compute droplet list --format "ID,Name,Status,Region"
  
  echo "Deleting ALL droplets..."
  doctl compute droplet list --format ID --no-header | while read -r id; do
    if [ -n "$id" ]; then
      echo "Deleting droplet $id..."
      doctl compute droplet delete "$id" --force
    fi
  done
}

main() {
    check_dependencies
    
    # Parse parameters first
    parse_params "$@"
    
    case "$1" in
        --create)
            validate_environment
            START_TIME=$(date +%s)
            echo "Using branch: ${BRANCH}"
            create_droplet
            ;;
        --destroy)
            validate_environment
            destroy_droplet
            ;;
        --delete-all)
            delete_all
            ;;
        --check)
            validate_configs
            ;;
        --dry-run)
            validate_environment
            validate_configs
            run_dry_run
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "Invalid command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Handle token override
if [[ "$1" == "--token" ]]; then
  export DO_TOKEN="$2"
  shift 2
fi

# Set from environment if not provided
export DO_TOKEN="${DO_TOKEN:-}"
export TF_VAR_do_token="$DO_TOKEN"

# Add at the top after shebang and set
cleanup() {
    echo -e "\nCleaning up..."
    pkill -f "autossh.*:3000" || true
    pkill -f "ssh.*:3000" || true
    
    echo "Running delete_all as part of cleanup..."
    delete_all
    
    echo "Cleanup complete"
    exit 1
}

# Set up trap
trap cleanup SIGINT SIGTERM

# Execute main function
main "$@"

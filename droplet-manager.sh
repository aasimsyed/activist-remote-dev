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
BRANCH="main"

# Parse branch parameter
parse_params() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --branch)
                BRANCH="$2"
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
  repo_url=$(yq e '.deploy.repository' config.yml)
  echo "Validating branch: $branch in repository $repo_url"
  
  # Check if branch exists
  if ! git ls-remote --exit-code --heads "$repo_url" "refs/heads/$branch" >/dev/null 2>&1; then
    echo -e "\nERROR: Branch '$branch' does not exist in repository $repo_url"
    echo -e "\nAvailable branches:"
    # Fetch and format all remote branches
    git ls-remote --heads "$repo_url" | cut -f2 | sed -e 's|refs/heads/||' | while read -r available_branch; do
      echo "  - $available_branch"
    done
    exit 1
  fi
}

# Function to ensure SSH key is synchronized with DigitalOcean
sync_ssh_key() {
  echo "Synchronizing SSH key with DigitalOcean..."
  
  # Get local public key
  LOCAL_SSH_KEY="$HOME/.ssh/id_rsa.pub"
  if [[ ! -f "$LOCAL_SSH_KEY" ]]; then
    echo "Error: Local SSH public key not found at $LOCAL_SSH_KEY"
    exit 1
  fi
  
  # Get local key fingerprint
  LOCAL_FINGERPRINT=$(ssh-keygen -lf "$LOCAL_SSH_KEY" | awk '{print $2}')
  echo "Local key fingerprint: $LOCAL_FINGERPRINT"
  
  # Check if DigitalOcean key exists and matches
  SSH_KEY_NAME="DigitalOcean"
  EXISTING_KEY=$(doctl compute ssh-key list --format ID,Name,FingerPrint --no-header | grep "$SSH_KEY_NAME" || true)
  
  if [[ -n "$EXISTING_KEY" ]]; then
    EXISTING_FINGERPRINT=$(echo "$EXISTING_KEY" | awk '{print $3}')
    EXISTING_ID=$(echo "$EXISTING_KEY" | awk '{print $1}')
    
    # Convert SHA256 to MD5 format for comparison if needed
    if [[ "$LOCAL_FINGERPRINT" == SHA256:* ]]; then
      # DigitalOcean shows MD5, convert local SHA256 to MD5 for comparison
      LOCAL_MD5=$(ssh-keygen -E md5 -lf "$LOCAL_SSH_KEY" | awk '{print $2}' | sed 's/MD5://')
    else
      LOCAL_MD5="$LOCAL_FINGERPRINT"
    fi
    
    if [[ "$EXISTING_FINGERPRINT" == "$LOCAL_MD5" ]]; then
      echo "SSH key already matches. Using existing key ID: $EXISTING_ID"
      return 0
    else
      echo "SSH key fingerprint mismatch. Updating DigitalOcean key..."
      echo "  Existing: $EXISTING_FINGERPRINT"
      echo "  Local:    $LOCAL_MD5"
      
      # Delete old key
      doctl compute ssh-key delete "$EXISTING_ID" --force
    fi
  fi
  
  # Create/recreate the SSH key
  echo "Adding local SSH key to DigitalOcean..."
  doctl compute ssh-key create "$SSH_KEY_NAME" --public-key "$(cat "$LOCAL_SSH_KEY")"
  
  echo "SSH key synchronized successfully!"
}

create_droplet() {
  echo "Creating droplet..."
  
  # Ensure SSH key is synchronized before creating droplet
  sync_ssh_key
  
  # Note: Using rsync from local directory, no branch validation needed
  
  cd "${TF_DIR}"
  rm -rf .terraform* terraform.tfstate*
  terraform init
  terraform apply -auto-approve \
    -var="do_token=${DO_TOKEN}" \
    -var="config_path=${PROJECT_ROOT}/config.yml"
  
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
    CONFIG_DIR="/Users/aasim/.config"
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Update IP in config file
    echo "DROPLET_IP=$DROPLET_IP" > "$CONFIG_DIR/ssh-tunnel.env"
    chmod 600 "$CONFIG_DIR/ssh-tunnel.env"

    # Set up real-time code synchronization
    setup_code_sync "$DROPLET_IP"

    echo "Deployment complete! Starting SSH tunnel..."
  else
    echo "Ansible deployment failed. Check the logs for details."
    exit 1
  fi
}

# Function for real-time code synchronization
setup_code_sync() {
  local droplet_ip=$1
  echo "Setting up real-time code synchronization..."
  
  # Parse local and remote directory paths from config.yml
  LOCAL_DIR=$(yq e '.deploy.local_path' "${PROJECT_ROOT}/config.yml" | sed 's/^~/'"$HOME"'/')
  if [[ -z "$LOCAL_DIR" || "$LOCAL_DIR" == "null" ]]; then
    LOCAL_DIR="${PROJECT_ROOT}"
  fi
  
  REMOTE_DIR=$(yq e '.paths.project_dir' "${PROJECT_ROOT}/config.yml" | sed 's/^~/\/root/')
  if [[ -z "$REMOTE_DIR" || "$REMOTE_DIR" == "null" ]]; then
    REMOTE_DIR="/root/activist"
  fi
  
  # Get SSH key path from config
  SSH_KEY_PATH=$(yq e '.tunnel.ssh.key_path' "${PROJECT_ROOT}/config.yml" | sed 's/^~/'"$HOME"'/')
  if [[ -z "$SSH_KEY_PATH" || "$SSH_KEY_PATH" == "null" ]]; then
    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
  fi
  
  # Create sync script
  SYNC_SCRIPT="${PROJECT_ROOT}/code-sync.sh"
  cat > "$SYNC_SCRIPT" <<EOL
#!/bin/bash
# Auto-generated code sync script
set -e

# Configuration
LOCAL_DIR="${LOCAL_DIR}"
REMOTE_USER="root"
REMOTE_HOST="${droplet_ip}"
REMOTE_DIR="${REMOTE_DIR}"
WATCH_DIRS=("frontend" "backend" "utils")
LOG_FILE="${PROJECT_ROOT}/code-sync.log"
EXCLUDE_PATTERNS=(".git" "*.log" ".terraform" "*.tfstate" "node_modules")
SSH_KEY_PATH="${SSH_KEY_PATH}"
PID_FILE="${PROJECT_ROOT}/.code-sync.pid"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if already running
if [ -f "\$PID_FILE" ] && ps -p \$(cat "\$PID_FILE") > /dev/null; then
    echo -e "\${YELLOW}Code sync is already running with PID \$(cat "\$PID_FILE").${NC}"
    echo "To stop it, run: \$0 stop"
    exit 0
fi

# Check dependencies
if ! command -v fswatch &> /dev/null; then
    echo -e "\${RED}Error: fswatch is not installed. Install with:${NC}"
    echo "  brew install fswatch"
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    echo -e "\${RED}Error: rsync is not installed. Install with:${NC}"
    echo "  brew install rsync"
    exit 1
fi

# Build exclude pattern
EXCLUDE_ARGS=""
for pattern in "\${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS="\$EXCLUDE_ARGS --exclude='\$pattern'"
done

# Function to sync files to remote
sync_to_remote() {
    local changed_file="\$1"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - Syncing: \$changed_file" | tee -a "\$LOG_FILE"

    # Create the directory structure on the remote if it doesn't exist
    local dir_path=\$(dirname "\$changed_file")
    ssh -i "\$SSH_KEY_PATH" -o StrictHostKeyChecking=no "\$REMOTE_USER@\$REMOTE_HOST" "mkdir -p \$REMOTE_DIR/\$dir_path"

    # Use rsync to copy the file
    eval rsync -azP --delete \$EXCLUDE_ARGS -e \"ssh -i \$SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"\$LOCAL_DIR/\$changed_file\" \"\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\$dir_path/\"

    echo -e "\${GREEN}Sync completed: \$changed_file\${NC}" | tee -a "\$LOG_FILE"
}

# Function to perform initial full sync
initial_sync() {
    echo -e "\${YELLOW}Performing initial full sync...${NC}" | tee -a "\$LOG_FILE"
    
    # Ensure important config files are synced even if they might be excluded
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - Syncing critical config files..." | tee -a "\$LOG_FILE"
    
    # Sync .yarnrc.yml specifically to ensure correct Yarn configuration
    if [ -f "\$LOCAL_DIR/frontend/.yarnrc.yml" ]; then
        rsync -azP -e \"ssh -i \$SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"\$LOCAL_DIR/frontend/.yarnrc.yml\" \"\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/frontend/\" || echo \"Warning: Failed to sync .yarnrc.yml\"
    fi
    
    # Sync environment files
    for env_file in .env .env.dev .env.dev.local .env.local; do
        if [ -f "\$LOCAL_DIR/\$env_file" ]; then
            rsync -azP -e \"ssh -i \$SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"\$LOCAL_DIR/\$env_file\" \"\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\" || echo \"Warning: Failed to sync \$env_file\"
        fi
    done
    
    # Perform main sync
    eval rsync -azP --delete \$EXCLUDE_ARGS -e \"ssh -i \$SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"\$LOCAL_DIR/\" \"\$REMOTE_USER@\$REMOTE_HOST:\$REMOTE_DIR/\"
    
    echo -e "\${GREEN}Initial sync completed${NC}" | tee -a "\$LOG_FILE"
}

# Function to handle signals
cleanup() {
    echo -e "\n\${YELLOW}Stopping code sync service...${NC}"
    if [ -f "\$PID_FILE" ]; then
        rm "\$PID_FILE"
    fi
    exit 0
}

# Function to stop the sync process
stop_sync() {
    if [ ! -f "\$PID_FILE" ]; then
        echo -e "\${YELLOW}No code sync process found.${NC}"
        return 0
    fi
    
    local pid=\$(cat "\$PID_FILE")
    if ps -p "\$pid" > /dev/null; then
        echo -e "\${YELLOW}Stopping code sync process (PID: \$pid)...${NC}"
        kill "\$pid"
        rm "\$PID_FILE"
        echo -e "\${GREEN}Code sync stopped.${NC}"
    else
        echo -e "\${YELLOW}Code sync process not running. Cleaning up.${NC}"
        rm "\$PID_FILE"
    fi
}

# Handle stop command
if [ "\$1" = "stop" ]; then
    stop_sync
    exit 0
fi

# Trap signals
trap cleanup SIGINT SIGTERM

# Display config
echo -e "\${GREEN}Code Sync Service${NC}"
echo -e "\${YELLOW}Configuration:${NC}"
echo "  Local directory: \$LOCAL_DIR"
echo "  Remote server: \$REMOTE_USER@\$REMOTE_HOST"
echo "  Remote directory: \$REMOTE_DIR"
echo "  SSH key: \$SSH_KEY_PATH"
echo "  Watching directories:"
for dir in "\${WATCH_DIRS[@]}"; do
    echo "    - \$dir"
done

# Handle interactive/automatic mode
if [ "\$1" = "interactive" ]; then
    # Interactive mode with prompt
    read -p "Perform initial full sync? (y/n): " confirm
    if [[ \$confirm == [yY] || \$confirm == [yY][eE][sS] ]]; then
        initial_sync
    fi
else
    # Non-interactive mode, always do initial sync
    initial_sync
fi

# Start watching for changes
echo -e "\${GREEN}Starting watch service. Process running in background.${NC}"
echo "Logs will be saved to \$LOG_FILE"
echo "To stop the service run: \$0 stop"

# Save PID to file for management
echo "\$\$" > "\$PID_FILE"

# Use fswatch to detect changes and trigger sync
watch_paths=""
for dir in "\${WATCH_DIRS[@]}"; do
    if [ -d "\$LOCAL_DIR/\$dir" ]; then
        watch_paths="\$watch_paths \$LOCAL_DIR/\$dir"
    fi
done

fswatch -0 -r \$watch_paths | while read -d "" event; do
    # Get the relative path
    rel_path=\${event#\$LOCAL_DIR/}
    
    # Skip excluded patterns
    skip=false
    for pattern in "\${EXCLUDE_PATTERNS[@]}"; do
        if [[ "\$rel_path" == *\$pattern* ]]; then
            skip=true
            break
        fi
    done
    
    if [ "\$skip" = true ]; then
        continue
    fi
    
    echo "Change detected: \$rel_path"
    sync_to_remote "\$rel_path"
done
EOL

  # Make the script executable
  chmod +x "$SYNC_SCRIPT"
  
  echo -e "\nStarting real-time code synchronization..."
  
  # Start the code sync in the background
  nohup "$SYNC_SCRIPT" > /dev/null 2>&1 &
  
  echo -e "Code sync service started automatically in the background."
  echo -e "Your code changes will automatically sync to the remote droplet at ${droplet_ip}"
  echo -e "To stop the service run: ${SYNC_SCRIPT} stop"
  echo -e "To view logs: cat ${PROJECT_ROOT}/code-sync.log"
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
            echo "Syncing local code: ${PROJECT_ROOT}"
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

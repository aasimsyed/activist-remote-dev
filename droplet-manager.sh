#!/usr/bin/env bash
set -eo pipefail

SCRIPT_NAME="do-droplet-manager"
TF_DIR="$(pwd)"
ANSIBLE_PLAYBOOK="${TF_DIR}/deploy.yml"
LOG_FILE="${TF_DIR}/droplet-manager.log"

# Initialize logging
exec > >(tee -a "${LOG_FILE}") 2>&1

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
  local deps=("terraform" "ansible-playbook" "jq" "doctl")
  local missing=()

  for dep in "${deps[@]}"; do
    if ! command -v "${dep}" &> /dev/null; then
      missing+=("${dep}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required dependencies: ${missing[*]}"
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

update_dns() {
  DOMAIN="dev-asyed.com"
  SUBDOMAIN="activist"
  NEW_IP=$1

  echo "Updating DNS A record for $SUBDOMAIN.$DOMAIN to point to $NEW_IP..."
  
  # Get existing record ID
  RECORD_ID=$(doctl compute domain records list $DOMAIN \
    --format ID,Type,Name --no-header | grep "A $SUBDOMAIN" | awk '{print $1}')
  
  if [ -n "$RECORD_ID" ]; then
    # Update existing record
    doctl compute domain records update $DOMAIN $RECORD_ID \
      --record-type A \
      --record-name $SUBDOMAIN \
      --record-data $NEW_IP
    echo "Updated existing A record"
  else
    # Create new record
    doctl compute domain records create $DOMAIN \
      --record-type A \
      --record-name $SUBDOMAIN \
      --record-data $NEW_IP
    echo "Created new A record"
  fi
}

create_droplet() {
  echo "Creating droplet..."
  rm -rf .terraform* terraform.tfstate*
  terraform init
  terraform apply -auto-approve
  
  # Get droplet IP through Terraform (more reliable)
  DROPLET_IP=$(terraform output -raw droplet_ip)
  
  # Update DNS
  update_dns "$DROPLET_IP"

  # Wait for SSH to become available
  echo -n "Waiting for SSH readiness..."
  for i in {1..30}; do
    if nc -z -w5 $DROPLET_IP 22; then
      echo " OK"
      break
    fi
    sleep 2
    echo -n "."
  done

  # Write environment file with bash syntax
  echo "export DROPLET_IP=$DROPLET_IP" > ~/.config/ssh-tunnel.env

  # Force bash-compatible service reload
  launchctl bootout gui/501/local.tunnel
  /bin/bash -c "launchctl bootstrap gui/501 ~/Library/LaunchAgents/local.tunnel.plist"

  # Bash-specific process check
  if ! /bin/bash -c "pgrep -f 'ssh.*-L 3000' >/dev/null"; then
    echo "Error: Tunnel process not found"
    exit 1
  fi
}

destroy_droplet() {
  if [ -z "$DO_TOKEN" ]; then
    echo "Error: DO_TOKEN is not set"
    exit 1
  fi

  echo "Debug: Current directory is $(pwd)"
  echo "Debug: TF_DIR is ${TF_DIR}"
  
  echo "Terminating SSH connections..."
  pkill -f "ssh -L.*root@.*" || true

  echo "Initializing doctl authentication..."
  doctl auth init -t "$DO_TOKEN"

  echo "Listing all droplets before cleanup..."
  doctl compute droplet list --format "ID,Name,Status,Region"
  
  echo "Cleaning up all droplets..."
  doctl compute droplet list --format ID --no-header | while read -r id; do
    if [ -n "$id" ]; then
      echo "Deleting droplet $id..."
      doctl compute droplet delete "$id" --force
    fi
  done

  echo "Verifying droplets are gone..."
  doctl compute droplet list --format "ID,Name,Status,Region"

  echo "Running terraform destroy..."
  terraform init -reconfigure
  (cd "${TF_DIR}" && terraform destroy -auto-approve)
  rm -f /Users/aasim/.config/ssh-tunnel.env
  launchctl stop local.tunnel
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
  
  echo "Listing all domains..."
  doctl compute domain list --format "Domain,TTL"
  
  echo "Deleting ALL domains..."
  doctl compute domain list --format Domain --no-header | while read -r domain; do
    if [ -n "$domain" ]; then
      echo "Deleting domain $domain..."
      doctl compute domain delete "$domain" --force
    fi
  done
}

main() {
  check_dependencies
  
  case "$1" in
    --create)
      validate_environment
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

# Execute main function
main "$@"

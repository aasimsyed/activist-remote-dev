#!/bin/bash
# Get the droplet IP (either from argument or doctl)
DROPLET_IP=${1:-$(doctl compute droplet list --format PublicIPv4 --no-header)}
export DROPLET_IP

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# IP validation function
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi
    # Validate each octet
    for octet in ${ip//\./ }; do
        if (( octet > 255 )); then
            return 1
        fi
    done
    return 0
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Ansible provisioning for ${CYAN}$DROPLET_IP${NC}"
echo -e "${BLUE}--------------------------------------------${NC}"
echo -e "${PURPLE}$(date)${NC}"

# Verify the variable
echo -e "${GREEN}Using DROPLET_IP=$DROPLET_IP${NC}"

# Check for existing droplets
if ! doctl compute droplet list --format ID | grep -qE '[0-9]+'; then
    echo -e "${RED}No droplets found. Create one first with:${NC}"
    echo -e "${YELLOW}doctl compute droplet create <name> --region nyc3 --image ubuntu-22-04-x64 --size s-1vcpu-1gb --ssh-keys <your-key-fingerprint>${NC}"
    exit 1
fi

# Add timeout for SSH check
echo -e "${YELLOW}Waiting for SSH to become available...${NC}"
TIMEOUT=180  # 3 minutes
START_TIME=$(date +%s)

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo -e "${RED}Timeout waiting for SSH after ${TIMEOUT} seconds${NC}"
        exit 1
    fi

    if [ -z "$DROPLET_IP" ]; then
        echo -e "${RED}No droplet IP provided${NC}"
        exit 1
    fi

    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$DROPLET_IP 'exit' 2>/dev/null; then
        echo -e "${GREEN}SSH connection established!${NC}"
        break
    fi
    
    echo -e "${YELLOW}.${NC}"
    sleep 5
done

# Generate dynamic inventory with proper escaping
"${SCRIPT_DIR}/inventory/get_droplet.sh" "$DROPLET_IP" > "${SCRIPT_DIR}/inventory/hosts.json"

# Update playbook path
PLAYBOOK_PATH="${SCRIPT_DIR}/playbooks/deploy.yml"

max_retries=5
delay=60
for i in $(seq 1 $max_retries); do
  echo -e "\n${BLUE}Attempt ${CYAN}$i/$max_retries${BLUE} - ${PURPLE}$(date)${NC}"
  if [ -f "$PLAYBOOK_PATH" ]; then
    ANSIBLE_FORCE_COLOR=true \
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible-playbook \
      -i "${SCRIPT_DIR}/inventory/hosts.json" \
      -e "template_dir=${PROJECT_ROOT}/ansible/templates" \
      -e "ansible_python_interpreter=/usr/bin/python3" \
      "$PLAYBOOK_PATH" && \
      echo -e "${GREEN}Deployment successful!${NC}" && exit 0
  else
    echo -e "${RED}Playbook not found at: $PLAYBOOK_PATH${NC}"
    exit 1
  fi
  
  echo -e "${RED}Attempt $i failed.${NC} ${YELLOW}Retrying in $delay seconds...${NC}"
  sleep $delay
done

echo -e "${RED}All attempts failed. Exiting.${NC}"
exit 1

# Run Ansible with full verbosity
ANSIBLE_DEBUG=1 \
ANSIBLE_LOG_PATH="ansible-deploy.log" \
ANSIBLE_STDOUT_CALLBACK=debug \
PYTHONUNBUFFERED=1 \
ansible-playbook \
    -vvvv \
    -i "${SCRIPT_DIR}/inventory/hosts.json" \
    "$PLAYBOOK_PATH" 2>&1 | tee -a deploy.log


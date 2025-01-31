#!/bin/bash
DROPLET_IP=$1

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

# Add inventory file dynamically
echo "[all]" > inventory.ini
echo "$DROPLET_IP ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_rsa" >> inventory.ini

max_retries=5
delay=60
for i in $(seq 1 $max_retries); do
  echo -e "\n${BLUE}Attempt ${CYAN}$i/$max_retries${BLUE} - ${PURPLE}$(date)${NC}"
  ANSIBLE_FORCE_COLOR=true \
  ANSIBLE_HOST_KEY_CHECKING=False \
  ansible-playbook -i "$DROPLET_IP," deploy.yml && \
    echo -e "${GREEN}Deployment successful!${NC}" && exit 0
  
  echo -e "${RED}Attempt $i failed.${NC} ${YELLOW}Retrying in $delay seconds...${NC}"
  sleep $delay
done

echo -e "${RED}All attempts failed. Exiting.${NC}"
exit 1


#!/bin/bash
# code-sync.sh - Real-time code synchronization to remote droplet
set -e

# Configuration
CONFIG_FILE="$(pwd)/config.yml"
# Get local directory from config.yml deploy.local_path
LOCAL_DIR=$(yq e '.deploy.local_path' "$CONFIG_FILE" 2>/dev/null || echo "$(pwd)")
# Expand ~ to home directory if present
LOCAL_DIR="${LOCAL_DIR/#\~/$HOME}"
REMOTE_USER="root"
WATCH_DIRS=("frontend" "backend" "utils")
LOG_FILE="code-sync.log"
EXCLUDE_PATTERNS=(".git" "*.log" ".terraform" "*.tfstate" "node_modules" ".yarn" "*.pnp.*" ".pnp.loader.mjs" ".pnp.cjs" ".pnp.js" "yarn-error.log")

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check dependencies
if ! command -v fswatch &> /dev/null; then
    echo -e "${RED}Error: fswatch is not installed. Install with:${NC}"
    echo "  brew install fswatch"
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    echo -e "${RED}Error: rsync is not installed. Install with:${NC}"
    echo "  brew install rsync"
    exit 1
fi

# Parse config.yml for droplet IP
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: config.yml not found. Please create it first.${NC}"
    exit 1
fi

# Get droplet IP from terraform output or config file
DROPLET_IP=$(cd terraform/environments/dev && terraform output -raw droplet_ip 2>/dev/null || grep -A5 "digitalocean:" "$CONFIG_FILE" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | head -1)

if [ -z "$DROPLET_IP" ]; then
    echo -e "${RED}Error: Could not determine droplet IP.${NC}"
    exit 1
fi

# Get SSH key path from config
SSH_KEY_PATH=$(grep -A10 "tunnel:" "$CONFIG_FILE" | grep "key_path:" | cut -d':' -f2 | tr -d ' ' | sed 's/^~/\/Users\/'$(whoami)'/')

if [ -z "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="$HOME/.ssh/id_rsa"
fi

# Get project directory from config
REMOTE_DIR=$(grep -A10 "paths:" "$CONFIG_FILE" | grep "project_dir:" | cut -d':' -f2 | tr -d ' ' | sed 's/^~/\/root/')

if [ -z "$REMOTE_DIR" ]; then
    REMOTE_DIR="/root/activist"
fi

# Build exclude pattern
EXCLUDE_ARGS=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude='$pattern'"
done

# Function to sync files to remote
sync_to_remote() {
    local changed_file="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Syncing: $changed_file" | tee -a "$LOG_FILE"

    # Create the directory structure on the remote if it doesn't exist
    local dir_path=$(dirname "$changed_file")
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$DROPLET_IP" "mkdir -p $REMOTE_DIR/$dir_path"

    # Use rsync to copy the file
    eval rsync -azP --delete $EXCLUDE_ARGS -e \"ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"$LOCAL_DIR/$changed_file\" \"$REMOTE_USER@$DROPLET_IP:$REMOTE_DIR/$dir_path/\"

    echo -e "${GREEN}Sync completed: $changed_file${NC}" | tee -a "$LOG_FILE"
}

# Function to perform initial full sync
initial_sync() {
    echo -e "${YELLOW}Performing initial full sync...${NC}" | tee -a "$LOG_FILE"
    
    # Ensure important config files are synced even if they might be excluded
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Syncing critical config files..." | tee -a "$LOG_FILE"
    
    # Sync .yarnrc.yml specifically to ensure correct Yarn configuration
    if [ -f "$LOCAL_DIR/frontend/.yarnrc.yml" ]; then
        rsync -azP -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_DIR/frontend/.yarnrc.yml" "$REMOTE_USER@$DROPLET_IP:$REMOTE_DIR/frontend/" || echo "Warning: Failed to sync .yarnrc.yml"
    fi
    
    # Sync package.json files to ensure correct package manager configuration
    if [ -f "$LOCAL_DIR/frontend/package.json" ]; then
        rsync -azP -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_DIR/frontend/package.json" "$REMOTE_USER@$DROPLET_IP:$REMOTE_DIR/frontend/" || echo "Warning: Failed to sync frontend package.json"
    fi
    
    # Clean up any potential PnP files that might cause conflicts
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$DROPLET_IP" "cd $REMOTE_DIR && find . -name '.pnp.*' -delete 2>/dev/null || true"
    
    # Sync environment files
    for env_file in .env .env.dev .env.dev.local .env.local; do
        if [ -f "$LOCAL_DIR/$env_file" ]; then
            rsync -azP -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" "$LOCAL_DIR/$env_file" "$REMOTE_USER@$DROPLET_IP:$REMOTE_DIR/" || echo "Warning: Failed to sync $env_file"
        fi
    done
    
    # Perform main sync
    eval rsync -azP --delete $EXCLUDE_ARGS -e \"ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no\" \"$LOCAL_DIR/\" \"$REMOTE_USER@$DROPLET_IP:$REMOTE_DIR/\"
    
    echo -e "${GREEN}Initial sync completed${NC}" | tee -a "$LOG_FILE"
}

# Function to handle signals
cleanup() {
    echo -e "\n${YELLOW}Stopping code sync service...${NC}"
    exit 0
}

# Trap signals
trap cleanup SIGINT SIGTERM

# Display config
echo -e "${GREEN}Code Sync Service${NC}"
echo -e "${YELLOW}Configuration:${NC}"
echo "  Local directory: $LOCAL_DIR"
echo "  Remote server: $REMOTE_USER@$DROPLET_IP"
echo "  Remote directory: $REMOTE_DIR"
echo "  SSH key: $SSH_KEY_PATH"
echo "  Watching directories:"
for dir in "${WATCH_DIRS[@]}"; do
    echo "    - $dir"
done

# Confirm with user
read -p "Perform initial full sync? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    initial_sync
fi

# Start watching for changes
echo -e "${GREEN}Starting watch service. Press Ctrl+C to stop.${NC}"
echo "Logs will be saved to $LOG_FILE"

# Use fswatch to detect changes and trigger sync
watch_paths=""
for dir in "${WATCH_DIRS[@]}"; do
    watch_paths="$watch_paths $LOCAL_DIR/$dir"
done

fswatch -0 -r $watch_paths | while read -d "" event; do
    # Get the relative path
    rel_path=${event#$LOCAL_DIR/}
    
    # Skip excluded patterns
    skip=false
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$rel_path" == *$pattern* ]]; then
            skip=true
            break
        fi
    done
    
    if [ "$skip" = true ]; then
        continue
    fi
    
    echo "Change detected: $rel_path"
    sync_to_remote "$rel_path"
done 
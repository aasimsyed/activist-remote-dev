#!/bin/bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Setting up development environment...${NC}"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}This script currently only supports macOS.${NC}"
    echo "For other operating systems, please install dependencies manually:"
    echo "- doctl"
    echo "- terraform"
    echo "- ansible"
    echo "- yq"
    echo "- mutagen"
    echo "- autossh"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install required packages
echo -e "${BLUE}Installing required packages...${NC}"
PACKAGES=(
    "doctl"
    "terraform"
    "ansible"
    "yq"
    "mutagen-io/mutagen/mutagen"
    "autossh"
)

for package in "${PACKAGES[@]}"; do
    if ! brew list "$package" &>/dev/null; then
        echo -e "${YELLOW}Installing $package...${NC}"
        brew install "$package"
    else
        echo -e "${GREEN}$package already installed${NC}"
    fi
done

# Install required Ansible collections
echo -e "${BLUE}Installing Ansible collections...${NC}"
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker

# Check for SSH key
if [[ ! -f ~/.ssh/id_rsa ]]; then
    echo -e "${YELLOW}SSH key not found. Generating new SSH key...${NC}"
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    echo -e "${GREEN}SSH key generated${NC}"
    echo -e "${YELLOW}Important: Add this SSH key to your DigitalOcean account:${NC}"
    echo -e "doctl compute ssh-key import activist --public-key-file ~/.ssh/id_rsa.pub"
fi

# Check for config.yml
if [[ ! -f config.yml ]]; then
    echo -e "${YELLOW}Creating config.yml from template...${NC}"
    cp config.yml.template config.yml
    echo -e "${GREEN}Created config.yml${NC}"
    echo -e "${YELLOW}Important: Edit config.yml and update the following:${NC}"
    echo "1. repository: Your Git repository URL"
    echo "2. local_path: Your local project path"
fi

# Check for DO_TOKEN
if [[ -z "${DO_TOKEN:-}" ]]; then
    echo -e "${YELLOW}DigitalOcean API token not found${NC}"
    echo "Please set your DigitalOcean API token:"
    echo "export DO_TOKEN='your-token-here'"
    echo "Add this line to your ~/.zshrc or ~/.bash_profile"
fi

# Create required directories
echo -e "${BLUE}Creating required directories...${NC}"
mkdir -p "${HOME}/.config"
chmod 700 "${HOME}/.config"

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Edit config.yml with your settings"
echo "2. Set your DO_TOKEN environment variable"
echo "3. Add your SSH key to DigitalOcean"
echo "4. Run: ./droplet-manager.sh --create" 
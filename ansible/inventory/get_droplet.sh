#!/bin/bash
set -euo pipefail

# Retry IP lookup up to 3 times
for i in {1..3}; do
    DROPLET_IP=${1:-$(doctl compute droplet list --format PublicIPv4 --no-header | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)}
    
    if [[ "$DROPLET_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
    fi
    
    if [[ $i -lt 3 ]]; then
        echo "Retrying IP lookup... (attempt $i/3)"
        sleep 10
    else
        echo "Failed to get droplet IP after 3 attempts" >&2
        exit 1
    fi
done

# Validate IP format
if [[ ! "$DROPLET_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address format: $DROPLET_IP" >&2
    exit 1
fi

# Generate inventory JSON with explicit SSH settings
jq -n --arg ip "$DROPLET_IP" --arg home "$HOME" '{
    "all": {
        "hosts": {
            ($ip): {
                "ansible_user": "root",
                "ansible_ssh_private_key_file": "\($home)/.ssh/id_rsa",
                "ansible_python_interpreter": "/usr/bin/python3",
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=no",
                "ansible_connection": "ssh"
            }
        }
    }
}' 
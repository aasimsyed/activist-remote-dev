#!/bin/bash

get_droplet_ip() {
    # Get IPs into an array
    IPS=()
    while read -r line; do
        IPS+=("$line")
    done < <(doctl compute droplet list --format PublicIPv4 --no-header)
    
    if [[ ${#IPS[@]} -eq 0 ]]; then
        echo "Failed to get any droplet IPs" >&2
        return 1
    fi

    # If only one IP, return it directly
    if [[ ${#IPS[@]} -eq 1 ]]; then
        echo "${IPS[0]}"
        return 0
    fi

    # Multiple IPs - prompt user to choose
    PS3="Select droplet IP: "  # Custom prompt for select
    select IP in "${IPS[@]}"; do
        if [[ -n "$IP" ]]; then
            echo "$IP"
            break  # Exit the select loop once valid selection is made
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

start_tunnel() {
    # Get fresh IP without extra output
    IP=$(get_droplet_ip | tail -n 1)
    if [[ -z "$IP" ]]; then
        echo "No IP address selected"
        exit 1
    fi
    echo "Connecting to droplet at: $IP"

    # Kill any existing tunnels
    pkill -f "ssh.*:3000"
    sleep 1

    # Start new tunnel
    autossh -M 0 -N \
        -L localhost:3000:0.0.0.0:3000 \
        -L localhost:8000:0.0.0.0:8000 \
        root@"$IP"
}

stop_tunnel() {
    echo "Stopping SSH tunnel"
    pkill -f "ssh.*:3000"
    sleep 1
    
    if pgrep -f "ssh.*:3000" >/dev/null; then
        echo "Failed to stop tunnel"
        return 1
    fi
    echo "Tunnel stopped"
}

case "$1" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    restart)
        stop_tunnel && start_tunnel
        ;;
    status)
        if pgrep -f "ssh.*:3000" >/dev/null; then
            echo "Tunnel is active"
        else
            echo "Tunnel is inactive"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
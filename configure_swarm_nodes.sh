#!/bin/bash

# Script to configure Docker daemon.json on all Swarm nodes for mediaserver:5000 registry
# and set mediaserver as primary DNS with 8.8.8.8 as fallback

# List of node names (excluding mediaserver, which is local)
NODES=("cluster1" "cluster2" "cluster3" "cluster4" "slave1")

# Local node (no SSH needed)
LOCAL_NODE="mediaserver"

# Registry and DNS settings
REGISTRY="mediaserver:5000"
PRIMARY_DNS=$(host mediaserver | grep "has address" | awk '{print $4}' | head -1)
FALLBACK_DNS="8.8.8.8"

# Check if PRIMARY_DNS resolved
if [ -z "$PRIMARY_DNS" ]; then
    echo "Error: Could not resolve mediaserver DNS to an IP address"
    exit 1
fi
echo "Resolved mediaserver to $PRIMARY_DNS"

# Function to update daemon.json on a node
update_daemon_json() {
    local node=$1
    local is_local=$2

    echo "Configuring $node..."

    # Command to update daemon.json
    update_cmd="
        sudo mkdir -p /etc/docker &&
        sudo bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  \"insecure-registries\": [\"$REGISTRY\"],
  \"dns\": [\"$PRIMARY_DNS\", \"$FALLBACK_DNS\"]
}
EOF' &&
        sudo systemctl restart docker &&
        docker info --format '{{.RegistryConfig.InsecureRegistryCIDRs}}' &&
        docker info --format '{{.DNSResolverConfig.DNS}}'
    "

    if [ "$is_local" == "true" ]; then
        # Run locally on mediaserver
        if bash -c "$update_cmd"; then
            echo "$node: Successfully updated daemon.json and restarted Docker"
        else
            echo "Error: Failed to update daemon.json on $node"
            exit 1
        fi
    else
        # Run via SSH
        if ssh pi@$node "$update_cmd"; then
            echo "$node: Successfully updated daemon.json and restarted Docker"
        else
            echo "Error: Failed to update daemon.json on $node"
            exit 1
        fi
    fi
}

# Update mediaserver (local)
update_daemon_json "$LOCAL_NODE" "true"

# Update remote nodes
for node in "${NODES[@]}"; do
#    update_daemon_json "$node" "false"
done

echo "All nodes configured successfully"
echo "Run 'docker node ls' to verify node status"
echo "Run './deploy_swarm.sh' in ~/MediaCentre/vacuum to redeploy the vacuum stack"

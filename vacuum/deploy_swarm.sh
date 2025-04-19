#!/bin/bash

# Script to build, upload, and deploy Xiaomi vacuum Swarm stack

cd ~/MediaCentre/vacuum

# Check for required Docker secrets
check_and_create_secret() {
    local secret_name=$1
    local prompt_message=$2
    if ! docker secret ls | grep -q "$secret_name"; then
        echo "$prompt_message"
        read -s -p "Enter $secret_name: " secret_value
        echo
        if [ -z "$secret_value" ]; then
            echo "Error: $secret_name cannot be empty"
            exit 1
        fi
        echo -n "$secret_value" | docker secret create "$secret_name" -
        echo "Created secret: $secret_name"
    else
        echo "Secret $secret_name already exists"
    fi
}

echo "Checking Docker secrets..."
check_and_create_secret "xiaomi_username" "Xiaomi username secret not found."
check_and_create_secret "xiaomi_password" "Xiaomi password secret not found."
check_and_create_secret "verisure_username" "Verisure username secret not found."
check_and_create_secret "verisure_password" "Verisure password secret not found."

# Build vacuum image
echo "Building vacuum image..."
docker build -f vacuum/Dockerfile -t mediaserver:5000/vacuum:latest vacuum

# Build alarm_poller image
echo "Building alarm_poller image..."
docker build -f alarm/Dockerfile -t mediaserver:5000/alarm_poller:latest alarm

# Upload images to registry
echo "Pushing images to registry..."
docker push mediaserver:5000/vacuum:latest
docker push mediaserver:5000/alarm_poller:latest

# Deploy Swarm stack
echo "Deploying Swarm stack..."
docker stack deploy -c docker-compose.yml vacuum

echo "Deployment complete. Access API at https://vacuum.granbacken/list"
echo "Swagger UI at https://vacuum.granbacken/apidocs"

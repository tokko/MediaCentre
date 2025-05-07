#!/bin/bash

# Script to build, upload, and deploy Traefik, Xiaomi vacuum, GitLab, and media stacks

# Check registry connectivity
check_registry() {
    echo "Checking registry connectivity to mediaserver:5000..."
    if ! curl -s -f http://mediaserver:5000/v2/ > /dev/null; then
        echo "Error: Cannot connect to registry at mediaserver:5000"
        exit 1
    fi
    echo "Registry is accessible"
}

# Check for required Docker secrets
check_and_create_secret() {
    local secret_name=$1
    local prompt_message=$2
    if ! docker secret ls | grep -q "$secret_name"; then
        echo "$prompt_message"
        read -p "Enter $secret_name: " secret_value
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

# Deploy infra stack
echo "Deploying infra stack..."

#docker stack deploy -c infra/docker-compose.yml infra 
# Verify registry
#check_registry

# Build vacuum image
echo "Building vacuum image..."
docker build -t mediaserver:5000/vacuum:latest vacuum/vacuum

# Build alarm_poller image
echo "Building alarm_poller image..."
docker build -t mediaserver:5000/alarm_poller:latest vacuum/alarm

# Upload images to registry
echo "Pushing images to registry..."
docker push mediaserver:5000/vacuum:latest
docker push mediaserver:5000/alarm_poller:latest

# Deploy Traefik stack
echo "Deploying Ingress stack..."
#docker stack deploy -c ingress/docker-compose.yml ingress

# Deploy vacuum stack
echo "Deploying vacuum stack..."
docker stack deploy -c vacuum/docker-compose.yml vacuum

# Deploy GitLab stack
echo "Deploying GitLab stack..."
#docker stack deploy -c gitlab/docker-compose.yml gitlab

# Deploy media stack
echo "Deploying media stack..."
#docker stack deploy -c media/docker-compose.yml media

# Deploy monitoring stack
echo "Deploying monitoring stack..."
#docker stack deploy -c monitoring/docker-compose.yml monitoring

echo "Deployment complete."
echo "Traefik Dashboard: http://traefik.granbacken"
echo "Vacuum API: http://vacuum.granbacken/list"
echo "Vacuum Swagger UI: http://vacuum.granbacken/apidocs"
echo "GitLab: http://gitlab.granbacken (login: root, password: changeme123)"
echo "Sonarr: http://sonarr.granbacken"
echo "Transmission: http://transmission.granbacken"

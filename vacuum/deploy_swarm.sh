#!/bin/bash

# Script to build, upload, and deploy Xiaomi vacuum Swarm stack

cd ~/MediaCentre/vacuum

# Build Docker image
docker build --no-cache -t mediaserver:5000/vacuum:latest .

# Upload to registry
docker push mediaserver:5000/vacuum:latest

# Deploy Swarm stack
docker stack deploy -c docker-compose.yml vacuum

echo "Deployment complete. Access API at https://vacuum.granbacken/list"
echo "Swagger UI at https://vacuum.granbacken/docs"

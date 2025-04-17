#!/bin/bash

# Script to set up Xiaomi vacuum control with Docker Swarm and Cloud API

# Prompt for Xiaomi credentials
echo "Enter your Xiaomi account username (email/phone):"
read XIAOMI_USERNAME
echo "Enter your Xiaomi account password:"
read -s XIAOMI_PASSWORD
echo

# Create temporary directory for device discovery
mkdir -p /tmp/xiaomi_setup
cd /tmp/xiaomi_setup

# Create Python script to discover devices
cat > list_xiaomi_devices.py << EOL
from micloud import MiCloud
import json
import sys

def list_devices(username, password):
    try:
        cloud = MiCloud(username, password)
        cloud.login()
        devices = cloud.get_devices()
        vacuum_devices = [
            {
                "ip": device.get("localip", "unknown"),
                "device_id": device["did"],
                "model": device["model"],
                "name": device["name"]
            }
            for device in devices if "roborock.vacuum" in device["model"]
        ]
        with open("xiaomi_devices.json", "w") as f:
            json.dump(vacuum_devices, f, indent=4)
        print("Devices saved to xiaomi_devices.json:")
        for dev in vacuum_devices:
            print(f"Name: {dev['name']}, IP: {dev['ip']}, ID: {dev['device_id']}, Model: {dev['model']}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 list_xiaomi_devices.py <username> <password>")
        sys.exit(1)
    list_devices(sys.argv[1], sys.argv[2])
EOL

# Create virtual environment and install micloud
python3 -m venv venv
source venv/bin/activate
pip install micloud==0.6
python3 list_xiaomi_devices.py "$XIAOMI_USERNAME" "$XIAOMI_PASSWORD"

# Check if device discovery succeeded
if [ ! -f xiaomi_devices.json ]; then
    echo "Error: Device discovery failed. Check credentials and try again."
    exit 1
fi

# Read devices from JSON
DEVICES=$(cat xiaomi_devices.json)

# Move to project directory
cd ~/MediaCentre/vacuum
mkdir -p secrets

# Create Docker secrets
echo -n "$XIAOMI_USERNAME" | docker secret create xiaomi_username -
echo -n "$XIAOMI_PASSWORD" | docker secret create xiaomi_password -

# Create requirements.txt
cat > requirements.txt << EOL
flask==3.0.3
werkzeug==3.0.4
micloud==0.6
EOL

# Create Dockerfile
cat > Dockerfile << EOL
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOL

# Create docker-compose.yml
cat > docker-compose.yml << EOL
version: '3.8'

services:
  vacuum:
    image: mediaserver:5000/vacuum:latest
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.vacuum.rule=Host(\`vacuum.granbacken\`)"
        - "traefik.http.routers.vacuum.entrypoints=web,websecure"
        - "traefik.http.routers.vacuum.tls=true"
        - "traefik.http.services.vacuum.loadbalancer.server.port=5001"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 128m
        reservations:
          memory: 64m
      secrets:
        - xiaomi_username
        - xiaomi_password
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock

networks:
  ingress_network:
    external: true

secrets:
  xiaomi_username:
    external: true
  xiaomi_password:
    external: true
EOL

# Create app.py
cat > app.py << EOL
from flask import Flask, jsonify, request
import json
import logging
import os
from micloud import MiCloud

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)

def read_secret(secret_name):
    """Read Docker secret."""
    try:
        with open(f"/run/secrets/{secret_name}", "r") as f:
            return f.read().strip()
    except Exception as e:
        app.logger.error(f"Failed to read secret {secret_name}: {e}")
        return None

XIAOMI_USERNAME = read_secret("xiaomi_username")
XIAOMI_PASSWORD = read_secret("xiaomi_password")

def get_cloud_client():
    """Initialize Xiaomi Cloud client."""
    if not XIAOMI_USERNAME or not XIAOMI_PASSWORD:
        app.logger.error("Missing credentials")
        return None
    try:
        cloud = MiCloud(XIAOMI_USERNAME, XIAOMI_PASSWORD)
        cloud.login()
        return cloud
    except Exception as e:
        app.logger.error(f"Cloud login failed: {e}")
        return None

def discover_vacuums():
    """Discover vacuums via Xiaomi Cloud."""
    vacuums = []
    cloud = get_cloud_client()
    if not cloud:
        app.logger.error("No cloud client available")
        return vacuums
    
    try:
        devices = cloud.get_devices()
        for device in devices:
            if "roborock.vacuum" in device["model"]:
                ip = device.get("localip", "unknown")
                did = device["did"]
                model = device["model"]
                vacuums.append({
                    "ip": ip,
                    "model": model,
                    "device_id": did,
                    "device": None  # Cloud control, no local miIO device
                })
                app.logger.info(f"Found vacuum: {ip}, model: {model}, did: {did}")
    except Exception as e:
        app.logger.error(f"Failed to discover vacuums: {e}")
    
    app.logger.info(f"Discovered {len(vacuums)} devices")
    return vacuums

def control_vacuums(action):
    """Control all vacuums via Xiaomi Cloud."""
    vacuums = discover_vacuums()
    results = []
    cloud = get_cloud_client()
    if not cloud:
        return ["Cloud connection failed"]
    
    if not vacuums:
        return ["No vacuums found"]
    
    for vac in vacuums:
        did = vac["device_id"]
        try:
            if action == "start":
                cloud.execute_action(did, "app_start", [])
                status = "Started"
            elif action == "stop":
                cloud.execute_action(did, "app_stop", [])
                status = "Stopped"
            elif action == "pause":
                cloud.execute_action(did, "app_pause", [])
                status = "Paused"
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): {status}")
        except Exception as e:
            results.append(f"Vacuum {vac['ip']} ({vac['model']}): Error - {str(e)}")
    
    return results

@app.route('/list')
def list_vacuums():
    """Return JSON with info about all vacuums."""
    vacuums = discover_vacuums()
    vacuum_info = [
        {"ip": vac["ip"], "model": vac["model"], "device_id": vac["device_id"]}
        for vac in vacuums
    ]
    app.logger.info(f"Returning vacuum list: {vacuum_info}")
    return jsonify(vacuum_info)

@app.route('/start')
def start():
    """Start all Xiaomi vacuums."""
    results = control_vacuums("start")
    app.logger.info(f"Start results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/stop')
def stop():
    """Stop all Xiaomi vacuums."""
    results = control_vacuums("stop")
    app.logger.info(f"Stop results: {results}")
    return "<br>".join(results) or "No vacuums found."

@app.route('/pause')
def pause():
    """Pause all Xiaomi vacuums."""
    results = control_vacuums("pause")
    app.logger.info(f"Pause results: {results}")
    return "<br>".join(results) or "No vacuums found."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001)
EOL

# Build and deploy
docker build --no-cache -t mediaserver:5000/vacuum:latest .
docker push mediaserver:5000/vacuum:latest
docker stack deploy -c docker-compose.yml vacuum

echo "Deployment complete. Access at https://vacuum.granbacken/list"
echo "Endpoints: /list, /start, /stop, /pause"

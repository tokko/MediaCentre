#!/bin/bash

set -e

# Base directories
VACUUM_DIR="/home/pi/MediaCentre/vacuum"
INFRA_DIR="/home/pi/MediaCentre/infra"

# Create vacuum stack directory
echo "Creating vacuum stack directory..."
mkdir -p "$VACUUM_DIR"

# Write vacuum/app.py
echo "Writing vacuum/app.py..."
cat > "$VACUUM_DIR/app.py" << 'EOF'
from flask import Flask
from miio import DeviceFactory, DeviceException
import netifaces
import ipaddress
import time

app = Flask(__name__)

def get_local_network():
    """Get the local network IP range (e.g., 192.168.68.0/24)."""
    try:
        interfaces = netifaces.interfaces()
        for iface in interfaces:
            addrs = netifaces.ifaddresses(iface)
            if netifaces.AF_INET in addrs:
                for addr in addrs[netifaces.AF_INET]:
                    ip = addr['addr']
                    if ip.startswith('192.168.68'):
                        netmask = addr['netmask']
                        network = ipaddress.IPv4Network(f"{ip}/{netmask}", strict=False)
                        return network
    except Exception as e:
        app.logger.error(f"Error getting network: {e}")
    return ipaddress.IPv4Network("192.168.68.0/24")

def discover_vacuums():
    """Discover Xiaomi vacuums on the network."""
    vacuums = []
    network = get_local_network()
    app.logger.info(f"Scanning network: {network}")
    for ip in network:
        try:
            dev = DeviceFactory.create(str(ip), None)
            info = dev.info()
            if "vacuum" in info.model:
                vacuums.append(dev)
                app.logger.info(f"Found vacuum: {ip}, model: {info.model}")
        except DeviceException:
            continue
    return vacuums

def control_vacuums(action):
    """Start or stop all discovered vacuums."""
    vacuums = discover_vacuums()
    results = []
    for dev in vacuums:
        try:
            if action == "start":
                dev.start()
                status = "Started"
            elif action == "stop":
                dev.stop()
                status = "Stopped"
            results.append(f"Vacuum {dev.ip}: {status}")
        except DeviceException as e:
            results.append(f"Vacuum {dev.ip}: Error - {str(e)}")
    return results

@app.route('/start')
def start():
    """Start all Xiaomi vacuums."""
    results = control_vacuums("start")
    return "<br>".join(results) or "No vacuums found."

@app.route('/stop')
def stop():
    """Stop all Xiaomi vacuums."""
    results = control_vacuums("stop")
    return "<br>".join(results) or "No vacuums found."

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

# Write vacuum/requirements.txt
echo "Writing vacuum/requirements.txt..."
cat > "$VACUUM_DIR/requirements.txt" << 'EOF'
flask==2.3.3
python-miio==0.5.12
netifaces==0.11.0
EOF

# Write vacuum/Dockerfile
echo "Writing vacuum/Dockerfile..."
cat > "$VACUUM_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim-bookworm

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
EOF

# Write vacuum/docker-compose.yml
echo "Writing vacuum/docker-compose.yml..."
cat > "$VACUUM_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  vacuum:
    image: localhost:5000/vacuum:latest
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.vacuum.rule=Host(`vacuum.granbacken`)"
        - "traefik.http.routers.vacuum.entrypoints=web,websecure"
        - "traefik.http.routers.vacuum.tls=true"
        - "traefik.http.services.vacuum.loadbalancer.server.port=5000"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 128m
        reservations:
          memory: 64m

networks:
  ingress_network:
    external: true
EOF

# Backup and write infra/docker-compose.yml
echo "Backing up infra/docker-compose.yml..."
if [ -f "$INFRA_DIR/docker-compose.yml" ]; then
    cp "$INFRA_DIR/docker-compose.yml" "$INFRA_DIR/docker-compose.yml.bak-$(date +%F-%H%M%S)"
fi

echo "Writing infra/docker-compose.yml..."
cat > "$INFRA_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(`portainer.granbacken`)"
        - "traefik.http.routers.portainer.entrypoints=web,websecure"
        - "traefik.http.routers.portainer.tls=true"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.docker.network=ingress_network"

  portainer-agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ingress_network
    deploy:
      mode: global

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - ingress_network
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *
      - DISABLE_HTTP=false
    deploy:
      placement:
        constraints: [node.role == manager]

  registry:
    image: registry:2
    volumes:
      - registry_data:/var/lib/registry
    networks:
      - ingress_network
    deploy:
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.registry.rule=Host(`registry.granbacken`)"
        - "traefik.http.routers.registry.entrypoints=web,websecure"
        - "traefik.http.routers.registry.tls=true"
        - "traefik.http.services.registry.loadbalancer.server.port=5000"
        - "traefik.docker.network=ingress_network"
      resources:
        limits:
          memory: 128m
        reservations:
          memory: 64m

volumes:
  portainer_data:
  registry_data:

networks:
  ingress_network:
    external: true
EOF

# Set permissions
echo "Setting permissions..."
chmod 644 "$VACUUM_DIR/app.py" "$VACUUM_DIR/requirements.txt" "$VACUUM_DIR/Dockerfile" "$VACUUM_DIR/docker-compose.yml" "$INFRA_DIR/docker-compose.yml"

# Update /etc/hosts for DNS
echo "Updating /etc/hosts..."
for host in vacuum.granbacken registry.granbacken; do
    if ! grep -q "$host" /etc/hosts; then
        echo "192.168.68.10 $host" | sudo tee -a /etc/hosts
    fi
done

# Build and push vacuum image
echo "Building and pushing vacuum image..."
cd "$VACUUM_DIR"
docker build -t localhost:5000/vacuum:latest .
docker push localhost:5000/vacuum:latest

# Deploy stacks
echo "Deploying infra stack..."
cd "$INFRA_DIR"
docker stack deploy -c docker-compose.yml infra

echo "Deploying vacuum stack..."
cd "$VACUUM_DIR"
docker stack deploy -c docker-compose.yml vacuum

echo "Setup complete! Test with:"
echo "curl -v --insecure https://vacuum.granbacken/start"
echo "curl -v --insecure https://vacuum.granbacken/stop"
echo "Registry at: https://registry.granbacken"
echo "Note: If 'No vacuums found', obtain tokens from Mi Home app v5.4.49 and update app.py."

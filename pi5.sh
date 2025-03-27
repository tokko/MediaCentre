#!/bin/bash

# Exit on any error for reliability
set -e

# Function to display usage
usage() {
    echo "Usage: $0 [--install-dependencies|-i] [--setup-fstab|-f <uuid>] [--teardown|-t] [--force-teardown|-ft] [--swarm-manager] [--swarm-worker <manager-ip>] <nordvpn_username> <nordvpn_password>"
    echo "  --install-dependencies or -i: Install system dependencies, Docker, expand filesystem, overclock, and reboot (optional)"
    echo "  --setup-fstab or -f <uuid>: Set up /etc/fstab for /mnt/pidrive with given UUID (optional, manager only)"
    echo "  --teardown or -t: Remove stack and non-config directories under ${PROJECT_DIR} (preserves config) (optional)"
    echo "  --force-teardown or -ft: Remove stack and all directories under ${PROJECT_DIR} (including config) (optional)"
    echo "  --swarm-manager: Initialize this Pi as the Swarm manager and set up NFS server (optional)"
    echo "  --swarm-worker <manager-ip>: Join this Pi as a Swarm worker and mount NFS from manager (optional)"
    echo "  <nordvpn_username>: NordVPN service username (required)"
    echo "  <nordvpn_password>: NordVPN service password (required)"
    exit 1
}

# Parse arguments
INSTALL_DEPENDENCIES=false
SETUP_FSTAB=false
TEARDOWN=false
FORCE_TEARDOWN=false
SWARM_MANAGER=false
SWARM_WORKER=false
FSTAB_UUID=""
MANAGER_IP=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --install-dependencies|-i)
            INSTALL_DEPENDENCIES=true
            shift
            ;;
        --setup-fstab|-f)
            SETUP_FSTAB=true
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                FSTAB_UUID="$2"
                shift 2
            else
                echo "Error: --setup-fstab or -f requires a UUID parameter."
                usage
            fi
            ;;
        --teardown|-t)
            TEARDOWN=true
            shift
            ;;
        --force-teardown|-ft)
            FORCE_TEARDOWN=true
            shift
            ;;
        --swarm-manager)
            SWARM_MANAGER=true
            shift
            ;;
        --swarm-worker)
            SWARM_WORKER=true
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                MANAGER_IP="$2"
                shift 2
            else
                echo "Error: --swarm-worker requires a manager IP parameter."
                usage
            fi
            ;;
        *)
            break
            ;;
    esac
done

# Check for NordVPN credentials
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: NordVPN username and password are required."
    usage
fi

VPN_USERNAME="$1"
VPN_PASSWORD="$2"

# Validate NordVPN credentials format (basic check)
if [[ "$VPN_USERNAME" =~ ^[a-z0-9-]+$ && "$VPN_PASSWORD" =~ ^[a-zA-Z0-9]+$ ]]; then
    echo "NordVPN credentials format looks plausible."
else
    echo "Warning: NordVPN credentials may be invalid. They should be alphanumeric with dashes (username) or alphanumeric (password)."
    echo "Get service credentials from https://nordvpn.com dashboard under 'Set up NordVPN manually'."
fi

# Variables
PI_USER="pi"
PROJECT_DIR="/mnt/pidrive/media_project"
BASE_DIR="${PROJECT_DIR}/media_server"
TZ="Europe/Stockholm"
PUID=$(id -u ${PI_USER})
PGID=$(id -g ${PI_USER})
TRANSMISSION_USER="admin"
TRANSMISSION_PASS="password"
PI_IP=$(hostname -I | awk '{print $1}')  # Local Pi's IP

# Step 1: Install Dependencies (optional with flag)
if [ "$INSTALL_DEPENDENCIES" = true ]; then
    echo "Expanding filesystem on next boot..."
    sudo raspi-config --expand-rootfs

    echo "Configuring overclock settings in /boot/config.txt..."
    sudo sed -i '/^arm_freq=/d' /boot/config.txt
    sudo sed -i '/^gpu_freq=/d' /boot/config.txt
    sudo sed -i '/^over_voltage=/d' /boot/config.txt
    echo -e "\n# Overclock settings\narm_freq=2000\ngpu_freq=750\nover_voltage=6" | sudo tee -a /boot/config.txt
    echo "Overclock set to 2.0GHz CPU, 750MHz GPU, over_voltage=6. Ensure cooling is adequate!"

    echo "Updating system and installing dependencies..."
    sudo apt update
    sudo apt full-upgrade -y
    sudo apt install -y curl docker.io nfs-common nfs-kernel-server
    sudo rpi-update
    sudo usermod -aG docker ${PI_USER}
    echo "Dependencies installed (curl, docker.io, nfs-common, nfs-kernel-server)."

    echo "Rebooting to apply filesystem expansion, overclock, and group changes..."
    echo "After reboot, rerun this script with the same arguments to continue setup."
    sudo reboot
else
    echo "Skipping dependency installation (use --install-dependencies or -i to install)."
    if ! command -v docker >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo "Error: Docker or curl not found. Run with --install-dependencies or -i to install."
        exit 1
    fi
fi

# Step 2: Configure Swarm and NFS (optional with flags)
if [ "$SWARM_MANAGER" = true ]; then
    echo "Checking Swarm status on this Pi..."
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo "This Pi is already part of a Swarm."
        SWARM_TOKEN=$(docker swarm join-token worker -q)
        echo "Existing Swarm worker join token: $SWARM_TOKEN"
    else
        echo "Initializing this Pi as Swarm manager..."
        docker swarm init --advertise-addr "$PI_IP"
        SWARM_TOKEN=$(docker swarm join-token worker -q)
        echo "Swarm initialized. Worker join token: $SWARM_TOKEN"
    fi
    
    # Save the Swarm token to a file
    echo "Saving Swarm manager token to ${BASE_DIR}/swarm_manager_token.txt..."
    sudo mkdir -p "${BASE_DIR}"  # Ensure BASE_DIR exists
    echo "$SWARM_TOKEN" | sudo tee "${BASE_DIR}/swarm_manager_token.txt" >/dev/null
    sudo chmod 600 "${BASE_DIR}/swarm_manager_token.txt"  # Restrict permissions
    sudo chown ${PI_USER}:${PI_USER} "${BASE_DIR}/swarm_manager_token.txt"
    echo "Swarm token saved. To join workers manually, use: 'docker swarm join --token $(cat ${BASE_DIR}/swarm_manager_token.txt) ${PI_IP}:2377'"

    echo "Setting up NFS server for /mnt/pidrive..."
    sudo mkdir -p /mnt/pidrive
    if ! grep -Fxq "/mnt/pidrive *(rw,sync,no_subtree_check)" /etc/exports; then
        echo "/mnt/pidrive *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    else
        echo "/mnt/pidrive already exported in /etc/exports, skipping addition."
    fi
    sudo exportfs -ra
    sudo systemctl restart nfs-kernel-server
    echo "NFS server configured on $PI_IP:/mnt/pidrive."
elif [ "$SWARM_WORKER" = true ]; then
    echo "Joining this Pi as a Swarm worker to $MANAGER_IP..."
    docker swarm join --token "$(ssh pi@$MANAGER_IP docker swarm join-token worker -q)" "$MANAGER_IP:2377"
    echo "Joined Swarm as worker."

    echo "Mounting NFS share from $MANAGER_IP:/mnt/pidrive..."
    sudo apt install -y nfs-common  # Ensure nfs-common is installed
    sudo mkdir -p /mnt/pidrive
    sudo mount -t nfs "$MANAGER_IP:/mnt/pidrive" /mnt/pidrive
    echo "$MANAGER_IP:/mnt/pidrive /mnt/pidrive nfs defaults 0 0" | sudo tee -a /etc/fstab
    if mountpoint -q /mnt/pidrive; then
        echo "NFS mounted successfully at /mnt/pidrive."
    else
        echo "Error: Failed to mount NFS. Check network or manager NFS setup."
        exit 1
    fi
else
    echo "Skipping Swarm setup (use --swarm-manager or --swarm-worker <manager-ip>). Checking if Swarm is active..."
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo "Swarm not active. Initializing single-node Swarm..."
        docker swarm init --advertise-addr "$PI_IP"
        echo "Single-node Swarm initialized."
    fi
fi

# Step 3: Teardown existing setup (optional with flags)
if [ "$TEARDOWN" = true ] || [ "$FORCE_TEARDOWN" = true ]; then
    echo "Tearing down existing stack..."
    if [ -d "$BASE_DIR" ]; then
        cd "$BASE_DIR"
        docker stack rm media-server || true
        sleep 10  # Give Swarm time to clean up
    fi
    if [ "$FORCE_TEARDOWN" = true ]; then
        echo "Force teardown: Removing all directories under ${PROJECT_DIR} (including config)..."
        sudo rm -rf "${PROJECT_DIR}"/*
    else
        echo "Standard teardown: Removing non-config directories under ${PROJECT_DIR} (preserving config)..."
        sudo find "${PROJECT_DIR}" -maxdepth 1 -type d -not -name "jellyfin" -not -name "sonarr" -not -name "radarr" -not -name "prowlarr" -not -name "overseerr" -not -name "transmission" -not -name "." -exec rm -rf {} +
    fi
    echo "Teardown complete."
fi

# Step 4: Configure /etc/fstab for /mnt/pidrive (manager only, optional with flag)
if [ "$SETUP_FSTAB" = true ] && [ "$SWARM_MANAGER" = true ]; then
    echo "Configuring /etc/fstab for /mnt/pidrive with UUID=${FSTAB_UUID} on manager..."
    if ! blkid -U "$FSTAB_UUID" >/dev/null 2>&1; then
        echo "Error: UUID ${FSTAB_UUID} not found. Verify with 'blkid'."
        exit 1
    fi
    sudo cp /etc/fstab /etc/fstab.bak
    sudo sed -i '/\/mnt\/pidrive/d' /etc/fstab
    echo "UUID=${FSTAB_UUID} /mnt/pidrive ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
    sudo mkdir -p /mnt/pidrive
    if sudo mount -a; then
        echo "/mnt/pidrive mounted successfully."
    else
        echo "Error: Failed to mount /mnt/pidrive. Restoring fstab backup and exiting."
        sudo cp /etc/fstab.bak /etc/fstab
        exit 1
    fi
elif [ "$SETUP_FSTAB" = true ] && [ "$SWARM_WORKER" = true ]; then
    echo "Warning: --setup-fstab ignored on worker. NFS mount is used instead."
else
    echo "Skipping fstab setup (use --setup-fstab or -f <uuid> on manager)."
fi

# Step 5: Create and configure directory structure
echo "Setting up directories under ${PROJECT_DIR}..."
sudo mkdir -p ${BASE_DIR}
sudo mkdir -p ${PROJECT_DIR}/{jellyfin/config,jellyfin/cache,sonarr/config,radarr/config,prowlarr/config,overseerr/config,transmission/config}
sudo mkdir -p ${PROJECT_DIR}/{downloads/complete,downloads/incomplete,downloads/watch,media/tv,media/movies}

# Create Docker secrets for Transmission
echo "${TRANSMISSION_USER}" | sudo tee ${BASE_DIR}/transmission_user_secret >/dev/null
echo "${TRANSMISSION_PASS}" | sudo tee ${BASE_DIR}/transmission_pass_secret >/dev/null
sudo chmod 600 ${BASE_DIR}/transmission_user_secret ${BASE_DIR}/transmission_pass_secret

# Preconfigure Jellyfin (disable transcoding)
echo "Preconfiguring Jellyfin..."
sudo mkdir -p ${PROJECT_DIR}/jellyfin/config
cat << EOF > ${PROJECT_DIR}/jellyfin/config/system.xml
<?xml version="1.0" encoding="utf-8"?>
<ServerConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <EnableHardwareEncoding>false</EnableHardwareEncoding>
  <EnableTranscoding>false</EnableTranscoding>
  <LocalNetworkAddresses>${PI_IP}</LocalNetworkAddresses>
</ServerConfiguration>
EOF

# Minimal initial configs for Sonarr, Radarr, Prowlarr, Overseerr
echo "Preconfiguring Sonarr..."
sudo mkdir -p ${PROJECT_DIR}/sonarr/config
cat << EOF > ${PROJECT_DIR}/sonarr/config/config.xml
<Config>
  <BindAddress>*</BindAddress>
  <Port>8989</Port>
  <UrlBase></UrlBase>
</Config>
EOF

echo "Preconfiguring Radarr..."
sudo mkdir -p ${PROJECT_DIR}/radarr/config
cat << EOF > ${PROJECT_DIR}/radarr/config/config.xml
<Config>
  <BindAddress>*</BindAddress>
  <Port>7878</Port>
  <UrlBase></UrlBase>
</Config>
EOF

echo "Preconfiguring Prowlarr..."
sudo mkdir -p ${PROJECT_DIR}/prowlarr/config

echo "Preconfiguring Overseerr..."
sudo mkdir -p ${PROJECT_DIR}/overseerr/config

# Check if /mnt/pidrive is mounted and writable
echo "Checking /mnt/pidrive mount..."
if ! mountpoint -q /mnt/pidrive; then
    echo "Error: /mnt/pidrive is not mounted. Ensure NFS (worker) or fstab (manager) is set up."
    exit 1
fi
if sudo touch /mnt/pidrive/.testfile 2>/dev/null; then
    sudo rm -f /mnt/pidrive/.testfile
    echo "Mount is writable. Setting ownership and permissions..."
    sudo chown -R ${PI_USER}:${PI_USER} ${PROJECT_DIR}
    sudo chmod -R 775 ${PROJECT_DIR}
else
    echo "Error: /mnt/pidrive is read-only. Remount with 'rw' or fix NFS/fstab."
    exit 1
fi

# Step 6: Create Docker Swarm stack file
echo "Generating docker-compose-swarm.yml in ${BASE_DIR}..."
cat << EOF > ${BASE_DIR}/docker-compose-swarm.yml
version: '3.7'

services:
  gluetun:
    image: qmcgaw/gluetun:latest
    cap_add:
      - NET_ADMIN
    environment:
      - VPN_SERVICE_PROVIDER=nordvpn
      - VPN_TYPE=openvpn
      - OPENVPN_USER=${VPN_USERNAME}
      - OPENVPN_PASSWORD=${VPN_PASSWORD}
      - SERVER_COUNTRIES=Sweden
    ports:
      - 51413:51413
      - 51413:51413/udp
      - 9091:9091
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]  # VPN on manager
    restart: unless-stopped

  transmission:
    image: lscr.io/linuxserver/transmission:latest
    network_mode: service:gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/transmission/config:/config
      - ${PROJECT_DIR}/downloads/complete:/downloads/complete
      - ${PROJECT_DIR}/downloads/incomplete:/downloads/incomplete
      - ${PROJECT_DIR}/downloads/watch:/watch
    secrets:
      - transmission_user
      - transmission_pass
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]  # Co-locate with gluetun
    restart: unless-stopped

  jellyfin:
    image: jellyfin/jellyfin:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/jellyfin/config:/config
      - ${PROJECT_DIR}/jellyfin/cache:/cache
      - ${PROJECT_DIR}/media:/media
    ports:
      - 8096:8096
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]  # Central media server
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/sonarr/config:/config
      - ${PROJECT_DIR}/downloads:/downloads
      - ${PROJECT_DIR}/media/tv:/tv
    ports:
      - 8989:8989
    deploy:
      replicas: 1
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/radarr/config:/config
      - ${PROJECT_DIR}/downloads:/downloads
      - ${PROJECT_DIR}/media/movies:/movies
    ports:
      - 7878:7878
    deploy:
      replicas: 1
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/prowlarr/config:/config
    ports:
      - 9696:9696
    deploy:
      replicas: 1
    restart: unless-stopped

  overseerr:
    image: sctx/overseerr:latest
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${PROJECT_DIR}/overseerr/config:/app/config
    ports:
      - 5055:5055
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]  # Run on manager with Jellyfin
    restart: unless-stopped

secrets:
  transmission_user:
    file: ${BASE_DIR}/transmission_user_secret
  transmission_pass:
    file: ${BASE_DIR}/transmission_pass_secret

volumes:
  jellyfin-config:
  jellyfin-cache:
  sonarr-config:
  radarr-config:
  prowlarr-config:
  overseerr-config:
  transmission-config:
  downloads:
  media:
EOF

# Step 7: Set permissions on docker-compose-swarm.yml
sudo chown ${PI_USER}:${PI_USER} ${BASE_DIR}/docker-compose-swarm.yml
sudo chmod 664 ${BASE_DIR}/docker-compose-swarm.yml

# Step 8: Deploy stack to Swarm
echo "Deploying media server stack to Docker Swarm..."
cd ${BASE_DIR}
docker stack deploy -c docker-compose-swarm.yml media-server
echo "Waiting for services to stabilize..."
sleep 60

# Verify
docker service ls

# Step 9: Extract API keys and configure services (manager only)
if [ "$SWARM_MANAGER" = true ]; then
    echo "Extracting API keys..."
    SONARR_API_KEY="not-found"
    RADARR_API_KEY="not-found"
    PROWLARR_API_KEY="not-found"
    SONARR_CONTAINER=$(docker ps -q -f name=media-server_sonarr)
    RADARR_CONTAINER=$(docker ps -q -f name=media-server_radarr)
    PROWLARR_CONTAINER=$(docker ps -q -f name=media-server_prowlarr)
    
    if [ -n "$SONARR_CONTAINER" ]; then
        SONARR_API_KEY=$(docker exec $SONARR_CONTAINER cat /config/config.xml | grep -oP '<ApiKey>\K[^<]+' || echo "not-found")
    fi
    if [ -n "$RADARR_CONTAINER" ]; then
        RADARR_API_KEY=$(docker exec $RADARR_CONTAINER cat /config/config.xml | grep -oP '<ApiKey>\K[^<]+' || echo "not-found")
    fi
    if [ -n "$PROWLARR_CONTAINER" ]; then
        PROWLARR_API_KEY=$(docker exec $PROWLARR_CONTAINER cat /config/config.xml | grep -oP '<ApiKey>\K[^<]+' || echo "not-found")
    fi

    # Configure Transmission
    echo "Configuring Transmission in Sonarr and Radarr..."
    if [ "$SONARR_API_KEY" != "not-found" ]; then
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_API_KEY" \
            http://${PI_IP}:8989/api/v3/downloadclient \
            -d "{\"name\":\"Transmission\",\"implementation\":\"Transmission\",\"protocol\":\"torrent\",\"priority\":1,\"fields\":[{\"name\":\"host\",\"value\":\"${PI_IP}\"},{\"name\":\"port\",\"value\":9091},{\"name\":\"username\",\"value\":\"${TRANSMISSION_USER}\"},{\"name\":\"password\",\"value\":\"${TRANSMISSION_PASS}\"}]}"
        echo "Transmission configured in Sonarr."
    else
        echo "Warning: Could not configure Transmission in Sonarr. Check 'docker service logs media-server_sonarr'."
    fi

    if [ "$RADARR_API_KEY" != "not-found" ]; then
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $RADARR_API_KEY" \
            http://${PI_IP}:7878/api/v3/downloadclient \
            -d "{\"name\":\"Transmission\",\"implementation\":\"Transmission\",\"protocol\":\"torrent\",\"priority\":1,\"fields\":[{\"name\":\"host\",\"value\":\"${PI_IP}\"},{\"name\":\"port\",\"value\":9091},{\"name\":\"username\",\"value\":\"${TRANSMISSION_USER}\"},{\"name\":\"password\",\"value\":\"${TRANSMISSION_PASS}\"}]}"
        echo "Transmission configured in Radarr."
    else
        echo "Warning: Could not configure Transmission in Radarr. Check 'docker service logs media-server_radarr'."
    fi

    # Configure quality profiles and subtitles
    echo "Configuring quality profiles and subtitles..."
    if [ "$SONARR_API_KEY" != "not-found" ]; then
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_API_KEY" \
            http://${PI_IP}:8989/api/v3/qualityprofile \
            -d '{"name":"HD-720p/1080p","upgradeAllowed":true,"cutoff":20,"items":[{"id":4,"name":"HDTV-720p","allowed":true},{"id":5,"name":"Bluray-720p","allowed":true},{"id":8,"name":"HDTV-1080p","allowed":true},{"id":10,"name":"Bluray-1080p","allowed":true}]}'
        curl -s -X PUT -H "Content-Type: application/json" -H "X-Api-Key: $SONARR_API_KEY" \
            http://${PI_IP}:8989/api/v3/config/mediamanagement \
            -d '{"autoUnmonitorPreviouslyDownloadedEpisodes":false,"recycleBin":"","recycleBinCleanupDays":7,"downloadPropersAndRepacks":"preferAndUpgrade","allowHardcodedSubs":false,"enableMediaInfo":true,"importExtraFiles":true,"extraFileExtensions":"srt","fileDate":"none","subtitleLanguage":"en"}'
        echo "Sonarr quality profile and subtitles configured."
    fi

    if [ "$RADARR_API_KEY" != "not-found" ]; then
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $RADARR_API_KEY" \
            http://${PI_IP}:7878/api/v3/qualityprofile \
            -d '{"name":"HD-720p/1080p","upgradeAllowed":true,"cutoff":10,"items":[{"id":5,"name":"Bluray-720p","allowed":true},{"id":10,"name":"Bluray-1080p","allowed":true}]}'
        curl -s -X PUT -H "Content-Type: application/json" -H "X-Api-Key: $RADARR_API_KEY" \
            http://${PI_IP}:7878/api/v3/config/mediamanagement \
            -d '{"autoUnmonitorPreviouslyDownloadedMovies":false,"recycleBin":"","recycleBinCleanupDays":7,"downloadPropersAndRepacks":"preferAndUpgrade","allowHardcodedSubs":false,"enableMediaInfo":true,"importExtraFiles":true,"extraFileExtensions":"srt","fileDate":"none","subtitleLanguage":"en"}'
        echo "Radarr quality profile and subtitles configured."
    fi

    # Configure Prowlarr with indexers and sync
    if [ "$PROWLARR_API_KEY" != "not-found" ]; then
        echo "Adding indexers to Prowlarr..."
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
            http://${PI_IP}:9696/api/v1/indexer \
            -d '{"name":"1337x","implementation":"Torznab","configContract":"TorznabSettings","settings":{"baseUrl":"https://1337x.to"},"enableRss":true,"enableAutomaticSearch":true}'
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
            http://${PI_IP}:9696/api/v1/indexer \
            -d '{"name":"RARBG","implementation":"Torznab","configContract":"TorznabSettings","settings":{"baseUrl":"https://rarbg.to"},"enableRss":true,"enableAutomaticSearch":true}'
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
            http://${PI_IP}:9696/api/v1/indexer \
            -d '{"name":"YTS","implementation":"Torznab","configContract":"TorznabSettings","settings":{"baseUrl":"https://yts.mx"},"enableRss":true,"enableAutomaticSearch":true}'
        curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
            http://${PI_IP}:9696/api/v1/indexer \
            -d '{"name":"The Pirate Bay","implementation":"Torznab","configContract":"TorznabSettings","settings":{"baseUrl":"https://thepiratebay.org"},"enableRss":true,"enableAutomaticSearch":true}'

        echo "Syncing Prowlarr with Sonarr and Radarr..."
        if [ "$SONARR_API_KEY" != "not-found" ]; then
            curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
                http://${PI_IP}:9696/api/v1/applications \
                -d "{\"name\":\"Sonarr\",\"syncLevel\":\"full\",\"implementation\":\"Sonarr\",\"configContract\":\"SonarrSettings\",\"settings\":{\"baseUrl\":\"http://${PI_IP}:8989\",\"apiKey\":\"${SONARR_API_KEY}\",\"syncCategories\":[1000,2000,3000,4000,5000,6000]}}"
        fi
        if [ "$RADARR_API_KEY" != "not-found" ]; then
            curl -s -X POST -H "Content-Type: application/json" -H "X-Api-Key: $PROWLARR_API_KEY" \
                http://${PI_IP}:9696/api/v1/applications \
                -d "{\"name\":\"Radarr\",\"syncLevel\":\"full\",\"implementation\":\"Radarr\",\"configContract\":\"RadarrSettings\",\"settings\":{\"baseUrl\":\"http://${PI_IP}:7878\",\"apiKey\":\"${RADARR_API_KEY}\",\"syncCategories\":[2000]}}"
        fi
        echo "Prowlarr configured and synced."
    else
        echo "Warning: Could not configure Prowlarr. Check 'docker service logs media-server_prowlarr'."
    fi
fi

# Step 10: Verify and provide next steps
echo "Verifying running services..."
docker service ls

if [ "$SWARM_MANAGER" = true ]; then
    echo "Verifying Transmission connectivity from Radarr..."
    if [ "$RADARR_API_KEY" != "not-found" ]; then
        curl -s -X GET -H "X-Api-Key: $RADARR_API_KEY" http://${PI_IP}:7878/api/v3/system/status > /dev/null && echo "Radarr is up and running."
        curl -s -X GET http://${PI_IP}:9091/transmission/web/ > /dev/null && echo "Transmission is accessible at ${PI_IP}:9091."
    fi

    echo -e "\nSetup complete! Next steps:"
    echo "1. Access Jellyfin at http://${PI_IP}:8096"
    echo "   - On first login, set up admin user and add libraries (/media/tv, /media/movies)."
    echo "   - Transcoding is disabled for lightweight operation."
    echo "2. Access management services via manager IP ($PI_IP):"
    echo "   - Sonarr: http://${PI_IP}:8989"
    echo "   - Radarr: http://${PI_IP}:7878"
    echo "   - Prowlarr: http://${PI_IP}:9696"
    echo "   - Overseerr: http://${PI_IP}:5055"
    echo "   - Transmission: httpmunity://${PI_IP}:9091 (default: admin/password)"
    echo "3. Monitor with 'docker service ls' or 'docker service ps media-server_<service>'"
    echo "4. Check logs if issues: 'docker service logs media-server_jellyfin', etc."
    echo "5. To scale, add workers with: './setup_media_server.sh --swarm-worker $PI_IP <username> <password>'"
    echo "   - Or manually join with token from ${BASE_DIR}/swarm_manager_token.txt"
    echo "All project data is in ${PROJECT_DIR}. Enjoy your lightweight media server!"
else
    echo -e "\nWorker setup complete! Next steps:"
    echo "1. Verify services with 'docker service ls'."
    echo "2. Access Jellyfin and services via manager IP ($MANAGER_IP) as configured on the manager."
    echo "3. Check logs if issues: 'docker service logs media-server_<service>'."
fi

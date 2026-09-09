#!/usr/bin/env bash
set -e

echo "=== 1. Installing MicroK8s and Base Utilities ==="
sudo snap install microk8s --classic
sudo snap install helm --classic

# Add current user to microk8s group
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
sudo chown -f -R $USER ~/.kube

# Set up alias for kubectl in .bashrc if not present
if ! grep -q "alias kubectl='microk8s kubectl'" ~/.bashrc; then
  echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
fi

echo "=== 2. Enabling MicroK8s Addons ==="
# Wait for MicroK8s core to be ready before enabling addons
sudo microk8s status --wait-ready
sudo microk8s enable dns
sudo microk8s enable hostpath-storage
sudo microk8s enable metrics-server
sudo microk8s enable ingress

echo "=== 3. Configuring Host Systems and Directories ==="
# Disable systemd-resolved DNSStubListener to free port 53 for Pi-hole
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved || true

# Shared Media Directories
sudo mkdir -p /srv/media/tv /srv/media/downloads /srv/media/movies
sudo chmod -R 777 /srv/media

# Service Storage Directories (only the apps that use hostPath, not PVCs)
sudo mkdir -p /srv/jellyfin/config
sudo chmod -R 777 /srv/jellyfin

sudo mkdir -p /srv/pihole/data
sudo chmod -R 777 /srv/pihole

sudo mkdir -p /srv/immich/upload /srv/immich/postgres
sudo chmod -R 777 /srv/immich

echo "=== Host setup complete ==="
echo ""
echo "MicroK8s is ready. To connect Helm to it:"
echo "  microk8s config > ~/.kube/config"
echo ""
echo "The application stack (Homepage, Jellyfin, Sonarr, Prowlarr, Bazarr,"
echo "qBittorrent, Pi-hole, Immich, Jellyseerr, FlareSolverr, and the Infisical"
echo "secret sync) is now installed as a Helm chart, not by this script."
echo "See README.md for how to configure and run:"
echo ""
echo "  microk8s helm dependency update ./chart/homelab"
echo "  microk8s helm install homelab ./chart/homelab \\"
echo "    -n homelab --create-namespace \\"
echo "    -f my-secrets.values.yaml"

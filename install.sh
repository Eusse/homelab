#!/usr/bin/env bash
set -e

echo "=== 1. Installing MicroK8s and Base Utilities ==="

echo "--> Installing MicroK8s via snap (downloads ~200MB+, can take a few minutes on a slow connection)..."
sudo snap install microk8s --classic
echo "--> MicroK8s installed."

echo "--> Installing Helm via snap..."
sudo snap install helm --classic
echo "--> Helm installed."

echo "--> Adding $USER to the microk8s group and preparing ~/.kube..."
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
sudo chown -f -R $USER ~/.kube

# Set up alias for kubectl in .bashrc if not present
if ! grep -q "alias kubectl='microk8s kubectl'" ~/.bashrc; then
  echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
  echo "--> Added 'kubectl' alias to ~/.bashrc."
fi

echo "=== 2. Enabling MicroK8s Addons ==="

echo "--> Waiting for MicroK8s core services to become ready..."
echo "    (on a fresh install this commonly takes 1-3 minutes with no output - that's normal, not frozen)"
( while true; do sleep 10; echo "    ...still waiting on MicroK8s..."; done ) &
HEARTBEAT_PID=$!
sudo microk8s status --wait-ready
kill "$HEARTBEAT_PID" 2>/dev/null || true
wait "$HEARTBEAT_PID" 2>/dev/null || true
echo "--> MicroK8s core is ready."

echo "--> Enabling dns addon..."
sudo microk8s enable dns
echo "--> Enabling hostpath-storage addon..."
sudo microk8s enable hostpath-storage
echo "--> Enabling metrics-server addon..."
sudo microk8s enable metrics-server
echo "--> Enabling ingress addon..."
sudo microk8s enable ingress
echo "--> All addons enabled."

echo "=== 3. Configuring Host Systems and Directories ==="

echo "--> Freeing port 53 for Pi-hole (disabling systemd-resolved's DNS stub listener)..."
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved || true

echo "--> Creating shared media directories under /srv/media..."
sudo mkdir -p /srv/media/tv /srv/media/downloads /srv/media/movies
sudo chmod -R 777 /srv/media

echo "--> Creating Jellyfin config directory..."
sudo mkdir -p /srv/jellyfin/config
sudo chmod -R 777 /srv/jellyfin

echo "--> Creating Pi-hole data directory..."
sudo mkdir -p /srv/pihole/data
sudo chmod -R 777 /srv/pihole

echo "--> Creating Immich upload/postgres directories..."
sudo mkdir -p /srv/immich/upload /srv/immich/postgres
sudo chmod -R 777 /srv/immich

echo ""
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
echo ""
echo "Note: that helm install can also sit quiet for a few minutes on first run"
echo "(Postgres + Redis + Infisical + its setup jobs all have to come up in"
echo "sequence) - add --debug for live progress, or watch it from another"
echo "terminal with: kubectl -n homelab get pods -w"

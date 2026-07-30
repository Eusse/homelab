# Installs dependencies in an ubuntu server
# TODO: Conenct via SSH
sudo snap install microk8s --classic
# Join the microk8s group to run commands without sudo
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
sudo chown -f -R $USER ~/.kube

# Reload the user session group membership
newgrp microk8s

# Create an alias so you can just type 'kubectl' instead of 'microk8s kubectl'
# TODO: move this to .bash_aliases and configute it to auto-load
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
source ~/.bashrc
# Configure addons
microk8s enable dns
microk8s enable hostpath-storage
# Set up Directories for Jellyfin Data
sudo mkdir -p /srv/jellyfin/config
sudo mkdir -p /srv/jellyfin/tvshows
sudo mkdir -p /srv/jellyfin/movies
# Ensure permissions allow the containers to write to the config path
sudo chmod -R 777 /srv/jellyfin/config
# Pi- Hole
sudo mkdir -p /srv/pihole/config
sudo chmod -R 777 /srv/pihole
# Handle Port 53 Conflict on Host
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved
# Immich
sudo mkdir -p /srv/immich/upload
sudo mkdir -p /srv/immich/postgres
sudo chmod -R 777 /srv/immich
# Install helm
sudo snap install helm --classic
# install sonarr
sudo mkdir -p /srv/media/tv
sudo mkdir -p /srv/media/downloads
sudo chmod -R 777 /srv/media

#helm install seerr oci://ghcr.io/seerr-team/seerr/seerr-chart
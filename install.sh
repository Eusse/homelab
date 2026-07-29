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


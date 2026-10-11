#!/usr/bin/env bash
echo "Provisioning mbenbajjSW"
sudo apt-get update
# Wait for the server to write the token file
while [ ! -f /vagrant/.vagrant/token ]; do sleep 2; done
K3S_TOKEN=$(sudo cat /vagrant/.vagrant/token)

# Install K3s agent, joining the server
echo "Installing k3s on mbenbajjSW"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" INSTALL_K3S_EXEC="--flannel-iface=eth1 --node-ip=192.168.56.111" K3S_URL="https://192.168.56.110:6443" K3S_TOKEN="${K3S_TOKEN}" sh -

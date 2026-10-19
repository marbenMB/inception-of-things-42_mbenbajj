#!/usr/bin/env bash
set -eo pipefail

echo "Provisioning mmezianiS"

sudo apt-get update
echo "Installing k3s on mmezianiS"
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" INSTALL_K3S_EXEC="--flannel-iface=eth1 --node-ip=192.168.56.110 --tls-san=192.168.56.110" sh -

# Wait for the API server before applying the manifests
until sudo kubectl get nodes >/dev/null 2>&1; do sleep 2; done

echo "Deploying the applications"
sudo kubectl apply -f /vagrant/confs/

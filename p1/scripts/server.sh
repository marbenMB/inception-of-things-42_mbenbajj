#!/usr/bin/env bash
echo "Provisioning abellakrS"
sudo apt-get update
echo "Installing k3s on abellakrS"
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" INSTALL_K3S_EXEC="--flannel-iface=eth1 --node-ip=192.168.56.110 --tls-san=192.168.56.110" sh -
sudo cp /var/lib/rancher/k3s/server/node-token /vagrant/.vagrant/token

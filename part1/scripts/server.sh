#!/bin/bash

rm -rf /var/lib/rancher/k3s 2>/dev/null || true

export K3S_TOKEN="${K3S_TOKEN}"
export INSTALL_K3S_EXEC="server \
  --node-ip=${SERVER_IP} \
  --flannel-iface=eth1 \
  --write-kubeconfig-mode=644"

curl -sfL https://get.k3s.io | sh -

sleep 5
timeout 90 bash -c "until kubectl get nodes &>/dev/null; do sleep 3; done"

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
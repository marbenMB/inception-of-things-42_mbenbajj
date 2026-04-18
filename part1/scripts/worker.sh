#!/bin/bash


echo "==> Waiting for K3s server at ${SERVER_IP}:6443..."
timeout 120 bash -c "until nc -z ${SERVER_IP} 6443 2>/dev/null; do
  echo '   ...not ready yet, retrying in 5s'
  sleep 5
done"
echo "==> Server is reachable."

export K3S_URL="https://${SERVER_IP}:6443"
export K3S_TOKEN="${K3S_TOKEN}"
export INSTALL_K3S_EXEC="agent \
  --node-ip=${WORKER_IP} \
  --flannel-iface=eth1"

curl -sfL https://get.k3s.io | sh -

echo ""
echo "==> Done! K3s agent joined the cluster."
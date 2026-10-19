#!/usr/bin/env bash
set -eo pipefail

echo "Provisioning mmezianiS"

# Use VirtualBox's NAT DNS (10.0.2.3) instead of the DNS server handed out by DHCP.
# When the host resolves through a local loopback resolver (e.g. a VPN client such as
# Cloudflare WARP on 127.0.2.x), VirtualBox advertises an unusable address (0.0.2.3)
# and nothing in the guest can resolve hostnames. 10.0.2.3 works in every case.
cat > /etc/netplan/99-nat-dns.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [10.0.2.3]
EOF
chmod 600 /etc/netplan/99-nat-dns.yaml   # takes effect on every boot
resolvectl dns eth0 10.0.2.3             # takes effect now, without restarting eth0

sudo apt-get update
echo "Installing k3s on mmezianiS"
sudo curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" INSTALL_K3S_EXEC="--flannel-iface=eth1 --node-ip=192.168.56.110 --tls-san=192.168.56.110" sh -

# Wait for the API server before applying the manifests
until sudo kubectl get nodes >/dev/null 2>&1; do sleep 2; done

echo "Deploying the applications"
sudo kubectl apply -f /vagrant/confs/

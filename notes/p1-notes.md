# p1 Project Notes — K3s and Vagrant

Project-specific notes for Part 1: how this setup is built, the problems encountered, and
how each was resolved. For general concepts see [`vagrant-refresher.md`](vagrant-refresher.md) (Vagrant and VM
networking) and [`k8s-k3s-refresher.md`](k8s-k3s-refresher.md) (Kubernetes and k3s).

## Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Files](#3-files)
4. [The Vagrantfile, line by line](#4-the-vagrantfile-line-by-line)
5. [Networking in this setup](#5-networking-in-this-setup)
6. [The "primary network interface" requirement](#6-the-primary-network-interface-requirement)
7. [Forming the cluster](#7-forming-the-cluster)
8. [Problems encountered](#8-problems-encountered)
9. [Known limitations](#9-known-limitations)
10. [Requirements checklist](#10-requirements-checklist)
11. [Scratchpad](#11-scratchpad)

## 1. Overview

Part 1 provisions two virtual machines with Vagrant and installs k3s on them: one in
server (control-plane) mode, one in agent (worker) mode. The two nodes communicate over a
dedicated private network.

Most problems in this part came down to one question: which virtual network adapter is
which, and is k3s using the right one?

## 2. Architecture

```
            internet
              |  (NAT, one per VM, for downloads)
   +----------+-----------+              +-----------------------+
   |      abellakrS       |   private    |      mbenbajjSW       |
   |  k3s server          |<------------>|  k3s agent            |
   |  eth1 192.168.56.110 |   network    |  eth1 192.168.56.111  |
   +----------------------+              +-----------------------+
                    192.168.56.0/24 (host-only)
```

- Server: `abellakrS`, k3s control plane, `192.168.56.110`.
- Worker: `mbenbajjSW`, k3s agent, `192.168.56.111`.
- Box: `bento/ubuntu-24.04` (pinned to `202510.26.0`), 1 CPU and 1024 MB per VM.

See also: [k8s/k3s Reference: 3. Cluster architecture](k8s-k3s-refresher.md#3-cluster-architecture), [k8s/k3s Reference: Server and agent roles](k8s-k3s-refresher.md#server-and-agent-roles).

## 3. Files

```
p1/
  Vagrantfile          two machine definitions, networks, provider settings
  scripts/server.sh    installs k3s server, copies the join token to /vagrant/.vagrant/token
  scripts/worker.sh    waits for the token, installs k3s agent and joins the server
  confs/               empty in p1 (manifests start in p2)
```

The Vagrantfile calls the scripts with `provision "shell", path: "scripts/…"`, matching
the layout in the subject's submission example.

## 4. The Vagrantfile, line by line

Shared settings (outer `config`, apply to both machines):

- `config.vm.box = "bento/ubuntu-24.04"` and `box_version = "202510.26.0"` — same image
  and version on every rebuild.
- `vb.memory = "1024"`, `vb.cpus = 1` — the minimal resources the subject recommends.
- `vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]` and
  `"--natdnsproxy1", "on"` — the guest's DNS queries go through the host's resolver
  instead of VirtualBox's built-in one. This helps when the host uses a VPN or custom
  DNS.

Per-machine settings (block variable, apply to that machine only):

- `vm.hostname` — `abellakrS` / `mbenbajjSW`.
- `vm.network "private_network", ip: …` — the dedicated IP.
- `vb.name` — the VM's name in VirtualBox.
- `vm.provision "shell", path: …` — `scripts/server.sh` or `scripts/worker.sh`.

See also: [Vagrant Reference: 5. The Vagrantfile](vagrant-refresher.md#5-the-vagrantfile), [Vagrant Reference: 6. Multi-machine setups](vagrant-refresher.md#6-multi-machine-setups).

## 5. Networking in this setup

Each VM has exactly two adapters:

```
   eth0  NAT       10.0.2.15        internet + vagrant ssh
   eth1  private   192.168.56.110   VM-to-VM, used by k3s
```

k3s is told to use the private network explicitly:

- `--node-ip=192.168.56.110` (server) / `192.168.56.111` (worker) — the address the node
  registers with.
- `--flannel-iface=eth1` (both) — the adapter flannel uses for node-to-node traffic.

These flags depend on the private network being `eth1`, which is only true while the
Vagrantfile declares no other network (see [8.2](#82-stray-bridged-adapter)).

See also: [Vagrant Reference: 9. Networking](vagrant-refresher.md#9-networking), [Vagrant Reference: 10. Interface naming in the guest](vagrant-refresher.md#10-interface-naming-in-the-guest).

## 6. The "primary network interface" requirement

The subject says: "Have a dedicated IP on the primary network interface. Server =
192.168.56.110, ServerWorker = 192.168.56.111."

### What the evaluator checks

The correction page tests it with:

```bash
ip a show $(ip route | grep default | awk '{print $5}')
```

Read from the inside out: `ip route` prints the routing table, `grep default` keeps the
default route (`default via 10.0.2.2 dev eth0 …`), `awk '{print $5}'` extracts the
interface name from it (`eth0`), and `ip a show eth0` prints that interface's addresses.

So the correction page defines the primary interface as **the interface that carries the
default route**, and expects `192.168.56.110` on it.

### What this setup shows

```
2: eth0: ... altname enp0s8
    inet 10.0.2.15/24 ... scope global dynamic eth0
```

The default route goes through `eth0`, the NAT adapter, so the command prints
`10.0.2.15`, not the dedicated IP. **Taken literally, this check does not pass.** The same
is true for p2's VM.

Decision taken: keep the setup as it is and explain it during the defense.

### Why it is set up this way

- Vagrant's VirtualBox provider always makes adapter 1 a NAT adapter (`eth0`). Vagrant
  needs it for `vagrant ssh` and provisioning, and it cannot hold a static address: it
  gets `10.0.2.15` from VirtualBox's DHCP.
- NAT is the only adapter with a path to the internet, so it carries the default route.
  The VMs need that to download packages, k3s, and container images.
- The dedicated IP is on the second adapter, the private host-only network (`eth1`). This
  is the interface the two machines use to reach each other, and the one k3s is bound to
  (`--node-ip`, `--flannel-iface=eth1`).
- Moving the default route to `eth1` is possible, but the host-only network has no
  internet gateway (the Mac does not forward its traffic), so the VM would lose internet
  access.

See also: [Vagrant Reference: NAT](vagrant-refresher.md#nat), [Vagrant Reference: Private network (host-only)](vagrant-refresher.md#private-network-host-only), [Vagrant Reference: 10. Interface naming in the guest](vagrant-refresher.md#10-interface-naming-in-the-guest).

### What to show the evaluator instead

```bash
ip a show eth1                   # inet 192.168.56.110/24 — the dedicated IP
ip route get 192.168.56.111     # ... dev eth1 — the machines talk over eth1
sudo kubectl get nodes -o wide  # INTERNAL-IP 192.168.56.110 / .111 — k3s uses it
```

Plus the k3s flags in `scripts/server.sh` and `scripts/worker.sh` (`--node-ip`,
`--flannel-iface=eth1`) and the `private_network` lines in the Vagrantfile.

### If the evaluator insists

Two alternatives exist, neither applied:

- Move the default route to `eth1` after k3s is installed. The check passes for real,
  but the VMs lose internet access afterwards.
- List the default route on `eth1` while internet traffic keeps using `eth0` through two
  more-specific routes (`0.0.0.0/1` and `128.0.0.0/1`). The check passes, but
  `ip route get 8.8.8.8` still shows `eth0`, so this is cosmetic.

### About `primary: true`

The Vagrantfile used to have `primary: true` on both `private_network` lines; it has been
removed. On a network line it does nothing: in Vagrant 2.4.9 the VirtualBox provider
reads only options such as `ip`, `netmask`, `adapter`, `mac`, and `type` for a private
network, and silently ignores the rest. `primary` is a real option on a machine
definition, where it marks the default machine for commands such as `vagrant ssh`:

```ruby
config.vm.define "abellakrS", primary: true do |abellakrS|
```

See also: [Vagrant Reference: Network options and the primary misconception](vagrant-refresher.md#network-options-and-the-primary-misconception).

## 7. Forming the cluster

```
   abellakrS (server.sh)                          mbenbajjSW (worker.sh)
   ---------------------                          ----------------------
   install k3s server                             wait until token file exists
   writes node-token                                      |
   copy token ---> /vagrant/.vagrant/token ---> read token
                   (shared folder)                        |
                                                  install k3s agent with
                                                  K3S_URL=https://192.168.56.110:6443
                                                  K3S_TOKEN=<token>
```

- The server writes its join token to `/var/lib/rancher/k3s/server/node-token` and copies
  it into the shared folder.
- The worker reads the token from the same shared path and joins the server.
- `.vagrant/` is git-ignored, so the token is never committed.
- `vagrant up` creates the machines one after another in definition order, so the server
  is fully provisioned and the token is written before the worker starts.

Server install flags: `--flannel-iface=eth1`, `--node-ip=192.168.56.110`,
`--tls-san=192.168.56.110` (adds the private IP to the API server certificate). Worker
install flags: `--flannel-iface=eth1`, `--node-ip=192.168.56.111`, plus `K3S_URL` and
`K3S_TOKEN`.

Both installs pin `INSTALL_K3S_VERSION="v1.37.1+k3s1"` (see [8.4](#84-k3s-install-failing-with-a-self-signed-certificate)).

Verification:

```bash
vagrant ssh abellakrS -c "sudo kubectl get nodes -o wide"
# abellakrs   Ready   control-plane   192.168.56.110
# mbenbajjsw  Ready   <none>          192.168.56.111
```

See also: [k8s/k3s Reference: Server and agent roles](k8s-k3s-refresher.md#server-and-agent-roles), [Vagrant Reference: 8. Synced folders](vagrant-refresher.md#8-synced-folders).

## 8. Problems encountered

### 8.1 Port collision on 6442/6443

Symptom: `Vagrant found a port collision for the specified port`.

Cause: two `forwarded_port` lines used the outer `config` inside the machine blocks, so
both VMs forwarded both ports.

Fix: removed them. The VMs are reached through their private IPs, so host port forwards
are not needed.

See also: [Vagrant Reference: 6. Multi-machine setups](vagrant-refresher.md#6-multi-machine-setups), [Vagrant Reference: Forwarded ports](vagrant-refresher.md#forwarded-ports), [Vagrant Reference: 12. Troubleshooting](vagrant-refresher.md#12-troubleshooting).

### 8.2 Stray bridged adapter

Symptom: the cluster worked but ran over Wi-Fi, and `vagrant up` would prompt for a
bridge interface on another machine.

Cause: a leftover `config.vm.network "public_network", bridge: "en0: Wi-Fi"` added a third
adapter and shifted the order:

```
   before fix                         after fix
   eth0  NAT      10.0.2.15           eth0  NAT      10.0.2.15
   eth1  bridged  192.168.11.117      eth1  private  192.168.56.110
   eth2  private  192.168.56.110
```

`--flannel-iface=eth1` therefore pointed at the Wi-Fi adapter. It worked only because both
VMs were on the same Wi-Fi network; on an evaluator's machine the `"en0: Wi-Fi"` bridge
would not exist.

Fix: commented out the `public_network` line. The private network returned to `eth1`.

See also: [Vagrant Reference: Public network (bridged)](vagrant-refresher.md#public-network-bridged), [Vagrant Reference: 10. Interface naming in the guest](vagrant-refresher.md#10-interface-naming-in-the-guest).

### 8.3 VM killed at boot (signal 9)

Symptom: `The virtual machine 'abellakrS' has terminated unexpectedly during startup
because of signal 9`.

Cause: the VM wrote no `VBox.log` and left no crash report, so the process was killed by
the host, not by a problem inside the VM. It started after updating macOS to 27.0.1 while
running VirtualBox 7.2.6; the likely cause is host security blocking that older build.

Fix (host side): VirtualBox was upgraded from 7.2.6 to 7.2.20, after which the VMs boot
normally. If it happens again: check System Settings → Privacy & Security for a blocked
VirtualBox item, approve it, and reboot.

See also: [Vagrant Reference: 12. Troubleshooting](vagrant-refresher.md#12-troubleshooting).

### 8.4 k3s install failing with a self-signed certificate

Symptom: `curl: (60) SSL certificate problem: self-signed certificate` during
`Finding release for channel stable`.

Cause: the installer contacts `update.k3s.io` to resolve `stable` into a version. On this
network that host was intercepted and served a forged `TRAEFIK DEFAULT CERT`. DNS
returned the correct IPs, so this was TLS interception, not DNS hijacking. `get.k3s.io`
and GitHub were unaffected.

Diagnosis:

```bash
openssl s_client -connect update.k3s.io:443 | openssl x509 -noout -issuer
# issuer=CN = TRAEFIK DEFAULT CERT
```

Fix: pinned `INSTALL_K3S_VERSION="v1.37.1+k3s1"` on both nodes. The installer skips the
`update.k3s.io` lookup and downloads directly from GitHub. Removing the pin on this network
brings the failure back.

See also: [k8s/k3s Reference: 6. k3s](k8s-k3s-refresher.md#6-k3s).

## 9. Known limitations

- Stale token. `vagrant destroy` does not delete `p1/.vagrant/token`. If the worker is
  brought up on its own (`vagrant up mbenbajjSW`) against a freshly rebuilt server, it
  finds the old file immediately, reads an outdated token, and fails to join. A full
  `vagrant up` is unaffected because the server overwrites the token first. Deleting
  `p1/.vagrant/token` before a rebuild avoids the issue.
- Hard-coded interface name. `--flannel-iface=eth1` assumes the private network is the
  second adapter. Adding any other network to the Vagrantfile breaks it (8.2).
- No error handling in the scripts. If the k3s install fails, `server.sh` still tries to
  copy the token and the worker waits forever for a file that never appears.

## 10. Requirements checklist

- Two VMs via Vagrant, latest stable distro (Ubuntu 24.04).
- Minimal resources: 1 CPU, 1024 MB each.
- Hostnames = team login + suffix: `abellakrS` (S), `mbenbajjSW` (SW).
- Dedicated IPs `192.168.56.110` / `.111` on the private network (see [section 6](#6-the-primary-network-interface-requirement): the
  evaluator's default-route check shows `eth0`, explained rather than changed).
- Passwordless SSH (Vagrant key auth).
- k3s server mode on the first machine, agent mode on the second.
- kubectl available (bundled with k3s).
- Layout: `p1/Vagrantfile`, `p1/scripts/`, `p1/confs/`.

## 11. Scratchpad

Working notes, open questions, and things to double-check for the defense.

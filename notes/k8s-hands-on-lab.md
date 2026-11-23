# Kubernetes Hands-On Lab

Welcome! In this lab you build a small Kubernetes cluster (a group of machines working as
one) with your own hands, then learn
every basic Kubernetes object by using it. No prior Kubernetes knowledge is
needed. Go slowly: the goal is not to finish, it's to understand what you're doing at
every step.

If you want a summary of a concept at any point, the
[k8s/k3s Reference](k8s-k3s-refresher.md) has one; Vagrant is explained in the
[Vagrant Reference](vagrant-refresher.md).

There is an interactive version of this lab: open `k8s-lab.html` in a browser.

## Contents

0. [Before you begin](#0-before-you-begin)
1. [Build the VMs](#1-build-the-vms)
2. [Install the k3s server](#2-install-the-k3s-server)
3. [Join the worker](#3-join-the-worker)
4. [Optional: kubectl from the Mac](#4-optional-kubectl-from-the-mac)
5. [Your first Pod](#5-your-first-pod)
6. [Deployments and self-healing](#6-deployments-and-self-healing)
7. [Services and cluster DNS](#7-services-and-cluster-dns)
8. [Ingress: reach the app from the Mac](#8-ingress-reach-the-app-from-the-mac)
   - [Side quest: How Kubernetes is built](#side-quest-how-kubernetes-is-built)
9. [Rolling updates and rollbacks](#9-rolling-updates-and-rollbacks)
10. [ConfigMaps and Secrets](#10-configmaps-and-secrets)
11. [Health checks and resources](#11-health-checks-and-resources)
12. [Storage that outlives Pods](#12-storage-that-outlives-pods)
13. [Namespaces](#13-namespaces)
14. [Troubleshooting drills](#14-troubleshooting-drills)
15. [Clean up](#15-clean-up)
16. [Putting it all together](#16-putting-it-all-together)
17. [Command cheat sheet](#17-command-cheat-sheet)

## 0. Before you begin

### Containers in two minutes

Kubernetes runs **containers**, so let's make sure that word is clear.

- An **image** is a packaged application: the program plus everything it needs
  (libraries, files, settings), frozen into one bundle. `nginx:1.27-alpine` is an image:
  the nginx web server, version 1.27, built on the small Alpine Linux.
- A **container** is a running copy of an image. One image can run as many containers as
  you like, the same way one installer can install an app on many computers.
- A **registry** is where images are stored and downloaded from: an app store for
  images. Here that's Docker Hub. When you write `nginx:1.27-alpine`, Kubernetes
  downloads it from there.
- The part after `:` is the **tag**, usually the version.

Why containers? Because an image runs the same way everywhere: your laptop, a test
server, a production cluster. "It works on my machine" stops being a problem.

### Kubernetes in two minutes

Running one container by hand is easy. Running fifty of them over ten machines, keeping
them alive when they crash, updating them without downtime, and letting users reach
them: that's hard. **Kubernetes does that for you.**

The single most important idea: in Kubernetes you **describe what you want**, and
Kubernetes **keeps making it true**.

```
   you write:      "I want 3 copies of this web server, reachable at web.lab"
                                     │
   Kubernetes:     checks, all the time:  what you want   vs   what exists
                                     │
                   difference?  ──>  fixes it  (starts, stops, replaces, reroutes)
```

You never say "start this container" or "restart that one". Instead you write a
description of what you want. Kubernetes calls this description an **object**, usually
written in a YAML file called a **manifest**. Small programs inside the cluster, called
**controllers**, then do the work.

Two words for this idea:
- **Declarative**: you say *what* you want, never *how* to do it.
- **Reconciliation loop**: the endless "compare, then fix" that controllers do. Like a
  thermostat.

Keep this picture in mind: every section of this lab is a variation of it.

### Networking in two minutes

Kubernetes is mostly programs talking to other programs over a network, so a few network
words come up all the time. You need four, and this lab uses the same phone comparison
for each of them every time.

- An **IP address** says where a message should go, like `192.168.56.120`. Every machine
  has one, and in Kubernetes every Pod has its own too. A phone number.
- A **port** picks one program on that machine, because one machine runs many programs.
  Web servers listen on port 80, the Kubernetes API on port 6443. An extension: one phone
  number, many extensions, and each program answers its own. Written together:
  `192.168.56.120:6443`.
- **DNS** turns a name into an IP address, so you can use `github.com` instead of a
  number. The contacts app on your phone.
- A **network card** connects a machine to one network and gives it an address there.
  Linux calls them `eth0`, `eth1`, and so on. A phone line: a machine with two cards has
  two lines, with a different number on each.

Every time one thing talks to another in this lab, it's the same three moves:

1. Look up the name: DNS turns `github.com` into an address, like `140.82.121.4`.
2. Call that address, on the port of the program you want: 80 for `http`, 443 for
   `https`.
3. The program listening on that port answers.

Two more words you'll see: `localhost`, or `127.0.0.1`, always means "this same
machine". And `ping` sends a tiny "are you there?" message to an address and waits for a
reply.

### The story of this lab

Each section solves a problem that the previous one left open. That's the thread to hold
on to:

```
 5  Pod          runs your container.
                 problem: if it dies, nothing brings it back.
                      │
 6  Deployment   keeps N Pods alive and replaces them when they die.
                 problem: every new Pod gets a new IP. How do you reach them?
                      │
 7  Service      one stable name and IP in front of the Pods.
                 problem: that IP only works inside the cluster.
                      │
 8  Ingress      lets outside web traffic in, sorted by website name.
                 problem: how do you update the app without stopping it?
                      │
 9  Rollout      replaces Pods gradually, with an undo button.
                 problem: changing a setting means building a new image?
                      │
10  ConfigMap    settings and files kept outside the image ...
    Secret       ... and the same for passwords and keys.
                 problem: Kubernetes thinks an app is fine as long as it runs,
                 even when it's stuck.
                      │
11  Probes       health checks: restart stuck apps, hold back unready ones.
    Resources    how much CPU and memory each app needs and may use.
                 problem: files written inside a container vanish when it's replaced.
                      │
12  Storage      disks that outlive Pods.
                 problem: everything lives in one shared space, and names collide.
                      │
13  Namespace    separate spaces inside one cluster.
```

Whenever something feels random, come back here: every object exists because of the
problem just above it.

### What you'll build

Two virtual machines on a private network: one runs the k3s **server** (the brain of the
cluster), the other runs the k3s **agent** (a worker). k3s is a small, complete version of
Kubernetes. You install everything yourself; no script does it for you.

```
   lab-server  192.168.56.120                 lab-worker  192.168.56.121
   +--------------------------------+         +------------------------------+
   |  k3s server (one process)      |         |  k3s agent (one process)     |
   |    API server :6443  <---------------------- kubelet registers here     |
   |    scheduler, controllers      |         |    kubelet                   |
   |    datastore (SQLite)          |         |    containerd  (runs pods)   |
   |    kubelet, containerd         |         |    flannel     (pod network) |
   |    flannel                     |         |                              |
   +--------------------------------+         +------------------------------+
          eth1  <===== private network 192.168.56.x: cluster traffic ====>  eth1
```

`.120` and `.121` are the two VMs' addresses, `:6443` is the API server's port, and
`eth1` is each VM's network card on the private network (section 1). Don't worry if the
other names mean nothing yet. Sections 2 and 3 introduce them, and the side quest after
section 8 explains how each one works.

### How each section works

1. **Why** — the problem this section solves.
2. **New words** — each new term, explained in plain words the first time you meet it.
   To find a word again later, search the page for it (Cmd+F).
3. **The idea** — the concept in plain words, usually with a picture.
4. **Read it** — the YAML or command, explained line by line.
5. **Predict** — guess the result *before* running anything. Being wrong is great: it
   shows exactly what you hadn't understood yet.
6. **Do it** — the commands.
7. **What happened** — the mechanism behind what you saw.
8. **Look under the hood** — commands that show the mechanism working.
9. **Experiment** — change one thing and see what happens.
10. **Check your understanding** — questions with hidden answers. Answer out loud first,
    then open.

Steps 5, 9 and 10 are where learning happens. Don't skip them.

### Practical notes

- Install Vagrant and VirtualBox. The `bento/ubuntu-24.04` box downloads automatically on
  the first `vagrant up`.
- Turn Cloudflare WARP off. With it on, the VMs can't look up names (DNS), so nothing
  downloads.
- If your Mac changes network (another Wi-Fi, a phone hotspot) while the VMs run, they
  keep asking the old network's DNS server, so looking up names stops working.
  `vagrant reload` fixes it.
- The Mac is arm64 (Apple Silicon); every image here (`nginx:*-alpine`, `busybox`) is
  published for arm64.
- Plan about 6 hours, over several sessions.

Where to run each command:
- `mac$` — a terminal on the Mac, inside your lab folder (this guide uses
  `~/Desktop/inception-of-things-42/k8s-lab`; use wherever you created yours).
- `server$` — inside `vagrant ssh lab-server`.
- `worker$` — inside `vagrant ssh lab-worker`.

### Coming back after a break

Been away a few days? Run these lines before anything else:

```bash
mac$ cd ~/Desktop/inception-of-things-42/k8s-lab
mac$ vagrant status
mac$ vagrant up
mac$ vagrant ssh lab-server -c "kubectl get nodes"
```

`vagrant status` should show both VMs `running`; run `vagrant up` only if they aren't.
Both nodes `Ready` means the cluster survived the break. After a boot the worker can
take about 5 minutes to show `Ready`.

If something can't download or look up names, check that WARP is off, then run
`vagrant reload`.

Each section starts with a **Coming back?** step: one command that shows whether your
cluster is where that section expects, and how to catch up if it isn't.

## 1. Build the VMs

**Why.** Kubernetes is about running apps across several machines, so you need more than
one. You'll create two virtual ones.

**New words.**
- **VM (virtual machine)**: a complete computer, with its own OS, CPU, memory and
  network cards, simulated by a program (VirtualBox) inside your Mac. You can create,
  break and delete it without touching your Mac.
- **Network card**: the part that connects a machine to a network, also called an
  interface. Each card has its own address on its network. Linux names them `eth0`,
  `eth1`, and so on, in the order they were added. A phone line.
- **NAT (Network Address Translation)**: the network VirtualBox gives each VM for
  internet access. The VM's messages go out through your Mac, so it can reach the
  internet, but nothing outside can reach the VM, not even the other VM. A phone line
  that can make calls but that nobody can call.
- **Private network**: a small network that only your two VMs and your Mac are on, with
  a fixed address for each. An internal line between the three of them: they can all
  call each other, and nobody else is on it.

**The idea.** Each VM gets two network cards, so two lines. `eth0` is on the NAT: the
VM's own line out to the internet, for downloads. `eth1` is on the private network: it
connects the two VMs and your Mac, and that's where the cluster lives.

```
   internet <── NAT (eth0, 10.0.2.15) ── lab-server ── private (eth1, .120) ──┐
   internet <── NAT (eth0, 10.0.2.15) ── lab-worker ── private (eth1, .121) ──┼── Mac
                                                                              │
                                           192.168.56.x ──────────────────────┘
```

`.120` is short for `192.168.56.120`: every address on the private network starts with
`192.168.56.`.

**Read it.** Create the lab folder:

```bash
mac$ mkdir -p ~/Desktop/inception-of-things-42/k8s-lab/manifests && cd ~/Desktop/inception-of-things-42/k8s-lab
```

Then create `~/Desktop/inception-of-things-42/k8s-lab/Vagrantfile`. Every line is explained in its comment:

```ruby
Vagrant.configure("2") do |config|                 # "2" = config format version
  config.vm.box = "bento/ubuntu-24.04"             # base image for both VMs
  config.vm.box_version = "202510.26.0"            # pin it: same image on every rebuild

  config.vm.provider "virtualbox" do |vb|          # defaults for both VMs
    vb.cpus = 1
    vb.memory = "1024"
  end

  config.vm.define "lab-server" do |server|        # first machine, named for Vagrant
    server.vm.hostname = "lab-server"              # the name Linux uses inside the VM
    server.vm.network "private_network", ip: "192.168.56.120"   # becomes eth1
    server.vm.provider "virtualbox" do |vb|
      vb.name = "lab-server"                       # name shown in VirtualBox
      vb.memory = "2048"                           # more RAM: it also runs the brain
    end
  end

  config.vm.define "lab-worker" do |worker|        # second machine
    worker.vm.hostname = "lab-worker"
    worker.vm.network "private_network", ip: "192.168.56.121"
    worker.vm.provider "virtualbox" do |vb|
      vb.name = "lab-worker"
    end
  end
end
```

One rule to notice: settings on the outer `config` apply to every machine; settings
inside a `define` block apply to that machine only.

Each machine gets three names here, all `lab-server` to keep things simple. `define` is
Vagrant's name (`vagrant ssh lab-server`), `vb.name` is the one VirtualBox shows on your
Mac, and `vm.hostname` is the name Linux uses inside the VM. Only the hostname reaches
Kubernetes: it becomes the node's name in the cluster.

**Predict.** Both VMs will have an `eth0` and an `eth1`. Will their `eth0` addresses be
different or the same?

**Do it.**

```bash
mac$ vagrant up
mac$ vagrant status
```

The first time takes a few minutes (the box downloads).

**What happened.** For each machine, Vagrant copied the box, created the VM, attached the
NAT card (automatically) and your private network card, booted it, set its name, and
shared your lab folder inside it at `/vagrant`.

**Look under the hood.**

```bash
mac$ vagrant ssh lab-server -c "ip -br -4 a"
mac$ vagrant ssh lab-worker -c "ip -br -4 a"
mac$ vagrant ssh lab-server -c "ls /vagrant"
```

`ip -br -4 a` lists each network card with its address. `lo` is the machine talking to
itself (`127.0.0.1`), `eth0` is the NAT and `eth1` the private network. You can ignore the
`/24` or `/8` after each address: it describes the size of that network.

Both `eth0` addresses are `10.0.2.15`. Each VM's NAT is its own private bubble, so the
same address in two bubbles never clashes, like two houses that each have a room 1. But it also means the VMs can't reach each
other through `eth0`; only `eth1` connects them. And `/vagrant` shows your Vagrantfile:
any file in your lab folder on the Mac appears there. That's how your YAML files will get
into the cluster.

**Check your understanding.**

<details><summary>Why can't the two VMs talk to each other over eth0?</summary>

Each VM has its own isolated NAT. `10.0.2.15` exists separately inside each one; it's not
a shared network. The private network on `eth1` is the only network both are on.
</details>

<details><summary>How will a YAML file you write on the Mac get into a VM?</summary>

Through the shared folder: your lab folder is mounted at `/vagrant` inside each VM, so
`manifests/web.yaml` on the Mac is `/vagrant/manifests/web.yaml` in the VM.
</details>

**Connect the dots.**
[Vagrant Reference: 9. Networking](vagrant-refresher.md#9-networking) and
[6. Multi-machine setups](vagrant-refresher.md#6-multi-machine-setups).

**Checkpoint.**

```bash
mac$ vagrant ssh lab-worker -c "ping -c 2 192.168.56.120"
mac$ vagrant ssh lab-server -c "getent hosts github.com"
```

`ping` sends a tiny "are you there?" message, so replies mean the worker reaches the
server over the private network. `getent hosts` asks DNS for a name's address, so an
address for `github.com` means looking up names and the internet both work. If
`github.com` gets no address, check that WARP is off, then try
`vagrant reload`.

## 2. Install the k3s server

**Coming back?** This section starts with two running VMs and nothing installed on them yet.

```bash
mac$ vagrant status
```

Both VMs should say `running`. If not, run `vagrant up` (section 1).

**Why.** Right now you have two ordinary computers. To turn them into a cluster, one of
them needs a "brain": something that remembers what you want and decides where things
run.

**New words.**
- **Cluster**: a set of nodes (machines) managed together by one control plane, so you
  deploy to "the cluster" instead of to individual machines. Several computers acting
  as one big computer for your apps.
- **Node**: a machine, physical or virtual, that belongs to the cluster and can run
  Pods. One computer on the team.
- **Control plane**: the components that store the cluster's state and decide what runs
  where: the API server, the datastore, the scheduler and the controllers (its four
  parts, just below). The brain of the cluster.
- **kubectl**: the command-line client for Kubernetes. Every command you type becomes a
  secure web request (HTTPS) to the API server, on port 6443. Your remote control for
  the cluster.
- **Pod**: the smallest unit Kubernetes runs: one or more containers that share an IP.
  For now, picture a small box with your running app inside. Section 5 opens one up.
- **Namespace**: a named space inside the cluster that groups objects, with names unique
  inside it. Like folders: k3s keeps its own extras in `kube-system`, and your apps go in
  `default`. `-n <name>` picks one, `-A` shows all. Section 13 goes deeper.

**The idea.** The brain has four parts, each with one job:

```
   API server    the front desk. Every request goes through it.
   datastore     the memory. Stores everything you create (SQLite in k3s).
   scheduler     the planner. Decides which node runs each new app.
   controllers   the fixers. Compare "wanted" with "actual", and act.
```

Every node also needs two helpers:

```
   kubelet       the node's caretaker: starts and watches the apps assigned to it.
   containerd    the engine that runs containers (the "container runtime").
```

k3s packs all of this into one program.

**Read it.**

```bash
mac$ vagrant ssh lab-server
server$ curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" \
  INSTALL_K3S_EXEC="--node-ip=192.168.56.120 --flannel-iface=eth1 --tls-san=192.168.56.120 --write-kubeconfig-mode=644" sh -
```

Piece by piece:
- `curl -sfL https://get.k3s.io | … sh -` — download the installer and run it. The
  variables before `sh` configure it.
  - Heads-up: `-s` hides progress and `-f` fails quietly. If the download fails you'll see
    **nothing at all**. If the command ends instantly with no output, run it again
    without `-s` to see the error.
- `INSTALL_K3S_VERSION` — install this version, so every rebuild is identical.
- `--node-ip=192.168.56.120` — use this VM's private network address. Otherwise k3s would pick
  `10.0.2.15`, which the other VM can't reach (you saw why in section 1).
- `--flannel-iface=eth1` — send Pod traffic between the machines through `eth1`, the
  private network card (`iface` is short for interface).
- `--tls-san=192.168.56.120` — add this address to the server's certificate, the ID card
  it shows to prove who it is, so your Mac can check it's talking to the real server
  (section 4).
- `--write-kubeconfig-mode=644` — let the `vagrant` user run `kubectl` without `sudo`.

**Predict.** The server will have the brain. Will it *also* appear as a node, a place
where apps can run?

**Do it.** Run the install, then:

```bash
server$ kubectl get nodes -o wide
server$ kubectl get pods -A
```

**What happened.** The installer put one program on the machine, `/usr/local/bin/k3s`,
and started it as a service named `k3s`. That one program is the whole brain.

It also started a kubelet and containerd on this machine, so the server is a node too.
That answers the prediction. k3s lets your apps run on it as well; section 6 shows how
to keep them off. The installer added `kubectl` as a shortcut to k3s, which
is why you didn't have to install it.

**Look under the hood.**

```bash
server$ pgrep -a k3s
server$ sudo ls /var/lib/rancher/k3s/server/db/
server$ kubectl get pods -n kube-system
```

Three things to notice:
- One process. In other setups the brain is four separate programs. k3s packs them into
  one, which is what makes it small.
- `state.db` is the cluster's memory. Everything you create becomes a record in this one
  file.
- The `kube-system` Pods are extras k3s installed for you. You'll use CoreDNS (the cluster's
  contacts app: it turns names into addresses, section 7) and Traefik (it lets web
  requests in from outside, section 8). The
  `helm-install-…` Pods are one-time installers. `Completed` means they finished, not
  that something broke.

**Check your understanding.**

<details><summary>If the API server stopped, could you still create an app?</summary>

No. Every request, including every `kubectl` command, goes through the API server. Apps
already running keep running (the kubelet looks after them), but nothing can change.
</details>

<details><summary>Where is "everything you create" stored?</summary>

In the datastore, `/var/lib/rancher/k3s/server/db/state.db`. The API server is the only
component that reads and writes it.
</details>

**Connect the dots.**
[k8s/k3s Reference: 3. Cluster architecture](k8s-k3s-refresher.md#3-cluster-architecture)
and [6. k3s](k8s-k3s-refresher.md#6-k3s).

**Checkpoint.** `lab-server` is `Ready` with INTERNAL-IP `192.168.56.120`, and every Pod
in `kube-system` is `Running` or `Completed`. Traefik can take a minute or two.

## 3. Join the worker

**Coming back?** This section starts with k3s running on the server.

```bash
server$ kubectl get nodes
```

You should see `lab-server` as `Ready`. If `kubectl` isn't found, k3s isn't installed
yet: redo the install in section 2.

**Why.** A one-machine cluster works, but Kubernetes shines when it spreads work
across machines. Time to add the second one.

**New words.**
- **Server and agent**: the two roles k3s can run. A server runs the full control plane
  and can also run Pods: the brain who also works. An agent only runs the node parts
  (kubelet, container runtime, flannel) and joins a server as a worker.
- **Token**: a shared secret the k3s server generates. An agent must present it to be
  allowed to join the cluster. The password for joining the team.
- **Flannel**: the program that connects Pods across machines. It gives each machine its
  own range of Pod addresses, and carries messages between Pods on different machines
  over `eth1`. It's k3s's CNI plugin (Container Network Interface, the standard way to
  plug a Pod network into Kubernetes). The line between two offices, so employees in
  different offices can call each other.

**The idea.** To join, the worker needs two things: **where** the brain is (its URL) and
**proof** it's allowed in (the token). Once joined, each node gets its own block of
addresses for its apps: everything on the server starts with `10.42.0.`, everything on
the worker with `10.42.1.`, like each office having its own number prefix. Flannel
builds a tunnel between the machines, so apps on different machines can talk as if they
were side by side.

```
   lab-server   apps get 10.42.0.x  ┐
                                    ├── flannel tunnel over eth1 (192.168.56.x)
   lab-worker   apps get 10.42.1.x  ┘
```

**Read it.** On the server, show the token:

```bash
server$ sudo cat /var/lib/rancher/k3s/server/node-token
```

Copy the whole line. In a second terminal, on the worker:

```bash
mac$ vagrant ssh lab-worker
worker$ curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.37.1+k3s1" \
  K3S_URL="https://192.168.56.120:6443" K3S_TOKEN="<paste-the-token>" \
  INSTALL_K3S_EXEC="--node-ip=192.168.56.121 --flannel-iface=eth1" sh -
```

- `K3S_URL` — where the brain is: `https://` for a secure web request, the server's
  address, and `:6443`, the API server's port. Setting it is what makes the installer
  set up an agent instead of a second server.
- `K3S_TOKEN` — the proof of membership.
- `--node-ip`, `--flannel-iface` — same meaning as on the server.

**Predict.** After joining, will the worker have its own brain (API server)?

**Do it.** Run the install, then watch from the server:

```bash
server$ kubectl get nodes -o wide -w        # Ctrl-C to stop watching
```

**What happened.** The agent knocked on `https://192.168.56.120:6443`, showed the token,
and got its certificates. Its kubelet registered the node. The brain gave the node a block
of app IPs, and flannel built the tunnel over `eth1`.

**Look under the hood.**

```bash
server$ kubectl get nodes -o custom-columns=NAME:.metadata.name,POD-IPS:.spec.podCIDR
worker$ pgrep -a k3s
worker$ ip -d link show flannel.1 | grep vxlan
```

- Each node owns a block: `10.42.0.0/24` (server), `10.42.1.0/24` (worker). `/24` means
  "every address that starts with the first three numbers", so `10.42.1.0/24` is
  `10.42.1.0` to `10.42.1.255`. An app's address tells you which machine it's on.
- The worker runs `k3s agent`: kubelet, containerd, flannel. No API server, no datastore.
- `flannel.1` is the tunnel, a network card that exists only in software. Its line
  contains `vxlan`, the name of the wrapping method, and `local 192.168.56.121 dev eth1`:
  a message for a Pod on the other machine is wrapped inside an ordinary message between
  the two VMs, sent across `eth1`, and unwrapped on the other side.

**Experiment (a thought experiment).** What if you had used `--flannel-iface=eth0`? The
tunnel would go out through the NAT card, which can't reach the other VM (section 1).
Apps on the same machine would still work; apps on different machines couldn't talk.

**Check your understanding.**

<details><summary>An app has IP 10.42.1.7. Which machine is it on?</summary>

`lab-worker`, because `10.42.1.0/24` is the worker's block.
</details>

<details><summary>What would happen with a wrong token?</summary>

The server rejects the agent. The node never appears in `kubectl get nodes`, and the
worker's log (`sudo journalctl -u k3s-agent`) shows the authentication error.
</details>

**Connect the dots.**
[k8s/k3s Reference: Server and agent roles](k8s-k3s-refresher.md#server-and-agent-roles).

**Checkpoint.** Two nodes `Ready`: `lab-server` (`control-plane`) and `lab-worker`
(`<none>`), with INTERNAL-IPs `.120` and `.121`.

## 4. Optional: kubectl from the Mac

**Coming back?** This section starts with a two-node cluster.

```bash
server$ kubectl get nodes
```

You should see `lab-server` and `lab-worker`, both `Ready`. If the worker is missing,
redo the join in section 3.

**Why.** In real life you don't log into a cluster's machines to manage it. You run
`kubectl` on your own computer, and it talks to the cluster over the network.

**New words.**
- **kubeconfig**: a YAML file with three parts: the cluster's address and certificate,
  your login credentials, and which pair is active. kubectl reads it on every command to
  know where to connect. kubectl's address book and keys.

**The idea.** `kubectl` is only a messenger: every command becomes a web request (HTTPS)
to the API server. To send it, kubectl reads a kubeconfig file with three parts:

```
   clusters:   where is the API server?        server: https://192.168.56.120:6443
               and how do I trust it?          certificate-authority-data: ...
   users:      who am I?                       client-certificate-data / key-data
   contexts:   which user for which cluster?   + current-context: the one in use
```

**Do it.**

```bash
mac$ brew install kubectl
mac$ vagrant ssh lab-server -c "cat /etc/rancher/k3s/k3s.yaml" > kubeconfig
mac$ sed -i '' 's/127.0.0.1/192.168.56.120/' kubeconfig
mac$ export KUBECONFIG=$PWD/kubeconfig
mac$ kubectl get nodes
```

- The file k3s wrote says `server: https://127.0.0.1:6443`. `127.0.0.1` means "this same
  machine": right on the server, but on the Mac it means the Mac, where no API server
  runs. So `sed` swaps in `192.168.56.120`.
- `export KUBECONFIG=…` tells kubectl which file to use, **for this terminal only**.

**Look under the hood.**

```bash
mac$ kubectl config view --minify          # the parts in use (secrets hidden)
mac$ kubectl get nodes -v=6 2>&1 | grep "api/v1/nodes"
```

The second command shows the real request. Look for
`verb="GET" url="https://192.168.56.120:6443/api/v1/nodes?limit=500"` and
`status="200 OK"`: kubectl asked the API server for the list of nodes, and the server
said yes. Every kubectl command is a request like this.

**A common error.** In a new terminal you may see:

```
The connection to the server localhost:8080 was refused
```

That means kubectl didn't find your kubeconfig and fell back to an old default
address: port 8080 on this same machine. "Refused" means nothing listens on that port,
like an extension nobody answers. The cluster is fine: run the `export` again in that terminal. (If you don't use
any other cluster, you can copy the file to `~/.kube/config`, kubectl's default location,
so every terminal finds it.)

**Check your understanding.**

<details><summary>k3s wrote 127.0.0.1 into the file. Why is 192.168.56.120 accepted?</summary>

Because of `--tls-san=192.168.56.120` in section 2: that IP was added to the server's
certificate, so connecting to it is trusted.
</details>

**Checkpoint.** `kubectl get nodes` on the Mac shows both nodes. From now on, commands
work from the Mac or from `server$`. From the Mac, write `manifests/…` instead of
`/vagrant/manifests/…`.

## 5. Your first Pod

**Coming back?** This section starts with a two-node cluster. Section 4 is optional, so it doesn't matter
whether you did it.

```bash
server$ kubectl get nodes
```

You should see `lab-server` and `lab-worker`, both `Ready`. If the worker is missing,
redo the join in section 3.

**Why.** Everything in Kubernetes ends with a container running somewhere. The Pod is the
object that says "run this container".

**New words.**
- **Pod**: the smallest deployable unit in Kubernetes: one or more containers that share
  one IP address and are always scheduled together on the same machine. A small box
  around your container. Kubernetes never runs a bare container, only Pods.
- **spec**: the part of an object's definition that you write: the desired state, what
  you want.
- **status**: the part Kubernetes writes back: the observed state, what actually is.

**The idea.** A Pod is a little wrapper around your container. If a Pod has several
containers, they share its IP and can talk over `localhost`, like programs on one
computer. Kubernetes never runs a bare container; it always runs Pods.

Every object has two halves, and this is the declarative idea in miniature:

```
   spec    what you want      ← written by you
   status  what actually is   ← written by Kubernetes
```

**Predict.** You'll create a Pod, then delete it. Will it come back on its own?

**Do it.**

```bash
server$ kubectl run hello --image=nginx:1.27-alpine
server$ kubectl get pods -o wide
```

**What happened.** A relay race, each component doing one job:

```
 kubectl ──> API server ──> datastore      Pod saved, no machine yet (Pending)
                 │
             scheduler                     picks a machine, writes it on the Pod
                 │
             kubelet on that machine       notices a Pod assigned to it
                 │
             containerd                    downloads the image, starts the container
             flannel                       gives the Pod an IP from the machine's block
                 │
             kubelet ──> API server        reports back: Running
```

**Look under the hood.** See both halves of your Pod:

```bash
server$ kubectl get pod hello -o yaml | less
```

Scroll: `spec` is what you asked for (the image); `status` is what happened (the machine,
the IP, `Running`). Press `q` to quit. Then:

```bash
server$ kubectl get events --sort-by=.metadata.creationTimestamp | tail -6
server$ sudo crictl ps | grep hello
```

Run `crictl` on the machine in the Pod's NODE column. If it says `lab-worker`, run it in
`vagrant ssh lab-worker` instead.

The events follow the relay: `Scheduled`, `Pulling`, `Pulled`, `Created`, `Started`. And
`crictl` shows the real container on the machine.

Use the Pod a bit:

```bash
server$ kubectl logs hello
server$ kubectl exec -it hello -- sh
/ # wget -qO- localhost | head -4
/ # exit
```

Now delete it:

```bash
server$ kubectl delete pod hello
server$ kubectl get pods
```

Gone for good. You only described "a Pod", not "keep a Pod running", so nobody is in charge
of bringing it back.

**Check your understanding.**

<details><summary>Which component decided which machine runs the Pod?</summary>

The scheduler. The kubelet only runs Pods that have already been assigned to its machine.
</details>

<details><summary>In the YAML, which half did you write and which did Kubernetes write?</summary>

You wrote `spec` (through `kubectl run`). Kubernetes wrote `status`.
</details>

**Connect the dots.** [k8s/k3s Reference: Pod](k8s-k3s-refresher.md#pod) and
[2. The declarative model](k8s-k3s-refresher.md#2-the-declarative-model).

**Checkpoint.** You can find a Pod's machine and IP, read its events, and explain why it
didn't come back.

## 6. Deployments and self-healing

**Coming back?** This section starts with an empty cluster: two nodes and no apps.

```bash
server$ kubectl get nodes
server$ kubectl get pods
```

Both nodes `Ready`, and `No resources found` for Pods. If `hello` from section 5 is
still there, remove it with `kubectl delete pod hello`.

**Why.** Section 5 left a problem: a Pod that dies stays dead. In the real world, apps
crash and machines fail. You need something that notices and replaces them.

**New words.**
- **Deployment**: a Kubernetes object that declares a desired number of identical Pods
  (from one template) and manages the ReplicaSets that keep them running and roll out
  new versions. In plain words, a standing order: "always keep 3 Pods like this
  running, and update them safely."
- **ReplicaSet**: an object that keeps exactly N Pods matching its selector running at
  all times. A Deployment creates one per version. It's the counter that does the
  actual counting.
- **Label**: a `key: value` pair attached to an object's metadata, used to identify and
  group objects. A name tag, like `app: web`, so you can find and group things later
  instead of by name.
- **Selector**: a query that matches objects by their labels. Deployments, ReplicaSets
  and Services all use one to decide which Pods are theirs: "everyone with `app: web`."

**The idea.** A Deployment doesn't count Pods itself. It creates a ReplicaSet, and the
ReplicaSet counts. *Which* Pods count is decided by **labels**: the ReplicaSet looks for
Pods tagged `app: web`. Labels and selectors are the glue of Kubernetes; you'll see them
again in section 7.

```
   Deployment web  ──creates──>  ReplicaSet web-abc12  ──creates──>  Pod  app=web
   (the standing order)          (the counter: "3 Pods             Pod  app=web
                                  with app=web")                   Pod  app=web
```

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/web.yaml`:

```yaml
apiVersion: apps/v1              # which API this object belongs to
kind: Deployment                 # what kind of object it is
metadata:
  name: web                      # its name
spec:
  replicas: 3                    # how many Pods you want
  selector:
    matchLabels:
      app: web                   # "Pods labelled app=web are mine"
  template:                      # the blueprint for each Pod
    metadata:
      labels:
        app: web                 # each new Pod gets this label (must match the selector)
    spec:
      containers:
        - name: nginx            # container name inside the Pod
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80  # for information: nginx listens on 80
          lifecycle:
            postStart:           # runs right after the container starts
              exec:
                command: ["/bin/sh", "-c", "echo \"served by $(hostname)\" > /usr/share/nginx/html/index.html"]
```

The `postStart` part is only a learning aid: it writes the Pod's name into its web page,
so in section 7 you can see *which* Pod answered you.

**Predict.** If you delete one of the three Pods, how many will exist ten seconds later?
Will the new one have the same name?

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml
server$ kubectl get deploy,rs,pods -o wide --show-labels
```

**What happened.** You saved one object. Then a chain reaction: the Deployment controller
created a ReplicaSet; the ReplicaSet controller created three Pods; the scheduler spread
them across both machines (the end of this section keeps them off the server). Pod names
look like `web-<ReplicaSet id>-<random>`.

**Look under the hood.** Follow the chain of ownership upward:

```bash
server$ kubectl get pod <a-web-pod> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
server$ kubectl get rs <the-web-rs> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

Pod → owned by a ReplicaSet → owned by the Deployment. Now watch self-healing. In a second
terminal:

```bash
server$ kubectl get pods -w
```

In the first:

```bash
server$ kubectl delete pod <a-web-pod>
```

A new Pod, with a new name, appears within seconds: the ReplicaSet saw 2 where 3 were
wanted. Scaling uses the same mechanism, with a new number:

```bash
server$ kubectl scale deployment web --replicas=5
server$ kubectl scale deployment web --replicas=3
server$ kubectl describe deployment web | tail -5
```

The last lines are events like `Scaled up replica set web-…` and
`Scaled down replica set web-…`. The Deployment only changed the ReplicaSet's number,
and the ReplicaSet did the rest.

**Experiment: labels decide everything.** Take the label off one Pod:

```bash
server$ kubectl label pod <a-web-pod> app-
server$ kubectl get pods --show-labels
```

Now there are **four** Pods! The ReplicaSet stopped counting the unlabelled one, so it
made a replacement. The unlabelled Pod keeps running as an orphan nobody looks after.
Delete it yourself: `kubectl delete pod <that-pod>`.

**A good habit.** Instead of `kubectl scale`, change `replicas:` in `web.yaml` and run
`kubectl apply -f` again. That way the file always tells the truth about what should run.

**New words: where Pods run.**
- **Taint**: a "keep out" mark on a node. The scheduler won't place a Pod there unless
  the Pod carries a matching toleration. A "staff only" sign on a door.
- **Toleration**: a line in a Pod's spec that lets it ignore one taint. The staff badge
  for that door.
- **nodeSelector**: a line in a Pod's spec that says "only run on nodes with this
  label". A reserved seat with your name on it.

**Keep apps off the server.** Look at the NODE column of `kubectl get pods -o wide`: some
`web` Pods probably run on `lab-server`. k3s allows that by default. But the server also
runs the brain, and an app that eats all the memory would slow down the whole cluster,
so real clusters usually keep apps off the brain's machine. Do the same with a taint:

```bash
server$ kubectl taint nodes lab-server node-role.kubernetes.io/control-plane=true:NoSchedule
server$ kubectl rollout restart deployment web
server$ kubectl get pods -o wide
```

- `NoSchedule` means "no new Pods here". It doesn't touch Pods already running, so
  `rollout restart` replaces them, and the scheduler can only put the new ones on
  `lab-worker`.
- The name `lab-worker` comes from `vm.hostname` in your Vagrantfile. k3s read the VM's
  hostname when it joined (section 3), named the node after it, and added the label
  `kubernetes.io/hostname=lab-worker`.
- The k3s extras in `kube-system` (CoreDNS, Traefik and others) keep running on the
  server, because they carry a toleration for exactly this taint. See it:

```bash
server$ kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.template.spec.tolerations}{"\n"}'
```

  The list includes `node-role.kubernetes.io/control-plane`. That's why this lab uses
  that standard name instead of inventing one.
- The taint is saved in the cluster, so it survives reboots. From now on every app you
  create runs on `lab-worker`. Its 1 GB of memory is plenty for this lab.
- To remove it, run the same `taint` command with a `-` at the end.

**Experiment: pin a Pod to a machine.** A `nodeSelector` picks machines by label. Ask for
the server on purpose. Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/pinned.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pinned
spec:
  nodeSelector:
    kubernetes.io/hostname: lab-server   # only the machine with this label
  containers:
    - name: nginx
      image: nginx:1.27-alpine
```

Guess what happens before you apply it:

```bash
server$ kubectl apply -f /vagrant/manifests/pinned.yaml
server$ kubectl get pod pinned -o wide
server$ kubectl describe pod pinned | tail -3
```

It stays `Pending`. The `FailedScheduling` event gives one reason per machine: the
server has a taint the Pod doesn't tolerate, and the worker doesn't match the selector.
No machine fits, so the Pod waits forever. Clean up:

```bash
server$ kubectl delete -f /vagrant/manifests/pinned.yaml
mac$ rm manifests/pinned.yaml
```

In a Deployment, `nodeSelector` goes in the Pod template, next to `containers:`
(`spec.template.spec.nodeSelector`), because it's a rule for each Pod.

**Check your understanding.**

<details><summary>Who replaced the deleted Pod: the Deployment or the ReplicaSet?</summary>

The ReplicaSet. The Deployment manages ReplicaSets (and versions, in section 9); the
ReplicaSet keeps the count.
</details>

<details><summary>Why did removing a label create a fourth Pod?</summary>

The ReplicaSet counts Pods by label (`app=web`). The unlabelled Pod no longer matched, so
the count dropped to 2 and it made one more. Kubernetes never tracks Pods by name; it
always picks them by labels.
</details>

<details><summary>How does Kubernetes know a node is called lab-worker?</summary>

From the VM's hostname, set by `vm.hostname` in the Vagrantfile. k3s read it when the
node joined, named the node after it, and added the label
`kubernetes.io/hostname=lab-worker`. The VirtualBox name plays no part.
</details>

<details><summary>After the taint, why do CoreDNS and Traefik still run on the server?</summary>

They carry a toleration for `node-role.kubernetes.io/control-plane`. A taint only keeps
out the Pods that don't tolerate it.
</details>

**Connect the dots.**
[k8s/k3s Reference: Deployment](k8s-k3s-refresher.md#deployment) and
[4. Core objects](k8s-k3s-refresher.md#4-core-objects).

**Checkpoint.** After deleting a Pod there are still 3, and you can explain who replaced
it and how it knew which Pods to count. All three `web` Pods run on `lab-worker`.

## 7. Services and cluster DNS

**Coming back?** This section starts with the `web` Deployment from section 6.

```bash
server$ kubectl get deploy web
```

You should see `READY 3/3`. If it's missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml
```

**Why.** Your app runs as 3 Pods, and each Pod has its own address. Section 6 showed that
Pods get replaced all the time, and every replacement gets a new address. Anything that
wants to talk to your app can't keep up. This section gives your app one address and one
name that never change.

**New words: networking basics.** You met these three in section 0. Here they are again,
because this section is built on them.
- **IP address**: a number that identifies one machine, or one Pod, on a network, like
  `192.168.56.120`. It says where data should go. A phone number.
- **Port**: a number that picks one program on a machine, because one machine runs many
  programs. Web servers usually listen on port 80. An extension: one phone number, many
  extensions, and each program answers its own.
- **DNS**: the system that turns a name into an IP address, so you can type `web` instead
  of `10.43.85.12`. The contacts app on your phone: you tap a name, it dials the number.

To reach a program you need both numbers: the address **and** the port, written
`address:port`, like `10.42.1.5:80`. You already did this in section 3: the worker joined
`192.168.56.120:6443`, the API server's port on the server. A name works too:
`http://web` means "look up the address of `web`, then connect to port 80". The `http`
part picks 80, because that's the usual port for web pages.

Three kinds of address show up in this lab. The first numbers tell you which kind you're
looking at:

| Starts with | Belongs to | Reachable from |
| --- | --- | --- |
| `192.168.56.` | your two VMs | the Mac, VMs, Pods |
| `10.42.` | each Pod | VMs and Pods only |
| `10.43.` | each Service | VMs and Pods only |

**New words: Services.**
- **Service**: a Kubernetes object that gives a group of Pods one address and one name
  that never change, and spreads requests across those Pods. It picks its Pods with a
  selector, like `app=web`, the same label glue as in section 6. The company's main
  number.
- **ClusterIP**: the default type of Service, and the name of the `10.43.…` address it
  gets. No machine has that address, and it only works inside the cluster. An internal
  number that only works from phones inside the company.
- **EndpointSlice**: a list, kept up to date automatically, of the Pods behind a Service:
  their addresses and whether each one is ready. Requests only go to ready Pods. The list
  of who's at their desk today, with a "free now" mark next to each name.
- **CoreDNS**: the cluster's own DNS server. It answers names like `web` with the
  Service's address. The building's contacts directory.
- **kube-proxy**: a program on every machine that sends traffic for a Service's address
  to one of its Pods. Call forwarding: no phone rings at the main number itself, every
  call is passed on to one of the employees.

**The idea.** A Service is your app's main phone number. The employees behind it, the
Pods, come and go, and each new one gets a new personal number. Callers never need those:
they dial the main number, and the call goes to whoever is free.

```
   caller  ──>  Service "web"   10.43.x.x   never changes
                     │  picks the Pods labelled app=web
            ┌────────┼────────┐
            v        v        v
          Pod      Pod      Pod      10.42.x.x   new address each time a Pod is replaced
```

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/web-svc.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web              # also becomes the DNS name "web"
spec:
  selector:
    app: web             # send traffic to Pods labelled app=web
  ports:
    - port: 80           # the port callers use on the Service
      targetPort: 80     # the port the Pods listen on
```

`port` is the extension callers dial on the main number. `targetPort` is the extension
that rings on each Pod. They can differ: `port: 8080` with `targetPort: 80` means "callers
use 8080, the Pods get the call on 80". There's no `type:` line, so this is the default
type, `ClusterIP`: it works **only from inside the cluster**.

**Predict.** First see the problem. Note a Pod's address in the IP column (it starts with
`10.42.`), delete that Pod, and compare:

```bash
server$ kubectl get pods -o wide
server$ kubectl delete pod <a-web-pod>
server$ kubectl get pods -o wide
```

The replacement has a different address. Now guess: once you create the Service, will
*its* address change when Pods are replaced?

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/web-svc.yaml
server$ kubectl get svc web
server$ kubectl get endpointslices -l kubernetes.io/service-name=web
```

`get svc` shows the Service's address under CLUSTER-IP, starting with `10.43.`, and
`80/TCP` under PORT(S): port 80. TCP is the kind of connection web requests use. The
EndpointSlice line lists the three Pod addresses, starting with `10.42.`. Delete a Pod
again and run both commands once more: the Pod addresses change, the CLUSTER-IP doesn't.

**What happened.** Four components each did one part:

1. The API server gave the Service an address from the `10.43.` range. No machine has it.
2. A controller wrote the **EndpointSlice**: the addresses of the Pods labelled
   `app=web`, each marked ready or not. It updates the list whenever Pods come and go.
3. kube-proxy, on every machine, turned that list into forwarding rules (Linux rules
   called iptables): "traffic for the Service's address on port 80 goes to one of these
   Pods".
4. CoreDNS started answering the name `web` with the Service's address.

Now follow one request from start to finish. This is the whole section in one picture:

```
  a Pod runs:  wget http://web
      │
      │ 1. asks CoreDNS: "what's the address of web?"
      │    answer: 10.43.85.12, the Service's address
      v
      │ 2. sends the request to 10.43.85.12, port 80
      v
  kube-proxy's rules on that machine
      │ 3. "10.43.85.12:80 means one of these Pods" (the EndpointSlice list)
      │    picks one, for example 10.42.1.5, port 80
      v
  one web Pod (nginx, port 80)  ──>  answers "served by web-…"
```

In phone terms: you tap a name, the contacts app finds the main number, and call
forwarding passes you to someone who's free.

**Look under the hood.** Watch those three steps happen. Start a throwaway Pod inside the
cluster, because Service addresses only work in there:

```bash
server$ kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
/ # nslookup web
/ # cat /etc/resolv.conf
/ # for i in 1 2 3 4 5 6; do wget -qO- http://web; done
/ # ping -c 2 -W 2 web
/ # exit
```

- `nslookup web` is step 1: it asks DNS for the address of `web`. At the top,
  `Server: 10.43.0.10` is CoreDNS, and `:53` after it is its port, because DNS servers
  listen on port 53. At the bottom, `Name: web.default.svc.cluster.local` and the
  address: the same CLUSTER-IP as in `kubectl get svc web`.
- Ignore the `can't find … NXDOMAIN` lines. They mean "no such name". busybox tries a few
  longer spellings of `web`, and only one of them exists.
- The full name reads from left to right: `web` (the Service) . `default` (its
  namespace, section 13) . `svc` (it's a Service) . `cluster.local` (this cluster). The
  short `web` is enough from Pods in the same namespace.
- `resolv.conf` is the Pod's DNS settings. `nameserver 10.43.0.10` tells it which DNS
  server to ask. The `search` line lists the endings it may add to a short name, which is
  why `web` alone works.
- The `wget` loop is steps 2 and 3, six times. The `served by` names change: kube-proxy's
  rules sent each request to a different Pod.
- `ping` gets no answer, even though `wget` works. The questions below explain why.

**Experiment: a Service with nobody behind it.**

```bash
server$ kubectl scale deployment web --replicas=0
server$ kubectl get endpointslices -l kubernetes.io/service-name=web
server$ kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 3 http://web
server$ kubectl scale deployment web --replicas=3
```

With zero Pods, the Service still exists and `web` still has an address, but the list is
empty (ENDPOINTS shows `<unset>`), so the request fails. A main number
with nobody at work: the number works, but nobody picks up.

**Experiment: a private line to the Service.** In one server terminal:

```bash
server$ kubectl port-forward svc/web 8888:80
```

Open a second terminal with `vagrant ssh lab-server`, then:

```bash
server$ curl -s localhost:8888
```

`localhost` means "this same machine". You get `served by web-…`: kubectl listens on
port 8888 on this VM and carries everything, through the API server, to port 80 of the
Service. Run the `curl` three or four times: every answer names the same Pod, because
port-forward picks one Pod and stays on it. Compare with the `wget` loop above, where the
names changed. The line stays open as long as the command runs. Press Ctrl-C in the first
terminal to close it.

It's for testing, not for users: section 8 shows how users get in. In p3 you'll use it
to open the app on port 8888.

**Check your understanding.**

<details><summary>What two things does a request need to reach a program on another machine?</summary>

The machine's IP address and the program's port, written `address:port`. With a name
like `http://web`, DNS supplies the address and `http` means port 80.
</details>

<details><summary>Another app needs to call yours. Should it use a Pod address (10.42.…) or the Service (web)?</summary>

The Service. A Pod's address changes every time the Pod is replaced. The Service's name
and address stay the same for as long as the Service exists.
</details>

<details><summary>Why did `ping` get no answer from the Service while `wget` worked?</summary>

`ping` asks "is there a machine at this address?". No machine has the Service's address:
it's only a forwarding rule for port 80, so nothing answers. Call forwarding has no phone
of its own. `wget` uses port 80, so the
rule forwards it to a Pod.
</details>

<details><summary>How does the Service know where to send traffic?</summary>

Its selector (`app=web`). A controller lists the matching Pods in the EndpointSlice,
each marked ready or not, and kube-proxy forwards only to the ready ones.
</details>

<details><summary>Can you reach the Service's address from the Mac?</summary>

No. `10.43.` addresses only work inside the cluster. That's what section 8 solves.
</details>

**Connect the dots.** [k8s/k3s Reference: Service](k8s-k3s-refresher.md#service).

**Checkpoint.** From the tmp Pod, `wget http://web` returns different `served by` names,
and you can tell the three steps of one request: name to Service address, Service address
to Pod, Pod answers.

## 8. Ingress: reach the app from the Mac

**Coming back?** This section starts with the `web` Deployment and its Service.

```bash
server$ kubectl get deploy,svc web
```

You should see `deployment.apps/web` at `3/3` and `service/web`. If either is missing,
catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml
```

**Why.** Your app works inside the cluster, but your users are outside it. Prove it:

```bash
server$ kubectl get svc web                                  # note the CLUSTER-IP
mac$ curl --max-time 3 http://<cluster-ip>/
```

The `curl` from the Mac times out: `10.43.` addresses only work inside the cluster (the
table in section 7). An internal number can't be dialled from outside the company.

**New words.**
- **Ingress**: an object holding rules that send web requests to Services by website
  name: "requests for `web.lab` go to the Service `web`." On its own it does nothing:
  it's stored data, not a running program. The operator's transfer list.
- **Ingress controller**: the program that answers web requests from outside, reads the
  Ingress rules and passes each request to the right Service. k3s ships one called
  Traefik. The operator who answers the company's public number.
- **Host header**: a line inside every web request that names the website it's for, like
  `Host: web.lab`. It lets many websites share one address and one port. The name you
  ask for when the operator picks up.
- **NodePort**: a Service type that opens the same port, a number from 30000 to 32767, on
  every machine, and passes it to the Service. A direct outside extension with an odd
  number, on every machine.
- **LoadBalancer**: a Service type that gives the Service its own address reachable from
  outside, normally provided by a cloud company. In k3s, small `svclb` Pods play that
  role. A public phone number of its own.
- **DaemonSet**: an object that keeps exactly one copy of a Pod running on every node.
  When a node joins the cluster, it gets its copy too. The `svclb` Pods come from one.
  A Deployment says "3 Pods, anywhere". A DaemonSet says "one Pod on each machine".

**The idea, part 1: three ways in.** Kubernetes has three ways to let outside traffic
reach a Service:

```
   NodePort       http://192.168.56.120:31234     an odd extension per app
   LoadBalancer   http://<its own address>/       a public number per app
   Ingress        http://web.lab/                 ONE public number for every app,
                  http://site.lab/                sorted by website name
```

Ingress is what real websites use: one public number, many sites.

**The idea, part 2: the rules and the program that follows them.** An Ingress has two
pieces:

- the **Ingress object**: rules stored in the cluster ("`web.lab` goes to Service
  `web`"). On its own it does nothing at all.
- the **ingress controller**: a real program that reads every Ingress object and forwards
  each request to the right place. In k3s that program is **Traefik**, running since
  section 2.

In phone terms: the company has one public number. Traefik is the operator who answers
it, asks who you want, and transfers you. The Ingress objects are the operator's transfer
list. The Services are the team numbers from section 7.

**The idea, part 3: the Host header.** All your apps share the same address
(`192.168.56.120`, port 80). So how does Traefik know which site you want? Every web
request carries a line naming the site:

```
   GET / HTTP/1.1
   Host: web.lab          <-- Traefik decides based on this line
```

It's the name you ask for when the operator picks up. A browser fills it in from the
address bar. Your Mac can't look up `web.lab`, because no DNS knows that name. So with
`curl` you connect to the address yourself and add the line: `-H "Host: web.lab"`.
That's exactly the request a browser would send.

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/web-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
spec:
  ingressClassName: traefik      # which ingress controller should apply these rules
  rules:
    - host: web.lab              # requests whose Host header is web.lab ...
      http:
        paths:
          - path: /              # ... and whose URL path starts with / ...
            pathType: Prefix     # ("starts with"; Exact would mean exactly /)
            backend:             # ... go here:
              service:
                name: web        # the Service from section 7
                port:
                  number: 80     # the Service's port
```

Notice that the Ingress points at the **Service**, never at Pods. Each object only knows
the layer right below it:

```
   Ingress ──(by name)──> Service ──(by label)──> Pods
```

**Predict.** Before running anything, guess these three:
1. `curl -H "Host: web.lab" http://192.168.56.120/` — what comes back?
2. The same to `192.168.56.121` (the worker) — does it work too?
3. `curl http://192.168.56.120/` with no `-H` — what comes back?

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/web-ingress.yaml
server$ kubectl get ingress
mac$ curl -H "Host: web.lab" http://192.168.56.120/
mac$ curl -H "Host: web.lab" http://192.168.56.121/
mac$ curl http://192.168.56.120/
```

**What happened.** Your request's whole journey:

```
 Mac
  │  connects to 192.168.56.120, port 80, says "Host: web.lab"
  v
 svclb Pod on that machine     passes port 80 on to Traefik
  v
 Traefik Pod     10.42.x.x     reads "Host: web.lab", finds your rule
  v
 Service web     10.43.x.x     forwards to one ready Pod (section 7)
  v
 web Pod         10.42.x.x     nginx answers "served by web-..."
```

Look at the addresses along the way. The request enters on a VM's address
(`192.168.56.`), the only kind the Mac can reach. Only then does it move to the inside
addresses, `10.42.` and `10.43.`.

The answers to your guesses:
1. `served by web-…`: the rule matched.
2. Yes. Traefik's Service is type `LoadBalancer`, and k3s makes that work by running a
   tiny `svclb` Pod on **every** machine, passing port 80 to Traefik. Any machine's
   address works.
3. `404 page not found`. Without `-H`, curl sends `Host: 192.168.56.120`, which matches
   no rule, so Traefik itself replies "no such site": the operator picked up and said
   nobody by that name works here. The line works, the transfer list just has no entry.
   Nothing is broken.

**Look under the hood.** See the Host line being sent:

```bash
mac$ curl -v -H "Host: web.lab" http://192.168.56.120/ 2>&1 | grep "^>"
mac$ curl -v http://192.168.56.120/ 2>&1 | grep "^>"
```

Lines starting with `>` are your request. The second shows `Host: 192.168.56.120`, which
is why it gets a 404.

Now meet the lines and the operator:

```bash
server$ kubectl get svc -n kube-system traefik
server$ kubectl get pods -n kube-system -o wide | grep -E "svclb|traefik"
server$ kubectl get daemonsets -n kube-system
server$ kubectl describe ingress web
```

- The `traefik` Service is type `LoadBalancer`, with both machine addresses as
  EXTERNAL-IP: the addresses outside callers use.
- One `svclb-traefik` Pod per machine, passing that machine's port 80 to Traefik, and one
  `traefik` Pod, the operator.
- The svclb Pods come from a DaemonSet named `svclb-traefik-…`. DESIRED is `2` because
  you have two machines. Add a third machine and it gets one too.
- `describe ingress` shows your rule and, under Backends, the Pod addresses it leads to.

**Experiment 1: try the NodePort way in.**

```bash
server$ kubectl expose deployment web --type=NodePort --name=web-np --port=80
server$ kubectl get svc web-np                # note the port after 80:, e.g. 80:31234/TCP
mac$ curl http://192.168.56.120:<that-port>/
server$ kubectl delete svc web-np
```

`80:31234/TCP` means the Service's port 80 is also open as port 31234 on every machine.
It works with no Host header, but you get a random high port, and every app would need its
own. Now you know why Ingress exists.

**Experiment 2: add a second website name.** Add this rule to `web-ingress.yaml`, lined up
with the first `- host:`:

```yaml
    - host: www.web.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

Apply it, then try `curl -H "Host: www.web.lab" http://192.168.56.120/` and
`curl -H "Host: other.lab" http://192.168.56.120/`. The first is routed. The second gets
404. You added a name to the operator's transfer list.

**Experiment 3: a default site.** So far, a name with no rule gets a 404. A rule with no
`host:` catches those requests instead. Add this rule to `web-ingress.yaml`, lined up
with the other `- host:` entries:

```yaml
    - http:                      # no host: catches every request no other rule matched
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

Apply it, then try the two requests that got 404 before:

```bash
server$ kubectl apply -f /vagrant/manifests/web-ingress.yaml
mac$ curl http://192.168.56.120/
mac$ curl -H "Host: other.lab" http://192.168.56.120/
```

Both now answer `served by`. Traefik tries the rules with a host first, because they're
more specific, and the hostless rule catches everything else. The operator's list now
ends with a "for anyone else" line. This is how p2 makes app3 the
default site.

Remove this rule and apply again before you go on: section 14 needs the 404 back.

**Optional: use a real browser.** `/etc/hosts` is the Mac's own small contacts list,
checked before DNS. Tell your Mac that these names mean the server's address by adding
this line to it (`sudo nano /etc/hosts`):

```
192.168.56.120  web.lab www.web.lab site.lab
```

Open `http://web.lab` in a browser. Now the browser sends `Host: web.lab` by itself,
which is what `-H` was doing. Remove the line when you finish the lab.

**Check your understanding.**

<details><summary>If Traefik were deleted, would your Ingress object still exist? Would it work?</summary>

It would still exist (it's data), but nothing would work: no program would be reading
the rules and forwarding traffic. (k3s would bring Traefik back from its add-on files.)
</details>

<details><summary>Why does an Ingress point at a Service instead of directly at Pods?</summary>

Pods come and go with new addresses; the Service's name and address stay the same
(section 7). The Ingress only needs the Service's name.
</details>

<details><summary>Two sites, a.lab and b.lab, use the same IP and port. How does Traefik tell them apart?</summary>

By the `Host` line of each request. IP and port are the same for every site; the Host
line is the only difference.
</details>

<details><summary>Why did curl without -H get a 404, and who sent it?</summary>

curl sent `Host: 192.168.56.120`. No rule has that host, so Traefik answered 404 itself.
Your Service and Pods were never involved.
</details>

**Connect the dots.**
[k8s/k3s Reference: Ingress](k8s-k3s-refresher.md#ingress) and the
[5. Request flow](k8s-k3s-refresher.md#5-request-flow) diagram, which you've now traced
hop by hop.

**Checkpoint.** You can draw a request's path from the Mac to a Pod, name the component at
each hop, and explain why the Host line decides where it goes.

## Side quest: How Kubernetes is built

**Coming back?** This side quest needs a running cluster.

```bash
server$ kubectl get nodes
```

Both nodes `Ready`? Then you're set. If the worker is missing, redo the join in section 3.

**Why.** By now you've met every part of Kubernetes once, spread over sections 2 to 8.
Here they sit together, one part per step: what it is, what it does, and how the parts
cooperate. "Explain the architecture" is also the question you're most likely to get at
the defense.

**New words.**
- **Watch**: a long-running request in which a component asks the API server to tell it
  every time an object of some kind changes. It's how each part learns about new work
  without anyone giving it orders.
- **Add-on**: an extra program that runs as ordinary Pods inside the cluster and adds a
  feature, such as DNS or web routing.

**The idea.** A cluster has two halves. The **control plane** is the brain: it stores
what you want and decides what should happen. The **nodes** are the hands: they run your
containers. Each half has four parts.

```
you ── kubectl ── HTTPS :6443 ──┐
┌───────────────────────────────▼────────────────────────────────────┐
│ CONTROL PLANE · the brain · on lab-server                          │
│                                                                    │
│     scheduler            API server           controller manager   │
│   "which node?"  ◄──►  the only door  ◄──►  "fix the difference"   │
│                               ▲                                    │
│                               ▼                                    │
│                           datastore                                │
│                        (SQLite in k3s)                             │
└───────────────────────────────┬────────────────────────────────────┘
                                │  every node watches the API server
                ┌───────────────┴───────────────┐
                ▼                               ▼
 ┌─ NODE · lab-server ────────┐  ┌─ NODE · lab-worker ────────┐
 │ kubelet     caretaker      │  │ kubelet     caretaker      │
 │ containerd  runs them      │  │ containerd  runs them      │
 │ kube-proxy  Service rules  │  │ kube-proxy  Service rules  │
 │ flannel     Pod network    │  │ flannel     Pod network    │
 │ [Pod] [Pod] [Pod]          │  │ [Pod] [Pod] [Pod]          │
 └────────────────────────────┘  └────────────────────────────┘
       ◄══════════ flannel tunnel over eth1 ══════════►
```

One rule explains the whole picture: **every part talks only to the API server.** The
scheduler never calls the kubelet, and the controllers never call containerd. Each part
watches the API server for its kind of work, does its one job, and writes the result
back.

### Brain part 1: API server

The API server is the front desk of the cluster: a web server, on HTTPS port 6443, that
every other part and every `kubectl` command talks to.

- It checks every request: who is asking, whether they're allowed, and whether the
  object is valid.
- It saves objects in the datastore. It's the only part that touches the datastore.
- It tells the other parts about changes, through watches.

If it stops, the apps already running keep running, but nothing can change: no new Pods,
no updates, no `kubectl`.

See it:

```bash
server$ kubectl get --raw /readyz
```

`ok` means the API server is up and ready to take requests.

### Brain part 2: datastore

The datastore is the cluster's memory: a database holding every object, both what you
asked for (`spec`) and what's true right now (`status`).

Big clusters use **etcd**, a database built for this job. k3s uses **SQLite** by
default: a single file, plenty for a small cluster.

If the datastore is lost, the cluster forgets everything: every Deployment, Service and
Secret. That's why real clusters back it up.

See it:

```bash
server$ sudo ls -lh /var/lib/rancher/k3s/server/db/
```

`state.db` is the whole cluster, in one file.

### Brain part 3: scheduler

The scheduler is the planner: it picks a node for every new Pod.

It watches for Pods that have no node yet. For each one it rules out the nodes that
can't take it, for example because they lack the free CPU or memory the Pod requests,
or because they carry a taint the Pod doesn't tolerate, like your server since section 6.
It ranks the rest and writes the winning node's name on the Pod. It never starts
anything itself. Starting the Pod is the kubelet's job.

If no node fits, the Pod stays `Pending`, and `kubectl describe pod` shows a
`FailedScheduling` event. You'll cause one on purpose in section 14.

See it: the NODE column shows the scheduler's decisions.

```bash
server$ kubectl get pods -A -o wide
```

### Brain part 4: controller manager

The controller manager is the fixer: one program that runs dozens of controllers, each
in charge of one kind of object.

Every controller runs the same reconciliation loop: read what you asked for, look at
what exists, fix the difference, repeat. Some you'll meet:

- The **Deployment controller** creates a ReplicaSet for each version of a Deployment.
- The **ReplicaSet controller** keeps the right number of Pods.
- The **EndpointSlice controller** lists the Pods behind each Service and marks which
  ones are ready.
- The **Node controller** notices when a node stops answering.

See it: delete the CoreDNS Pod, then look again a few seconds later.

```bash
server$ kubectl -n kube-system delete pod -l k8s-app=kube-dns
server$ kubectl -n kube-system get pods -l k8s-app=kube-dns
```

The new Pod has a new name and a young AGE. Nobody asked for it: the ReplicaSet
controller saw 0 Pods where 1 was wanted.

### Node part 1: kubelet

The kubelet is the caretaker on every node: an agent that runs the Pods assigned to its
node and keeps them healthy.

It watches the API server for Pods with its node's name on them. For each one it asks
the container runtime to pull the image and start the containers. It also mounts the
Pod's volumes, runs its health checks, restarts containers that crash, and reports the
Pod's status back.

It's also why a node exists in the cluster at all: the kubelet registers its node with
the API server and keeps reporting that it's alive.

See it: the VERSION column is each node's kubelet version.

```bash
server$ kubectl get nodes -o wide
```

### Node part 2: container runtime (containerd)

The container runtime is the engine: the program that downloads images and runs
containers. k3s uses **containerd**.

The kubelet decides *what* should run, and containerd does the running. Kubernetes
itself never starts a process directly.

See it: the CONTAINER-RUNTIME column of `kubectl get nodes -o wide`, and the real
containers on a node:

```bash
server$ sudo crictl ps
```

Each line is a real container. Pick a Pod from `kubectl get pods -A -o wide` whose
NODE is `lab-server`, and find it here: the POD column shows its name.

### Node part 3: kube-proxy

kube-proxy is the call forwarding on every node: it turns each Service into forwarding
rules, so traffic sent to a Service's address reaches one of its Pods.

A Service's address (its ClusterIP, `10.43.…`) belongs to no machine. It only exists as
these rules, which kube-proxy writes on every node with iptables, Linux's built-in
traffic rules, and updates whenever the Pods behind a Service change. In k3s, kube-proxy runs inside the k3s process.

See it: count the rule chains it wrote, one per Service port.

```bash
server$ sudo iptables-save | grep -c "^:KUBE-SVC"
```

The number is the count of Service ports kube-proxy knows about, and your `web` Service
from section 7 is one of them. Create another Service and it grows by one.

### Node part 4: Pod network (CNI, flannel)

The CNI plugin is the plumbing: it gives every Pod its own address and connects Pods
across nodes, like the line between two offices. k3s uses **flannel**.

flannel gives each node a block of Pod addresses (`10.42.0.…` on the server, `10.42.1.…`
on the worker). It builds a tunnel between the nodes over `eth1`, so a Pod on one node
reaches a Pod on the other as if they sat side by side.

kube-proxy and flannel are easy to mix up. flannel makes every **Pod address**
(`10.42.`) reachable, even on the other machine: every employee's own number works.
kube-proxy forwards **Service addresses** (`10.43.`) to Pod addresses: call forwarding
from a team number to one employee.

See it:

```bash
server$ ip -br addr | grep -E "flannel|cni"
```

`flannel.1` is the tunnel to the other node. `cni0` is a software network card that
every Pod on this machine is plugged into, and its address `10.42.0.1` comes from this
node's block.

### Add-ons: CoreDNS, Traefik and friends

Add-ons are ordinary Pods that give the cluster extra features. They live in the
`kube-system` namespace, and k3s installs these for you:

| Add-on | What it does | Section |
|---|---|---|
| CoreDNS | The cluster's contacts app: turns Service names like `web` into their `10.43.` addresses | 7 |
| Traefik | The ingress controller, the operator: sends web requests to a Service by website name | 8 |
| ServiceLB (`svclb-*` Pods) | Makes `LoadBalancer` Services answer on every machine's address | 8 |
| metrics-server | Measures CPU and memory use, for `kubectl top` | 11 |
| local-path-provisioner | Creates disks on demand for PersistentVolumeClaims | 12 |

See them:

```bash
server$ kubectl get pods -n kube-system
```

### Where everything lives in k3s

In a standard cluster (built with kubeadm, for example), each part is a separate
program, and you'd see Pods like `kube-apiserver-…`, `etcd-…` and `kube-scheduler-…` in
`kube-system`. k3s packs them into one program:

```
   k3s server  (lab-server)          k3s agent  (lab-worker)
   ├── API server                    ├── kubelet
   ├── scheduler                     ├── kube-proxy
   ├── controller manager            └── flannel
   ├── datastore (SQLite)            + containerd, started by k3s
   ├── kubelet
   ├── kube-proxy
   └── flannel
   + containerd, started by k3s
```

That's why `kubectl get pods -n kube-system` shows only the add-ons: the brain itself
doesn't run as Pods.

See it:

```bash
server$ pgrep -a k3s
worker$ pgrep -a k3s
```

### All together: one apply, start to finish

Here's what happens when you apply `web.yaml`, a Deployment with 3 replicas. Every arrow
goes through the API server.

1. **kubectl** sends the Deployment to the **API server**, which checks it and saves it
   in the **datastore**.
2. The **Deployment controller** sees a new Deployment and creates a ReplicaSet.
3. The **ReplicaSet controller** sees a ReplicaSet that wants 3 Pods and has 0. It
   creates 3 Pods, with no node yet (`Pending`).
4. The **scheduler** sees 3 Pods without a node, picks a node for each, and writes it on
   the Pod.
5. The **kubelet** on each chosen node sees a Pod with its name on it. It asks
   **containerd** to pull the image and start the container, and **flannel** gives the
   Pod an IP.
6. The **kubelet** reports `Running` back to the API server.
7. When a Service selects these Pods, the **EndpointSlice controller** lists their IPs,
   **kube-proxy** on every node turns that list into rules, and **CoreDNS** answers the
   Service's name.

Nobody gave anyone an order. Each part saw a change it cares about, did its one job,
and wrote the result back.

**Check your understanding.**

<details><summary>Which part is the only one that reads and writes the datastore?</summary>

The API server. Everything else, including `kubectl`, goes through it.
</details>

<details><summary>You delete a Pod that belongs to a Deployment. Which part creates the replacement: the kubelet or a controller?</summary>

The ReplicaSet controller, inside the controller manager. The kubelet only runs the Pods
it's given. It never decides that a Pod should exist.
</details>

<details><summary>A new Pod stays Pending forever. Which part couldn't do its job, and where do you see why?</summary>

The scheduler: no node fits the Pod. `kubectl describe pod` shows a `FailedScheduling`
event with the reason.
</details>

<details><summary>The API server goes down. Do your running apps stop?</summary>

No. The kubelets keep their Pods running. But nothing can change until it's back: no new
Pods, no updates, no `kubectl`.
</details>

<details><summary>What's the difference between kube-proxy and flannel?</summary>

flannel gives Pods their addresses (`10.42.`) and connects them across machines.
kube-proxy turns Service addresses (`10.43.`) into rules that forward to those Pod
addresses.
</details>

<details><summary>Why is there no API server Pod in kube-system on k3s?</summary>

k3s runs the whole control plane inside the `k3s server` process, not as Pods. Only the
add-ons run as Pods.
</details>

**Checkpoint.** You can draw the big picture from memory: the 4 parts of the brain, the
4 parts on every node, and the add-ons. For each one, you can say in one sentence what
it is and what it does.

## 9. Rolling updates and rollbacks

**Coming back?** This section uses the `web` chain you built in sections 6 to 8: Deployment, Service and
Ingress.

```bash
server$ kubectl get deploy,svc,ingress web
mac$ curl -H "Host: web.lab" http://192.168.56.120/
```

The `curl` should answer `served by web-…`. If something is missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml -f /vagrant/manifests/web-ingress.yaml
```

**Why.** Apps change all the time: new versions, bug fixes. Stopping everything to update
means downtime. You want to swap old for new gradually, with an undo button if the new
version is bad.

**New words.**
- **Rollout**: the process by which a Deployment replaces the Pods of one version with
  Pods of a new version, step by step. It swaps old for new a few at a time, so the
  app never goes down.
- **Rollback**: returning a Deployment to a previous version, by scaling its old
  ReplicaSet back up (`kubectl rollout undo`). The undo button for a release.

**The idea.** When you change a Deployment's Pod blueprint (for example the image), the
Deployment creates a **new ReplicaSet** for the new version and moves Pods across step by
step. The old ReplicaSet is kept, scaled down to 0, as a record of the previous version.

```
   start:    old RS [Pod Pod Pod]      new RS [ ]
   step:     old RS [Pod Pod    ]      new RS [Pod]
   step:     old RS [Pod        ]      new RS [Pod Pod]
   end:      old RS [ ]                new RS [Pod Pod Pod]
```

Two settings control the pace: `maxSurge` (how many extra Pods may exist during the
update) and `maxUnavailable` (how many may be missing). The defaults (25% each) work out,
for 3 Pods, as "at most 1 extra, none missing".

**Predict.** Later you'll deploy an image that doesn't exist. Will the website go down?

**Do it.** Keep a loop running on the Mac to spot any interruption:

```bash
mac$ while true; do curl -s -H "Host: web.lab" http://192.168.56.120/; sleep 0.5; done
```

In another terminal, a good update:

```bash
server$ kubectl set image deployment/web nginx=nginx:1.28-alpine
server$ kubectl rollout status deployment/web
server$ kubectl get rs -l app=web
```

The loop never stops answering, and new `served by` names appear as Pods are replaced.
`get rs` shows two ReplicaSets: the new one with 3 Pods, the old one with 0.

Now a bad update:

```bash
server$ kubectl set image deployment/web nginx=nginx:does-not-exist
server$ kubectl get pods
server$ kubectl get rs -l app=web
```

**What happened.** The new ReplicaSet made one Pod, which can't download its image
(`ErrImagePull`, then `ImagePullBackOff`). Since no Pod may be missing, an old Pod is only
removed after a new one is ready, and this new one never gets ready. So the rollout stops,
and the three old Pods keep serving. Your loop never noticed a thing.

One detail: this Deployment has no health check yet, so "ready" means "the container
started". In section 11 you'll add a real one.

**Undo it.**

```bash
server$ kubectl describe pod <the-broken-pod> | tail -5
server$ kubectl rollout history deployment/web
server$ kubectl rollout undo deployment/web
server$ kubectl get rs -l app=web
```

`rollout undo` scales the previous ReplicaSet back up and the broken one down to 0.
Finally, write `image: nginx:1.28-alpine` into `web.yaml` and re-apply, so the file
matches the cluster. Changes made with `kubectl set` get overwritten the next time someone
applies the old file.

**Check your understanding.**

<details><summary>Where does Kubernetes keep the previous version?</summary>

In the old ReplicaSets, scaled to 0. Each holds the Pod blueprint of one version.
</details>

<details><summary>Why did the broken image cause no downtime?</summary>

With no Pod allowed to be missing, old Pods are removed only once new ones are ready. The
new Pod never became ready, so no old Pod was removed.
</details>

**Connect the dots.** [k8s/k3s Reference: Deployment](k8s-k3s-refresher.md#deployment).

**Checkpoint.** You can explain what happens during an update, why the broken release
caused no downtime, and what `rollout undo` does.

## 10. ConfigMaps and Secrets

**Coming back?** This section uses the `web` chain you built in sections 6 to 8: Deployment, Service and
Ingress.

```bash
server$ kubectl get deploy,svc,ingress web
mac$ curl -H "Host: web.lab" http://192.168.56.120/
```

The `curl` should answer `served by web-…`. If something is missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml -f /vagrant/manifests/web-ingress.yaml
```

**Why.** So far the web page is baked into each Pod by the `postStart` trick. In real life
you want **one image** that runs everywhere (laptop, test, production) with different
settings. Rebuilding an image to change a setting is slow and clumsy. And some settings
are sensitive: passwords, keys.

**New words.**
- **ConfigMap**: an object storing non-sensitive settings as `key: value` pairs or whole
  files, kept in the cluster and outside the image, so one image works everywhere.
- **Secret**: an object like a ConfigMap but meant for sensitive values such as
  passwords and keys. Careful: it is only base64-encoded, not encrypted.
- **Volume**: a directory made available to a Pod's containers, sourced from outside the
  image: a ConfigMap, a Secret, a disk claim, and others. A folder plugged in from
  outside.
- **Environment variable**: a named value passed to a process at startup, which it reads
  but which doesn't change while the container runs. For example, `DB_USER=admin`.

**The idea.** A ConfigMap or Secret holds `key: value` pairs. A Pod can receive them in
two ways:

```
   as files      mounted into a folder in the container    (updates while running)
   as env vars   set when the container starts             (fixed until restart)
```

### Part 1: a ConfigMap as files

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/site.yaml`. One file can hold several
objects, separated by `---`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: site
data:
  index.html: |                         # a key named index.html; its value is the file
    <h1>Version 1, served from a ConfigMap</h1>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: site
spec:
  replicas: 2
  selector:
    matchLabels:
      app: site
  template:
    metadata:
      labels:
        app: site
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine      # plain nginx, nothing custom inside
          volumeMounts:
            - name: html                # mount the volume called html ...
              mountPath: /usr/share/nginx/html   # ... where nginx looks for pages
      volumes:
        - name: html                    # a volume called html ...
          configMap:
            name: site                  # ... filled from the ConfigMap "site"
---
apiVersion: v1
kind: Service
metadata:
  name: site
spec:
  selector:
    app: site
  ports:
    - port: 80                          # no targetPort: defaults to the same, 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site
spec:
  ingressClassName: traefik
  rules:
    - host: site.lab
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: site
                port:
                  number: 80
```

You know most of this already (Deployment, Service, Ingress). The new part is
`volumes` + `volumeMounts`: "make a volume from the ConfigMap, and mount it here".

**Predict.** After you change the text in the ConfigMap and re-apply, will the Pods
restart?

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/site.yaml
mac$ curl -H "Host: site.lab" http://192.168.56.120/
```

Change `Version 1` to `Version 2` in the file, re-apply, and repeat the `curl` every few
seconds.

**What happened.** The kubelet read the ConfigMap and wrote each key as a file inside the
Pod's volume. When you changed it, the kubelet noticed (it checks regularly, so it can
take up to about a minute) and updated the file. nginx served the new file. No Pod
restarted.

**Look under the hood.**

```bash
server$ kubectl exec deploy/site -- ls -la /usr/share/nginx/html
server$ kubectl get pods -l app=site            # RESTARTS stays 0
```

`index.html` is a link into a hidden `..data` folder. On a change, the kubelet writes the
new version next to the old one and switches the link in one go, so nginx never reads a
half-written file.

### Part 2: a Secret as environment variables

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque                       # a generic Secret (key/value pairs)
stringData:                        # plain text here; Kubernetes stores it base64-encoded
  username: admin
  password: s3cr3t
---
apiVersion: v1
kind: Pod
metadata:
  name: secret-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo user=$DB_USER password=$DB_PASSWORD; sleep 3600"]
      env:
        - name: DB_USER            # the variable the program will see ...
          valueFrom:
            secretKeyRef:
              name: db-credentials # ... taken from this Secret ...
              key: username        # ... this key
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
```

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/secret.yaml
server$ kubectl wait --for=condition=Ready pod/secret-demo --timeout=90s
server$ kubectl logs secret-demo
```

The program printed the values it received as environment variables.

**Look under the hood: a Secret is not encrypted.**

```bash
server$ kubectl get secret db-credentials -o yaml | grep -A2 "^data"
server$ kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```

The stored value looks scrambled, but it's only **base64 encoding**, which anyone can
reverse, as the second command shows. A Secret's protection comes from who is allowed to
read it (access rules) and from keeping it out of images and Git, not from encryption.
Never commit real passwords in YAML.

**Check your understanding.**

<details><summary>Why is a ConfigMap better than writing the page into the image?</summary>

The same image works everywhere. Content or settings change without building a new image,
and (as mounted files) without restarting Pods.
</details>

<details><summary>If you change the Secret now, will secret-demo print the new password?</summary>

No. Environment variables are set when the container starts. The Pod would need to be
recreated. Only mounted files update while running.
</details>

<details><summary>Is a password safe just because it's in a Secret?</summary>

No. Base64 is not encryption. A Secret is safer than a ConfigMap only because access can
be restricted to it, and because it keeps passwords out of images and code.
</details>

**Connect the dots.** [k8s/k3s Reference: Other objects](k8s-k3s-refresher.md#other-objects).

**Checkpoint.** The `site.lab` page changes while `RESTARTS` stays 0, and you can explain
the difference between receiving settings as files and as environment variables.

## 11. Health checks and resources

**Coming back?** This section uses the `web` chain you built in sections 6 to 8: Deployment, Service and
Ingress.

```bash
server$ kubectl get deploy,svc,ingress web
mac$ curl -H "Host: web.lab" http://192.168.56.120/
```

The `curl` should answer `served by web-…`. If something is missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml -f /vagrant/manifests/web-ingress.yaml
```

**Why.** Kubernetes knows whether a container's *process* is running, but not whether the
app inside *works*. An app can be stuck, or still starting up, while its process
looks perfectly alive. Kubernetes also needs to know how much CPU and memory each app
needs, to place it on a machine with room for it.

**New words.**
- **Probe**: a periodic check the kubelet runs against a container: an HTTP request, a
  TCP connection, or a command, used to decide if it's healthy or ready. A regular "are
  you OK?" check.
- **Liveness probe**: a probe that gets the kubelet to restart the container once it
  fails repeatedly. "Are you stuck?" If yes, reboot.
- **Readiness probe**: a probe that removes the Pod from its Service's list while it
  fails, without restarting it. "Can you take visitors now?" If not, send them
  elsewhere.
- **Requests**: the CPU and memory a container needs. The scheduler only places it on a
  node with that much free. "I need at least this much."
- **Limits**: the most a container may use. Going over the memory limit gets the
  container killed (`OOMKilled`). Going over the CPU limit only slows it down. "Never
  give me more than this."

**The idea.**

```
   liveness fails   →  kubelet restarts the container      ("it's broken, reboot it")
   readiness fails  →  Pod removed from the Service's list  ("not now, send others")
```

Resources:

```
   requests   what the app needs. The scheduler only picks a machine with this much free.
   limits     the ceiling. More memory than the limit: killed. More CPU: slowed down.
```

### Part 1: a liveness probe restarts a stuck app

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/liveness.yaml`. This app is healthy for
30 seconds, then "breaks" by deleting its health file:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: liveness-demo
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "touch /tmp/healthy; sleep 30; rm /tmp/healthy; sleep 600"]
      livenessProbe:
        exec:
          command: ["cat", "/tmp/healthy"]   # healthy = this file exists
        initialDelaySeconds: 5                # wait 5 s before the first check
        periodSeconds: 5                      # then check every 5 s
```

**Predict.** The process never exits; it keeps sleeping. Will Kubernetes still restart it?

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/liveness.yaml
server$ kubectl get pod liveness-demo -w       # watch RESTARTS for about two minutes
```

**What happened.** For 30 seconds `cat /tmp/healthy` succeeded. Then the file vanished,
the check failed three times in a row (the default threshold), and the kubelet restarted
the container. `RESTARTS` goes up by one each cycle, even though the process itself was
never dead.

The first restart takes over a minute: 30 seconds healthy, then three failed checks 5
seconds apart, then up to 30 seconds for the old container to stop.

```bash
server$ kubectl describe pod liveness-demo | grep -i liveness
```

The events say `Liveness probe failed … will be restarted`.

### Part 2: a readiness probe and resources on your web app

**Read it.** Add this to the container in `web.yaml`, lined up with `image:`:

```yaml
          readinessProbe:          # "can this Pod take traffic?"
            httpGet:
              path: /              # ask nginx for its home page ...
              port: 80             # ... a 200-399 answer means ready
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m             # 50 thousandths of a CPU
              memory: 32Mi         # 32 mebibytes of memory
            limits:
              memory: 64Mi         # never more than 64 MiB
```

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml
server$ kubectl rollout status deployment/web
```

Changing the Pod blueprint caused a rollout (section 9): new Pods, now with a health check.
Now break one Pod's readiness by deleting its home page:

```bash
server$ kubectl get pods -l app=web -o wide
server$ kubectl exec <a-web-pod> -- rm /usr/share/nginx/html/index.html
server$ kubectl get pods -l app=web
server$ kubectl describe endpointslices -l kubernetes.io/service-name=web | grep -E "Addresses|Ready"
mac$ for i in 1 2 3 4 5 6; do curl -s -H "Host: web.lab" http://192.168.56.120/; done
```

READY becomes `0/1` for that Pod after about 15 seconds: 3 failed checks, 5 seconds
apart. Run `get pods` again if it still says `1/1`.

**What happened.** Without `index.html`, nginx answers `403 Forbidden`, so the readiness
check fails. The Pod stays in the EndpointSlice, but its address now shows
`Ready: false`. kube-proxy and Traefik skip addresses that aren't ready, so the Service
(section 7) stops sending it traffic. Every `curl` answer names one of the other two
Pods, never the broken one.

The Pod is **not** restarted: readiness only steers traffic. Clean up by deleting that
Pod. The Deployment replaces it with a fresh one.

**Look under the hood: resources.**

```bash
server$ kubectl describe node lab-worker | grep -A6 "Allocated resources"
server$ kubectl top pods                        # actual use (needs a minute of data)
```

`describe node` adds up the requests of the Pods on that machine: this is the bookkeeping
the scheduler uses. `kubectl top` (from metrics-server) shows what they use.

**Check your understanding.**

<details><summary>An app is still loading its data for 20 seconds after start. Which probe protects users from it?</summary>

The readiness probe. Until it passes, the Pod gets no traffic. A liveness probe would be
wrong here: it would restart an app that is only slow to start.
</details>

<details><summary>What uses `requests`, and what enforces `limits`?</summary>

The scheduler uses requests to choose a machine with enough free capacity. Limits are
enforced on the machine while the container runs: going over the memory limit gets the
container killed (Kubernetes marks it `OOMKilled`, short for "out of memory").
</details>

**Connect the dots.** Readiness feeds the EndpointSlice from
[section 7](#7-services-and-cluster-dns); requests feed the scheduler from
[k8s/k3s Reference: 3. Cluster architecture](k8s-k3s-refresher.md#3-cluster-architecture).

**Checkpoint.** You've watched a liveness probe restart a container, a readiness probe
take a Pod out of the Service without restarting it, and you can say who uses requests.

## 12. Storage that outlives Pods

**Coming back?** This section needs the `web` Pods from section 6.

```bash
server$ kubectl get pods -l app=web
```

You should see three Pods `Running`. If there are none, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml
```

**Why.** A container's files live only as long as the container. When a Pod is replaced
(and section 6 showed that happens all the time), everything it wrote is gone. Databases,
uploads, and logs need a disk that survives.

**New words.**
- **PersistentVolumeClaim (PVC)**: an object through which an app requests storage (a
  size and access mode). Kubernetes binds it to a matching PersistentVolume. "I need
  100 MiB."
- **PersistentVolume (PV)**: a piece of real storage in the cluster, with a lifecycle of
  its own, independent of any Pod. It stays when the Pod is gone.
- **StorageClass**: a description of how to create storage on demand. When a claim names
  one (or uses the default), its provisioner creates a matching PV automatically. In k3s
  it's `local-path`, the recipe for making new disks.

**The idea.** You don't create disks yourself. You file a **claim** (PVC) saying how much
you need; a provisioner (k3s's local-path) creates a matching **volume** (PV) and binds it
to your claim; your Pod mounts the claim.

```
   Pod ──mounts──> PVC "notes-data"  ──bound to──> PV  ──>  a folder on a machine's disk
                   (the request)                   (the actual storage)
```

**Predict.** First see the problem with a normal container:

```bash
server$ kubectl exec <a-web-pod> -- sh -c 'echo hello > /tmp/note.txt; cat /tmp/note.txt'
server$ kubectl delete pod <that-web-pod>
server$ kubectl exec <the-new-web-pod> -- cat /tmp/note.txt
```

The file is gone in the new Pod. Now guess: with a PVC, will the file survive the Pod being
deleted?

**Read it.** Create `~/Desktop/inception-of-things-42/k8s-lab/manifests/storage.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: notes-data
spec:
  accessModes:
    - ReadWriteOnce            # can be mounted by one machine at a time
  resources:
    requests:
      storage: 100Mi           # how much space you need
---
apiVersion: v1
kind: Pod
metadata:
  name: notes
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data     # the claim appears here in the container
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: notes-data  # use the claim above
```

**Do it.**

```bash
server$ kubectl apply -f /vagrant/manifests/storage.yaml
server$ kubectl wait --for=condition=Ready pod/notes --timeout=90s
server$ kubectl get pvc,pv
server$ kubectl exec notes -- sh -c 'echo "I survive" > /data/note.txt'
server$ kubectl delete pod notes
server$ kubectl apply -f /vagrant/manifests/storage.yaml
server$ kubectl wait --for=condition=Ready pod/notes --timeout=90s
server$ kubectl exec notes -- cat /data/note.txt
```

`kubectl wait` pauses until the Pod is ready, because the first time local-path needs a
few seconds to create the folder. The `delete` takes about 30 seconds: this busybox
program ignores the polite stop signal, so Kubernetes waits 30 seconds and then forces
it.

**What happened.** The claim asked for 100 MiB. When the `notes` Pod first needed it,
local-path created a PV (a folder on the disk of the machine running the Pod) and bound
the claim to it. Deleting the Pod didn't touch the claim or the volume. The new Pod
mounted the same claim, and your file was still there.

A tip: if you look at `kubectl get pvc` before any Pod uses the claim, it says `Pending`.
That's normal with local-path: it waits to see which machine the Pod runs on, then creates
the folder there.

**Look under the hood.**

```bash
server$ kubectl get pv -o wide
server$ kubectl get pod notes -o wide
server$ sudo ls /var/lib/rancher/k3s/storage/
```

Run the `ls` on the machine in the NODE column. If it says `lab-worker`, run it in
`vagrant ssh lab-worker` instead.

The PV is a real folder under `/var/lib/rancher/k3s/storage/` on the machine where the Pod
ran. Because the data lives on that one machine, the PV is pinned to it, and a new `notes`
Pod is always scheduled there.

**Check your understanding.**

<details><summary>What's the difference between a PVC and a PV?</summary>

The PVC is the request ("I need 100 MiB"); the PV is the actual storage that satisfies it.
Apps only ever refer to the PVC.
</details>

<details><summary>Why is the PVC still there after you deleted the Pod?</summary>

It's a separate object with its own life. Deleting a Pod never deletes its claim; you
delete the PVC explicitly when you no longer want the data.
</details>

**Connect the dots.** [k8s/k3s Reference: Other objects](k8s-k3s-refresher.md#other-objects)
and the local-path storage bundled with [k3s](k8s-k3s-refresher.md#6-k3s).

**Checkpoint.** Your note survived deleting the Pod, and you can explain claim, volume,
and why the Pod lands on the same machine.

## 13. Namespaces

**Coming back?** This section needs the `web` Deployment and Service.

```bash
server$ kubectl get deploy,svc web
```

If either is missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml
```

**Why.** So far everything lives in one space, `default`. In a shared cluster, two teams
(or a "dev" and a "prod" copy of the same app) would collide on names like `web`.

**New words.**
- **Namespace**: a way to divide one cluster into separate spaces. Names must be unique
  within a namespace, not across the whole cluster. Like folders: two folders can each
  hold a file called `web`.

**The idea.** `web` in `default` and `web` in `dev` are two different objects. A few kinds
of objects belong to the whole cluster instead of a namespace: Nodes, PersistentVolumes,
and Namespaces themselves.

**Predict.** If you create a second `web` Service in `dev`, which one does `http://web`
reach from a Pod in `default`?

**Do it.**

```bash
server$ kubectl create namespace dev
server$ kubectl apply -n dev -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml
server$ kubectl get pods                 # default only
server$ kubectl get pods -n dev
server$ kubectl get pods -A              # every namespace
```

**What happened.** The same files created a second, independent set of objects in `dev`.
Its Service gets its own full DNS name: `<service>.<namespace>.svc.cluster.local`. Like
a phone number with its area code, the full name works from anywhere in the cluster. The
short `web` is like dialling without the area code: it stays in your own namespace.

**Look under the hood.**

```bash
server$ kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- http://web.dev.svc.cluster.local
server$ kubectl api-resources --namespaced=false | head -15
```

The full name reaches the copy in `dev`. The short name `web` is looked up in the Pod's own
namespace first, thanks to the `search` line you saw in section 7.
In the `api-resources` list, find `nodes`, `namespaces` and `persistentvolumes`. They
belong to the whole cluster, so `-n` means nothing for them.

Deleting a namespace deletes everything inside it:

```bash
server$ kubectl delete namespace dev
```

**Check your understanding.**

<details><summary>Back to the prediction: which web does http://web reach from default?</summary>

The one in `default`. A Pod's DNS search list, the endings it adds to short names
(section 7), starts with its own namespace, so the short name is found there first.
</details>

**Connect the dots.** [k8s/k3s Reference: Other objects](k8s-k3s-refresher.md#other-objects).

**Checkpoint.** You can reach `web` in `dev` from a Pod in `default` and explain why the
short name reaches `default`'s copy.

## 14. Troubleshooting drills

Time to be a detective. Each drill breaks one link in the chain you've built. Diagnose it
with `get`, `describe`, `logs`, and `get endpointslices` before opening the answer, and
name **which link** broke.

**Coming back?** This section uses the `web` chain you built in sections 6 to 8: Deployment, Service and
Ingress.

```bash
server$ kubectl get deploy,svc,ingress web
mac$ curl -H "Host: web.lab" http://192.168.56.120/
```

The `curl` should answer `served by web-…`. If something is missing, catch up:

```bash
server$ kubectl apply -f /vagrant/manifests/web.yaml -f /vagrant/manifests/web-svc.yaml -f /vagrant/manifests/web-ingress.yaml
```

### Drill 1 — the Service that points at nothing

```bash
server$ kubectl patch svc web -p '{"spec":{"selector":{"app":"wbe"}}}'
mac$ curl -H "Host: web.lab" http://192.168.56.120/
```

Symptom: the request fails, yet every Pod is `Running`.

<details><summary>Answer</summary>

Broken link: Service → Pods. `kubectl get endpointslices -l kubernetes.io/service-name=web`
is empty (ENDPOINTS shows `<unset>`): the selector `app: wbe` matches no Pod. Fix with
`kubectl apply -f /vagrant/manifests/web-svc.yaml`.
</details>

### Drill 2 — the wrong port

Change `targetPort: 80` to `targetPort: 8080` in `web-svc.yaml` and apply it.

Symptom: endpoints exist, but requests fail.

<details><summary>Answer</summary>

Broken link: Service → container port. The Service forwards to port 8080, where nginx
isn't listening: the call goes to an extension nobody answers. Endpoints only prove that labels match, not that the port is right. Set it back
to 80 and re-apply.
</details>

### Drill 3 — the Pod that never starts

In `web.yaml`, set both the memory request and the memory limit to `64Gi`, then apply.
(Both, because Kubernetes refuses a request larger than its limit.)

Symptom: new Pods stay `Pending`.

<details><summary>Answer</summary>

Broken link: scheduler → machine. `kubectl describe pod` shows `FailedScheduling` with
one reason per machine: `Insufficient memory` for the worker, and the taint for the
server (section 6). No machine fits, so the Pod is never placed. Put the
values back (`32Mi` / `64Mi`) and re-apply.
</details>

### Drill 4 — the wrong website name

Change `host: web.lab` to `host: wbe.lab` in `web-ingress.yaml` and apply it.

Symptom: `curl -H "Host: web.lab" http://192.168.56.120/` returns `404 page not found`.

<details><summary>Answer</summary>

Broken link: Ingress rule. The 404 comes from Traefik: no rule matches `web.lab`.
`kubectl describe ingress web` shows the host it expects. Set it back and
re-apply.
</details>

### Drill 5 — the app that keeps crashing

```bash
server$ kubectl run crash --image=busybox:1.36 -- sh -c "echo starting; echo config file missing; exit 1"
server$ kubectl get pod crash -w                 # Ctrl-C after about a minute
```

Symptom: STATUS switches between `Error` and `CrashLoopBackOff`, and RESTARTS keeps
climbing.

<details><summary>Answer</summary>

Broken link: the app itself. The container starts, prints two lines and exits with code 1.
The kubelet restarts it and waits longer before each new try: 10 seconds, then 20, then
40, up to 5 minutes. `CrashLoopBackOff` is the name for that waiting. Kubernetes is
working fine, so read what the app said. `kubectl logs crash --previous` prints the
output of the run that crashed, and `kubectl describe pod crash` shows
`Last State: Terminated` with `Reason: Error` and `Exit Code: 1`. The fix belongs in the
app or its configuration. Clean up with `kubectl delete pod crash`.
</details>

### The method

Every symptom points at one stage of the chain:

```
kubectl get pods            is it running?          Pending → scheduling problem
kubectl describe pod <p>    what do Events say?     ImagePullBackOff → image problem
kubectl logs <p>            what did the app say?   CrashLoopBackOff → app problem
kubectl get endpointslices  does the Service see    <unset> → selector problem
                            the Pods?
kubectl describe            are they ready?         Ready: false → readiness problem
  endpointslices
curl gets 404 from Traefik  does a rule match?      check the Ingress host and path
```

## 15. Clean up

Remove the apps but keep the cluster:

```bash
server$ kubectl delete -f /vagrant/manifests/
```

Remove the whole lab:

```bash
mac$ vagrant destroy -f
```

To practise the installation again from zero: `vagrant destroy -f && vagrant up`, then
restart at section 2. Repeating sections 2–3 a few times is the best way to make them
stick.

## 16. Putting it all together

Well done for getting here! Two flows run through everything you did.

The control flow — how a description you apply becomes running containers:

```
 you: kubectl apply ──> API server ──> datastore
                            │
          controllers: Deployment ──> ReplicaSet ──> Pods      (sections 6, 9)
                            │
          scheduler: picks an allowed machine (taints)          (sections 5, 6, 11)
          with room (requests)
                            │
          kubelet + containerd: run it, mount ConfigMaps,       (sections 5, 10, 12)
          Secrets and volumes, run the probes                   (section 11)
                            │
          EndpointSlice (Pods, marked ready) + kube-proxy        (sections 7, 11)
          + CoreDNS:
          make it reachable by Service name
```

The request flow — how a request from outside reaches a container:

```
 client ──> machine:80 ──> svclb ──> Traefik ──> Ingress rule ──> Service ──> ready Pod
            (section 8)                          (section 8)    (section 7)  (section 11)
```

Follow the addresses: the request arrives on a machine's address (`192.168.56.`), the only
kind the outside can reach. Then it moves inside, to a Service (`10.43.`) and finally a
Pod (`10.42.`).

And the glue between them: **names** connect an Ingress to a Service and a Pod to its
ConfigMap, Secret, or claim; **labels** connect a Deployment and a Service to their Pods.
Most broken setups come down to one wrong name or label.

Final self-test. Explain each out loud, without looking:

1. What happens, step by step, between `kubectl apply -f web.yaml` and a running
   container?
2. Why does a Service exist, and how does it find its Pods?
3. Why does `curl` need `-H "Host: …"` in this lab, and what does Traefik do with it?
4. Where is the previous version kept during a rollout?
5. Files versus environment variables: which one updates without a restart?
6. Liveness versus readiness: what does each one do when it fails?
7. Why did your note survive deleting the `notes` Pod?
8. Name the three kinds of address in this lab, and who can reach each one.

If one feels shaky, go back to that section's "What happened" and "Look under the hood".

## 17. Command cheat sheet

### Do I need to know all of these?

No. Most commands in this lab are only there to let you look at what
Kubernetes is doing. You need about 15 for the project. The rest you can look
up on this page when you need them.

### Where do I type them?

- `vagrant` commands: on the Mac, inside the project folder (`p1/`, `p2/`).
- `kubectl` commands: in p1 and p2, inside the VM after `vagrant ssh <name>`. In p3,
  on the machine where k3d runs.
- In the project VMs (p1, p2) type `sudo kubectl ...`. In the lab VMs you
  don't need `sudo`, because the lab installed k3s with
  `--write-kubeconfig-mode=644` (section 2).

### One pattern for (almost) every kubectl command

```
kubectl  <what to do>  <what kind of thing>  [its name]  [-n namespace]
```

Example:

```
kubectl  describe  pod  web-7d4b9  -n dev
         |         |    |          |
         |         |    |          +-- look in the "dev" namespace
         |         |    +------------- the Pod called web-7d4b9
         |         +------------------ kind of thing: a Pod
         +---------------------------- what to do: show its details
```

The five "what to do" words you will use most:

| Word | Meaning |
|---|---|
| `get` | List things (short table) |
| `describe` | Show one thing in detail, with its recent events |
| `apply` | Create or update things from a YAML file |
| `delete` | Remove things |
| `logs` | Show what a Pod's program printed |

Learn these five and you can build most commands yourself.

If you leave out `-n`, kubectl looks only in the `default` namespace. Use `-A`
to look in all namespaces at once.

### Must know (for the defense and p1 to p3)

**Vagrant (on the Mac)**

| Command | What it does |
|---|---|
| `vagrant up` | Create and start the VMs |
| `vagrant status` | Show which VMs are running |
| `vagrant ssh <name>` | Open a terminal inside a VM |
| `vagrant destroy -f` | Delete the VMs |

**Inside the VM: check the cluster (p1)**

| Command | What it does |
|---|---|
| `ip a show eth1` | Show the VM's 192.168.56.x address |
| `kubectl get nodes -o wide` | List the machines in the cluster, their state (Ready?) and IPs |

**See and fix what runs (p2, p3)**

| Command | What it does |
|---|---|
| `kubectl get all` | List Pods, Services and Deployments in the `default` namespace |
| `kubectl get all -n dev` | Same, in the `dev` namespace |
| `kubectl get pods -A` | List every Pod in every namespace |
| `kubectl apply -f <file>` | Create or update what the file describes |
| `kubectl delete -f <file>` | Remove what the file describes |
| `kubectl describe pod <name>` | Something is wrong? Read the "Events" at the bottom |
| `kubectl logs <pod>` | A Pod keeps crashing? See what it printed |

**Routing (p2)**

| Command | What it does |
|---|---|
| `kubectl get svc` | List the Services (the stable address in front of Pods) |
| `kubectl get ingress` | List the Ingress rules (which host name goes to which Service) |
| `curl -H "Host: app1.com" 192.168.56.110` | Send a request as if you typed app1.com, to prove the routing |

**k3d and Argo CD (p3)**

| Command | What it does |
|---|---|
| `docker ps` | List running containers (k3d nodes are containers) |
| `k3d cluster create <name>` | Create a cluster inside Docker |
| `k3d cluster list` | List k3d clusters |
| `kubectl get ns` | List namespaces (you should see `argocd` and `dev`) |
| `kubectl port-forward svc/<name> 8888:8888 -n dev` | Open the app on `localhost:8888` |
| `kubectl port-forward svc/argocd-server 8080:443 -n argocd` | Open the Argo CD web page on `localhost:8080` |

To get the Argo CD password, copy this line into your script. You don't need
to memorise it:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Good to understand (look them up when you need them)

| Command | What it does |
|---|---|
| `kubectl get <kind> <name> -o yaml` | Show the whole object as YAML (what you asked for and what is real) |
| `kubectl exec -it <pod> -- sh` | Open a terminal inside a container |
| `kubectl scale deployment <name> --replicas=3` | Change the number of Pods |
| `kubectl rollout status deployment/<name>` | Watch an update finish |
| `kubectl rollout undo deployment/<name>` | Go back to the previous version |
| `kubectl get events` | Recent events in the namespace |
| `kubectl get pods -l app=web` | Only Pods with the label `app=web` |
| `kubectl get pods -w` | Keep watching; the list updates live (Ctrl+C to stop) |
| `kubectl taint nodes <node> <key>=<value>:NoSchedule` | Keep new Pods off a node (add `-` at the end to remove it) |
| `kubectl explain <kind>` | Built-in help for a YAML field |

If someone asks "what does this do?", you should be able to answer.

### Can forget after the lab

Kubeconfig on the Mac (section 4), the NodePort experiment (section 8),
health checks and resources (section 11), storage (section 12), the
troubleshooting drill commands (section 14). They were there to help you
understand, not for the project.

### What the evaluator checks

The evaluator does not test whether you remember flags. They ask you to show
something ("show me the nodes") and then to explain what you see ("why are
there 3 Pods for app2?", "how does a request reach app1?").

So after each command, ask yourself: "what is this output telling me?"

### Full list

All commands used in the lab. The IP `192.168.56.120` is the lab server; in p2
it is `192.168.56.110`.

```bash
# cluster
kubectl get nodes -o wide
kubectl get pods -A
kubectl get all -n <namespace>
kubectl get events --sort-by=.metadata.creationTimestamp

# apply / remove
kubectl apply -f <file-or-folder>
kubectl delete -f <file-or-folder>

# inspect
kubectl get <kind> <name> -o yaml          # full object: spec and status
kubectl describe <kind> <name>
kubectl logs <pod> [-f]
kubectl exec -it <pod> -- sh
kubectl get pods --show-labels
kubectl get endpointslices -l kubernetes.io/service-name=<svc>
kubectl top pods

# change
kubectl scale deployment <name> --replicas=<n>
kubectl set image deployment/<name> <container>=<image>
kubectl rollout status|history|undo deployment/<name>
kubectl taint nodes lab-server node-role.kubernetes.io/control-plane=true:NoSchedule   # apps off the server

# debug Pod
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh

# HTTP through the Ingress, from the Mac
curl -H "Host: <host>" http://192.168.56.120/
curl -v -H "Host: <host>" http://192.168.56.120/ 2>&1 | grep "^>"   # see the request

# on a machine
sudo crictl ps                     # the real containers behind the Pods
pgrep -a k3s                       # k3s server or agent process
```

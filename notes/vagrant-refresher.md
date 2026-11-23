# Vagrant Reference

General documentation for Vagrant and virtual machine networking: concepts, the
Vagrantfile, the machine lifecycle, provisioning, networking, commands, and
troubleshooting. Project-independent; examples use generic names.

## Contents

1. [Concept map](#1-concept-map)
2. [What Vagrant is](#2-what-vagrant-is)
3. [Core components](#3-core-components)
4. [Machine lifecycle](#4-machine-lifecycle)
5. [The Vagrantfile](#5-the-vagrantfile)
6. [Multi-machine setups](#6-multi-machine-setups)
7. [Provisioning](#7-provisioning)
8. [Synced folders](#8-synced-folders)
9. [Networking](#9-networking)
10. [Interface naming in the guest](#10-interface-naming-in-the-guest)
11. [Command reference](#11-command-reference)
12. [Troubleshooting](#12-troubleshooting)
13. [Review questions](#13-review-questions)
14. [Glossary](#14-glossary)

## 1. Concept map

```
                                    VAGRANT
                    "describe a VM in a file, build it with one command"
                                       |
        -------------------------------+-------------------------------
        |                   |                    |                    |
   COMPONENTS           VAGRANTFILE          PROVISIONING         NETWORKING
   ------------        -------------        -------------        -------------
   box (image)         Ruby config          runs on first up     NAT (auto)
   provider            config.vm.box        shell inline:          -> internet
     (VirtualBox)      config.vm.define     shell path:          private_network
   provisioner         network / provider   as root by default     -> VM <-> VM
   Vagrantfile         provision                                 public_network
                                                                   -> real LAN
                                       |                         forwarded_port
                                    LIFECYCLE                      -> host:port
                      up -> (provision) -> running -> halt / reload / destroy
```

## 2. What Vagrant is

Vagrant is a tool for building and managing virtual machines from a configuration file.
Instead of creating a VM by hand in a hypervisor's interface, the machine is described in
a `Vagrantfile`, and `vagrant up` creates, configures, and starts it. The same file
produces the same machine on any computer, which makes environments reproducible,
shareable, and disposable.

Vagrant does not run VMs itself. It drives a provider (a hypervisor such as VirtualBox)
and runs provisioners to configure the guest after boot.

## 3. Core components

```
   +----------------+        reads        +-----------------+
   |  Vagrantfile   | ------------------> |     Vagrant     |
   |  (the recipe)  |                     |  (orchestrator) |
   +----------------+                     +-----------------+
                                            |      |       |
                          downloads/imports |      | drives| runs
                                            v      v       v
                                  +---------+  +----------+  +--------------+
                                  |   Box   |  | Provider |  | Provisioner  |
                                  | (image) |  | VirtualBox| | shell script |
                                  +---------+  +----------+  +--------------+
                                                     |
                                                     v
                                              [ running VM ]
```

- Box: a packaged base image (operating system plus minimal setup), for example
  `bento/ubuntu-24.04`. Downloaded once and cached locally.
- Provider: the hypervisor that actually runs the VM (VirtualBox, VMware, libvirt,
  Hyper-V).
- Provisioner: the mechanism that configures the guest after it boots (shell scripts,
  Ansible, and others).
- Vagrantfile: the Ruby file that ties these together.

## 4. Machine lifecycle

```
                 vagrant up
   (not created) ----------> [ import box -> configure -> boot -> provision* ]
                                                  |
                                                  v
                                             RUNNING
                     vagrant halt  /             |             \  vagrant destroy
                                  v              |              v
                             POWERED OFF         |          (not created)
                                  |              |
                     vagrant up   |              | vagrant reload
                                  v              v
                               RUNNING      reboot + re-apply config
                                            (+ provision with --provision)

   * provisioners run automatically only on the first `vagrant up`
```

Key points:
- Provisioning runs automatically only the first time a machine is created. Later runs
  require `vagrant provision` or `vagrant reload --provision`.
- `vagrant reload` is required for network and hardware changes to take effect.
- `vagrant destroy` removes the VM entirely; the next `vagrant up` starts from the box.

## 5. The Vagrantfile

The Vagrantfile is Ruby. A minimal single-machine example:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "demo"

  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "1024"
    vb.cpus = 1
  end

  config.vm.provision "shell", path: "scripts/setup.sh"
end
```

Common directives:

- `config.vm.box` — base box.
- `config.vm.box_version` — pin a specific box version.
- `config.vm.hostname` — hostname inside the guest.
- `config.vm.network` — attach a network ([section 9](#9-networking)).
- `config.vm.provider "virtualbox" do |vb| … end` — provider settings: memory, CPUs, VM
  name, and raw `vb.customize ["modifyvm", …]` options.
- `config.vm.provision` — provisioning steps ([section 7](#7-provisioning)).
- `config.vm.synced_folder` — shared folders ([section 8](#8-synced-folders)).

The `"2"` in `Vagrant.configure("2")` is the configuration format version and should not
be changed.

## 6. Multi-machine setups

Several VMs can be defined in one Vagrantfile with `config.vm.define`. Settings on the
outer `config` apply to every machine; settings on the block variable apply to that
machine only.

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"          # shared by all machines

  config.vm.define "alpha" do |alpha|
    alpha.vm.hostname = "alpha"
    alpha.vm.network "private_network", ip: "192.168.56.10"
  end

  config.vm.define "beta" do |beta|
    beta.vm.hostname = "beta"
    beta.vm.network "private_network", ip: "192.168.56.11"
  end
end
```

```
   config ......................... applies to ALL machines
     |
     +-- define "alpha" |alpha| ... alpha.vm.*  applies to alpha only
     |
     +-- define "beta"  |beta|  ... beta.vm.*   applies to beta only
```

Common mistake: writing `config.vm.network …` inside a `define` block. Because it uses
`config`, the setting applies to every machine, not just the one whose block contains it.
With forwarded ports this causes port collisions; with networks it adds unintended
adapters to all machines.

Commands accept a machine name: `vagrant up alpha`, `vagrant ssh beta`. Without a name
they act on all machines, in definition order.

## 7. Provisioning

A provisioner configures the guest after boot. The shell provisioner has two forms:

```ruby
# inline: script embedded in the Vagrantfile
config.vm.provision "shell", inline: <<-SHELL
  apt-get update
SHELL

# path: script kept in a separate file, relative to the Vagrantfile
config.vm.provision "shell", path: "scripts/setup.sh"
```

Details:
- Scripts run as root by default (`privileged: true`), so `sudo` inside them is
  redundant.
- `path:` keeps the Vagrantfile short and lets scripts be edited and tested separately.
- Arguments and environment variables can be passed with `args:` and `env:`.
- Scripts should be idempotent (safe to run more than once), since `vagrant provision`
  re-runs them on an existing machine.

## 8. Synced folders

By default, the directory containing the Vagrantfile is mounted inside each guest at
`/vagrant`.

```
   HOST                                   GUEST
   project/                               /vagrant/
     Vagrantfile          <======>          Vagrantfile
     scripts/setup.sh                       scripts/setup.sh
     .vagrant/                              .vagrant/
```

This allows files to be shared between the host and guests, and between guests (one
machine writes a file under `/vagrant`, another reads it). The default share can be
disabled with `config.vm.synced_folder ".", "/vagrant", disabled: true`. The `.vagrant/`
directory holds Vagrant's local machine state and should be excluded from version
control.

## 9. Networking

A VM can have several virtual network adapters, each attached to a different kind of
network.

```
                        INTERNET
                            ^
                            | NAT (adapter 1, always present)
                            |
   +------------------------+------------------------+
   |                      HOST                       |
   |                                                 |
   |   private_network (host-only) 192.168.56.0/24   |
   |     +---------+                 +---------+     |
   |     |  VM A   | <-------------> |  VM B   |     |
   |     |  .10    |                 |  .11    |     |
   |     +---------+                 +---------+     |
   +-------------------------------------------------+
           \                                 /
            \  public_network (bridged)     /
             v                             v
            REAL LAN / Wi-Fi  (router assigns IPs)
```

### NAT

Added automatically as the first adapter on every VirtualBox VM and cannot be removed.
Gives the guest outbound internet access and is the channel Vagrant uses for
`vagrant ssh`. Each VM has its own isolated NAT, so VMs cannot reach each other through
it. The guest typically receives `10.0.2.15`.

### Private network (host-only)

```ruby
config.vm.network "private_network", ip: "192.168.56.10"
```

A network shared only by the host and its VMs. Used for VM-to-VM communication with
fixed IPs. VirtualBox allows host-only addresses in `192.168.56.0/21` by default; other
ranges must be listed in `/etc/vbox/networks.conf`.

### Public network (bridged)

```ruby
config.vm.network "public_network", bridge: "en0: Wi-Fi"
```

Connects the VM directly to a physical network, as if it were another device on the
LAN; the router assigns its IP. The bridge interface name is host-specific: if the named
interface does not exist, Vagrant stops and prompts interactively.

### Forwarded ports

```ruby
config.vm.network "forwarded_port", guest: 80, host: 8080
```

Maps a host port to a guest port over NAT (`localhost:8080` → guest port 80). Each host
port can be used once; duplicate mappings across machines cause collisions.
`auto_correct: true` lets Vagrant pick another host port when one is taken.

### Network options and the `primary` misconception

A private network on VirtualBox accepts options such as `ip`, `netmask`, `type`
(`"dhcp"` for a dynamic address), `adapter` (which adapter slot to use), `mac`,
`nic_type`, `auto_config`, and `virtualbox__intnet` (internal network instead of
host-only).

Options Vagrant does not recognize are ignored without a warning. A common example is
`primary: true` on a network line:

```ruby
config.vm.network "private_network", ip: "192.168.56.10", primary: true   # no effect
```

This looks meaningful but does nothing; `vagrant validate` passes and the adapter is
configured exactly as without it. `primary` is a real option only on a machine
definition, where it marks the default machine for commands like `vagrant ssh` in a
multi-machine Vagrantfile:

```ruby
config.vm.define "alpha", primary: true do |alpha|
```

(It is also used for disks.) There is no network option that makes a declared network
"primary"; NAT is always adapter 1.

Summary of roles:
- NAT → internet access and Vagrant management.
- Private network → communication between VMs and the host.
- Public network → presence on the physical LAN.
- Forwarded port → expose one guest port on the host.

## 10. Interface naming in the guest

Linux names adapters in attachment order. With the `ethX` scheme:

```
   adapter 1 (NAT)              -> eth0
   adapter 2 (first declared)   -> eth1
   adapter 3 (second declared)  -> eth2
```

An interface name identifies a position, not a network. Adding or removing a declared
network shifts the names of the adapters after it, so any configuration that refers to
an interface by name (for example a service bound to `eth1`) can silently point at a
different network.

Some distributions use predictable names such as `enp0s3`/`enp0s8` instead of `ethX`.

Inspection commands:

```bash
ip -br a                       # interfaces and their addresses
ip route show default          # interface used for internet traffic
ip route get <ip>              # interface used to reach a specific address
```

The default route (shown by `ip route show default`) normally uses the NAT interface,
since that is the path to the internet. A static IP on a private network lives on a
different interface (usually `eth1`); both are normal at the same time.

## 11. Command reference

```bash
vagrant up [name]              # create and start; provisions on first creation only
vagrant provision [name]       # re-run provisioners on a running machine, no reboot
vagrant reload [name]          # reboot and apply Vagrantfile changes
vagrant reload --provision     # reboot, apply changes, and re-run provisioners
vagrant halt [name]            # power off
vagrant destroy -f [name]      # delete the VM
vagrant ssh [name]             # shell into the guest
vagrant status                 # state of this project's machines
vagrant global-status --prune  # all machines on the host
vagrant validate               # check Vagrantfile syntax
vagrant box list               # cached boxes (box update to refresh)
```

Rule of thumb: network or hardware change → `reload`; provisioning script change →
`provision`.

## 12. Troubleshooting

Port collision. `Vagrant found a port collision for the specified port`: a forwarded
host port is already in use, often because the same `forwarded_port` was applied to
several machines through the outer `config`. Move it onto the correct machine's block
variable, remove unneeded forwards, or use `auto_correct: true`.

Interactive bridge prompt. `vagrant up` asks which interface to bridge: the
`public_network` bridge name does not exist on this host. Remove the public network if it
is not needed, or name an interface that exists.

VM killed at boot (signal 9). `terminated unexpectedly during startup because of signal
9`: the host OS killed the VirtualBox process (SIGKILL). If the VM's `Logs/VBox.log` was
never written and there is no crash report, the kill came from outside the VM, typically
host security after an OS update. On macOS: update VirtualBox, approve it under System
Settings → Privacy & Security, and reboot.

Machine locked. `another process is already executing an action on the machine`: another
Vagrant command is running against the same machine. Wait for it to finish, or check for
leftover `vagrant`/`ruby` processes.

Host-only IP rejected. VirtualBox refuses a private network IP outside its allowed
ranges: add the range to `/etc/vbox/networks.conf` (for example `* 192.168.56.0/21`).

Provisioner failed. Fix the script and re-run `vagrant provision` rather than recreating
the VM; well-written scripts are safe to run again.

See also: [p1 Notes: 8. Problems encountered](p1-notes.md#8-problems-encountered).

## 13. Review questions

1. What are the four parts Vagrant ties together? — Vagrantfile, box, provider,
   provisioner.
2. When do provisioners run automatically? — Only on the first `vagrant up` of a machine.
3. Which command applies a network change, and which re-runs scripts? — `vagrant reload`;
   `vagrant provision`.
4. Why must per-machine settings use the block variable instead of `config`? — Settings on
   `config` apply to every machine.
5. Which network gives internet access, and which connects VMs to each other? — NAT;
   private network.
6. Why can an interface name like `eth1` start pointing at a different network? — Names
   follow adapter order; adding an adapter renumbers the ones after it.
7. What does a signal 9 at boot with no VM log indicate? — The host OS killed the process,
   not a configuration error inside the VM.

## 14. Glossary

- Box: packaged base image a VM is built from.
- Provider: the hypervisor that runs the VM (VirtualBox).
- Provisioner: mechanism that configures the guest after boot.
- Vagrantfile: Ruby file describing one or more machines.
- Guest: the virtual machine. Host: the physical computer running it.
- NAT: adapter giving the guest internet access through the host.
- Host-only / private network: network shared by the host and its VMs only.
- Bridged / public network: connects the VM directly to the physical LAN.
- Forwarded port: a host port mapped to a guest port.
- Synced folder: a host directory mounted inside the guest (`/vagrant` by default).
- Idempotent: safe to run repeatedly with the same result.

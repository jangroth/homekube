# Ansible Roles and Playbooks

This directory contains Ansible playbooks and roles for setting up and managing a Kubernetes cluster on Raspberry Pi nodes.

## Overview of Playbooks

| Playbook | Description |
|----------|-------------|
| `01-update-control-node.yml` | Updates the control node with necessary tools and configurations |
| `02-prepare-pis.yml` | Prepares Raspberry Pi nodes with basic configuration and NVMe setup |
| `03-setup-k8s-nodes.yml` | Configures nodes for Kubernetes installation |
| `04-setup-k8s-control-plane.yml` | Prepares the control plane node for kubeadm |
| `05-setup-gitops.yml` | Installs and configures ArgoCD for GitOps operations |

## Roles

### 1. control-node

This role updates and configures the control node (your local machine) with necessary configurations and tools to manage the Kubernetes cluster.

**Tasks:**

- Update `/etc/hosts` file with cluster node information
- Update `~/.ssh/known_hosts` for seamless SSH connections
- Configure `~/.ssh/config` for SSH access
- Install management tools (k9s, helm, cilium-cli)

**Usage:**

```shell
# Install everything
ansible-playbook 01-update-control-node.yml --ask-become-pass

# Update tools only
ansible-playbook 01-update-control-node.yml --tags update-only
```

**Supported Tags:**

- `update-only`: Only update the management tools (k9s, helm, cilium-cli)

### 2. raspberry-pi

Semi-automated role to run basic Pi configuration and set up NVMe storage. Most tasks are one-time operations (non-idempotent).

**Tasks:**

- Create user accounts
- Update system packages
- Configure SSH for key-based authentication
- Enable PCIe for NVMe support
- Configure NVMe storage

**Usage:**

```shell
# Initial setup of SSH and system configuration
ansible-playbook 02-prepare-pis.yml --tags init --limit pi0|1|2

# After manual bootloader update and SD-to-NVMe copy, configure NVMe storage
ansible-playbook 02-prepare-pis.yml --tags nvme --limit pi0|1|2
```

**Supported Tags:**

- `init`: Initial setup (user accounts, system updates, SSH configuration)
- `nvme`: NVMe storage configuration

**Manual Steps Required:**
After running the initial setup, you need to manually update the Pi bootloader and copy the SD card to NVMe:

```shell
rpi-eeprom-update
raspi-config # -> confirm bootloader
sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 status=progress
```

### 3. k8s-node

Automated role to prepare Raspberry Pi nodes for Kubernetes installation.

**Tasks:**

- Update system packages
- Disable swap (required for Kubernetes)
- Configure networking for Kubernetes
- Configure cgroups
- Set up storage for container runtime
- Install container runtime
- Install Kubernetes packages

**Usage:**

```shell
# Configure all nodes
ansible-playbook 03-setup-k8s-nodes.yml --limit pi0|1|2

# Update system packages only
ansible-playbook 03-setup-k8s-nodes.yml --tags update-only
```

**Supported Tags:**

- `update-only`: Update system packages and storage configuration, display dependencies
- `unhold-kube`: Unhold Kubernetes packages for updates

### 4. k8s-control-plane

This role prepares the control plane node for kubeadm by copying necessary configuration files.

**Tasks:**

- Copy kubeadm configuration files to the control plane node

**Usage:**

```shell
ansible-playbook 04-setup-k8s-control-plane.yml --tags update-only
```

**Supported Tags:**

- `update-only`: Update the kubeadm configuration files

### 5. gitops

This role installs and configures ArgoCD for GitOps operations on the Kubernetes cluster.

**Tasks:**

- Create ArgoCD namespace
- Install ArgoCD using Helm
- Deploy root ArgoCD application for managing all applications

**Usage:**

```shell
# Install ArgoCD and setup GitOps
ansible-playbook 05-setup-gitops.ym
```

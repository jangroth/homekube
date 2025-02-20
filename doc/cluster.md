# Cluster

<!-- TOC -->
* [Cluster](#cluster)
* [Configuration & Logs](#configuration--logs)
  * [containerd](#containerd)
  * [CNI-plugins](#cni-plugins)
* [Setup](#setup)
  * [1. Manual Prep](#1-manual-prep)
    * [1.1. Control machine](#11-control-machine)
    * [1.2. Home router](#12-home-router)
    * [1.3. Pi nodes](#13-pi-nodes)
    * [1.4. Control machine](#14-control-machine)
    * [1.5. Control machine](#15-control-machine)
  * [2. Ansible](#2-ansible)
* [Notes](#notes)
<!-- /TOC -->

## Configuration & Logs

### containerd
- conf
  - `/etc/containerd/config.toml`
  - `/etc/systemd/system/containerd.service`
- logs
  - `journalctl -u containerd.service`

### CNI-plugins
- conf
  - `/etc/cni/net.d/`

## Setup

### 1. Manual prep

#### 1.1. Control machine
- Create images
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

#### 1.2. Home router
- Assign static IPs

#### 1.3. Pi nodes
- Configure root user on each machine

```shell
ssh user@pi0 #/pi1/pi2
sudo passwd root
sudo vi /etc/ssh/sshd_config # PermitRootLogin yes
sudo systemctl restart ssh 
```

#### 1.4. Control machine
- Edit `/etc/hosts`
- Confirm `~/.ssh/known_hosts`
- Create and distribute ssh key

```shell
ssh-keygen # id_homekube

chmod 600 ~/.ssh/id_homekube
chmod 644 ~/.ssh/id_homekube.pub

ssh-copy-id -i ~/.ssh/id_homekube root@pi0 # pi0/1/2
ssh -i ~/.ssh/id_homekube root@pi0 #pi0/1/2
```

#### 1.5. Control machine
- edit `~/.ssh/config`

```shell
Host pi0
  HostName 192.168.86.220
  User root
  IdentityFile ~/.ssh/id_homekube
```
### 2. Ansible
- Run ansible playbook

```shell
ansible-playbook setup-nodes.yml
```

## Notes
- Kernel options as per original image

```shell
cat /boot/firmware/cmdline.txt
console=serial0,115200 console=tty1 root=PARTUUID=b5376a11-02 rootfstype=ext4 fsck.repair=yes rootwait cfg80211.ieee80211_regdom=AU
```

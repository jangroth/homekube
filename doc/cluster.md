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

### kubernetes
- conf
  - `/etc/kubernetes`
  
### api-server
- log
  - `k logs -n kube-system -f kube-apiserver-pi0`

### scheduler
- log
  - `k logs -n kube-system -f kube-scheduler-pi0`

### kubelet
- conf
  - `/var/lib/kubelet`
  - `/lib/systemd/system/kubelet.service`
- logs
  - `journalctl -b -u kubelet.service`

### containerd
- conf
  - `/etc/containerd/config.toml`
  - `/etc/systemd/system/containerd.service`
- logs
  - `journalctl -b -u containerd.service`

### CNI-plugins
- conf
  - `/etc/cni/net.d/`

## Setup

⚠️ The following steps outline the tasks required to install Kubernetes on _my_ Raspberry Pi cluster. It's likely that _your_ cluster is  different. Use this repository as a guide, but don't expect every step to work for your setup.

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
### 2. Automated installation pre kubeadm
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

### 3. kubeadm

#### 3.1 Initialize control plane
- Run kubeadm init
```shell
kubeadm config print init-defaults
kubeadm init --dry-run --config ~/kubeadm-config.yaml
kubeadm init --config ~/kubeadm-config.yaml
```

- Confirm kubelet config has `cgroupDriver` set to `systemd`

- CNI installation
```shell
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

#### 3.2 Add nodes to cluster
- Join nodes to cluster
```shell
kubeadm join 10.0.0.20:6443 --token abcde \
	--discovery-token-ca-cert-hash sha256:12345 
```

#### 3.3 Later changes
- Generate kubeadm config from existing cluster
```shell
kubectl get configmap kubeadm-config -n kube-system -o yaml
```
- E.g. Add SAN to certs
```shell
# remove old keys
rm /etc/kubernetes/pki/apiserver.crt
rm /etc/kubernetes/pki/apiserver.key
# regenerate cert
kubeadm init phase certs apiserver --config ~/kubeadm-config.yaml
# restart api-server
```

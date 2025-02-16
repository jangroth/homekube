# Cluster

## Configuration & Logs

### containerd
- conf:
  - `/etc/containerd/config.toml`
  - `/etc/systemd/system/containerd.service`
- logs
  - `journalctl -u containerd.service`

### CNI-plugins
Conf:
  - `/etc/cni/net.d/`


## Setup

### Manual

#### Control machine
- Create images
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

#### Router
- Assign static IPs

#### Nodes
- Configure root user on each machine

```shell
ssh user@pi0 #/pi1/pi2
sudo passwd root
sudo vi /etc/ssh/sshd_config # PermitRootLogin yes
sudo systemctl restart ssh 
```

#### Control machine
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

#### Control machine
- edit `~/.ssh/config`

```shell
Host pi0
  HostName 192.168.86.220
  User root
  IdentityFile ~/.ssh/id_homekube
```
### Automated
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

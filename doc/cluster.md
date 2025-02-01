# Cluster

## Overview

| Static IP | Internal IP | Hostname |
|-----------|------------|----------|
| 192.168.86.220 | 10.0.0.20 | pi0 |
| 192.168.86.221 | 10.0.0.21 | pi1 |
| 192.168.86.222 | 10.0.0.22 | pi2 |

## Setup

### Control machine
- Create images
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

### Router
- Assign static IPs

### Nodes
- Configure root user on each machine

```shell
ssh user@pi0 #/pi1/pi2
sudo passwd root
sudo vi /etc/ssh/sshd_config # PermitRootLogin yes
sudo systemctl restart ssh 
```

### Control machine
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
### Control machine
- edit `~/.ssh/config`

```shell
Host pi0
  HostName 192.168.86.220
  User root
  IdentityFile ~/.ssh/id_homekube
```

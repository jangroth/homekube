# 1. Manual prep

## 1.1. Control machine
- Create images for nodes
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

## 1.2. Pi nodes
- Boot and join network

## 1.3. Home router
- Assign static IPs 

## 1.4. Pi nodes
- Configure root user:

```shell
ssh user@pi0 #/pi1/pi2
sudo passwd root
sudo vi /etc/ssh/sshd_config # PermitRootLogin yes
sudo systemctl restart ssh 
```

## 1.4. Control machine
- Edit `/etc/hosts`, add nodes:

```
[...]
192.168.86.220 pi0.kubernetes.local, pi0
192.168.86.221 pi1.kubernetes.local, pi1
192.168.86.222 pi2.kubernetes.local, pi2
[...]
```

- Confirm `~/.ssh/known_hosts`, check for leftover keys
- Create and distribute ssh key for control machine to log into nodes

```shell
ssh-keygen # id_homekube

chmod 600 ~/.ssh/id_homekube
chmod 644 ~/.ssh/id_homekube.pub

ssh-copy-id -i ~/.ssh/id_homekube root@pi0 # pi0/1/2
ssh -i ~/.ssh/id_homekube root@pi0 #pi0/1/2
```

- edit `~/.ssh/config`:

```shell
Host pi0 # pi0/1/2
  HostName 192.168.86.220 # 220/221/222
  User root
  IdentityFile ~/.ssh/id_homekube
```

## 1.5 Verify

```shell
ssh pi0 # pi0/1/2
Linux pi0 6.6.74+rpt-rpi-2712 
[...]
root@pi0:~#
```

# 1. Prepare Pis and control node

## 1.1. Control node

- Create images for nodes
  - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)
  - Hostname pi0-p3, username - boot, password - boot, ssid, password, ...

## 1.2. Pi nodes

- Disconnect nvme
- Boot and join network

## 1.3. Home router

- Assign static IPs, reboot

## 1.4 Control node & Pis

- Connect nvme drive
- Run the following playbooks in order (see [ansible/README.md](../ansible/README.md) for details):

```shell
# upates control node (/etc/hosts, ...)
ansible-playbook 01-update-control-node.yml --ask-become-pass

# configure pi
ansible-playbook 02-prepare-pis.yml --tags init --limit pi1

# pick latest bootloader, reboot
ssh pi1
sudo raspi-config

# copy sd card to nvme (~25min)
sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 status=progress
sudo shutdown now

# remove sd card, reboot (leave boot order sd first)
sudo lsblk
sudo parted /dev/nvme0n1 mkpart primary ext4 128GB 1000GB
sudo mkfs.ext4 /dev/nvme0n1p3
sudo parted -s /dev/nvme0n1 print
mkdir /storage
vi /etc/fstab

# configure nvme on pi
ansible-playbook 02-prepare-pis.yml --tags nvme --limit pi1

# kubernetes node configuration
ansible-playbook 03-setup-k8s-nodes.yml --limit pi1
# update other nodes about new node
ansible-playbook 03-setup-k8s-nodes.yml 
```

## 1.5 Control plane node & Pi node

```
sudo kubeadm token create --print-join-command
kubeadm join 10.0.0.20:6443 --token 6f2b5h.seu8yc3upi8ji3m7 --discovery-token-ca-cert-hash sha256:249edc49bf84547ff8b10a84d494b88ebb36b661a4340b393aa7b05ae2e6779e
```

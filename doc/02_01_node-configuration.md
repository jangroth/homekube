# 1. Prepare Pis and control node

## 1.1. Control node

- Create images for nodes
  - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)
  - Hostname, username, password, ssid, password, ...

## 1.2. Pi nodes

- Disconnect nvme
- Boot and join network

## 1.3. Home router

- Assign static IPs, reboot

## 1.4 Control node

- Connect nvme drive
- Run the following playbooks in order (see [ansible/README.md](../ansible/README.md) for details):

```shell
# upates control node (/etc/hosts, ...)
ansible-playbook 01-update-control-node.yml --ask-become-pass

# configure pi
ansible-playbook 02-prepare-pis.yml --tags init --limit pi3

# pick latest bootloader, reboot
sudo raspi-config 

# copy sd card to nvme (~25min)
sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 status=progress

# remove sd card, reboot (leave boot order sd first)

sudo parted /dev/nvme0n1 mkpart primary ext4 128GB 1000GB
sudo mkfs.ext4 /dev/nvme0n1p3
sudo parted -s /dev/nvme0n1 print
vi /etc/fstab

# configure nvme on pi
ansible-playbook 02-prepare-pis.yml --tags nvme --limit pi3

# kubernetes node configuration
ansible-playbook 03-setup-k8s-nodes.yml --limit pi3
# update other nodes about new node
ansible-playbook 03-setup-k8s-nodes.yml 
```

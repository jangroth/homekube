# prepare-pis

Semi-automated role to run basic Pi configuration and set up NVMe. Mostly once-off (non-idempotent).

## Ansible: Setup ssh
```shell
ansible-playbook 02-prepare-pis.yml --tags init --limit pi0|1|2
```

## Manual: Pi bootloader & copy SD to NVMe

```shell
rpi-eeprom-update
raspi-config # -> confirm bootloader
sudo dd if=/dev/mmcblk0 of=/dev/nvme0n1 status=progress
```
https://learn.pimoroni.com/article/getting-started-with-nvme-base

## Ansible: Create storage partition

```shell
ansible-playbook 02-prepare-pis.yml --tags nvme --limit pi0|1|2
```

# 1. Prepare Pis and control node

## 1.1. Control node
- Create images for nodes
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

## 1.2. Pi nodes
- Boot and join network

## 1.3. Home router
- Assign static IPs

## 1.4 Control node

- Run [playbook](../ansible/roles/update-control-node/README.md) to update control node itself
- Run [playbook](../ansible/roles/prepare-pis/README.md) to prepare pis for ansible
- Run [playbook](../ansible/roles/setup-nodes/README.md) to install and configure pis for Kubernetes
- Run [playbook](../ansible/roles/control-plane/README.md) to prepare the control plane for kubeadm

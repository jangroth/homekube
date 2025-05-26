# 1. Prepare Pis and control node

## 1.1. Control node
- Create images for nodes
    - Raspberry Pi Imager -> Raspberry Pi OS Lite (64b)

## 1.2. Pi nodes
- Boot and join network

## 1.3. Home router
- Assign static IPs

## 1.4 Control node

Run the following playbooks in order (see [ansible/README.md](../ansible/README.md) for details):

- [01-update-control-node](../ansible/01-update-control-node.yml) to update the control node 
- [02-setup-raspberry-pi](../ansible/02-setup-raspberry-pi.yml) to run basic Pi configuration
- [03-setup-k8s-nodes](../ansible/03-setup-k8s-nodes.yml) to configure the nodes for Kubernetes
- [04-setup-k8s-control-plane](../ansible/04-setup-k8s-control-plane.yml) to configure the control plane for Kubernetes
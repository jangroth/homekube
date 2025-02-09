# Homekube

Running Kubernetes on Raspberry Pi.

![Homekube](./doc/homekube.png)

## Overview

| Hostname | Device | OS | Static IP | Internal IP |
|-|-|-|-|-|
| pi0 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.220 | 10.0.0.20 |
| pi1 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.221 | 10.0.0.21 | 
| pi2 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.222 | 10.0.0.22 |

### Dependencies

- Kubernetes - tbd
- Container Runtime
    - `containerd` - 2.0.0
    - `cni plugins` - tbd
    - `runc` - tbd

## Documentation / Notes

- [Cluster setup](./doc/cluster.md)
- [Ansible playbooks](./ansible-project/ansible.md)

## Thanks / References / Inspiration

- ['Kubernetes the hard way'](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/master) - Kelsey Hightower
- ['How to install Kubernetes on Raspberry PI'](https://medium.com/karlmax-berlin/how-to-install-kubernetes-on-raspberry-pi-53b4ce300b58) - Ralph Bergmann
- [Kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/)

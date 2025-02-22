# Homekube

Running Upstream Kubernetes on Raspberry Pi.

![Homekube](./doc/homekube.png)

<!-- TOC -->
- [Overview](#overview)
    - [Dependencies](#dependencies)
- [Documentation / Notes](#documentation--notes)
- [References / Inspiration](#thanks--references--inspiration)
<!-- /TOC -->

## Overview

| Hostname | Device | OS | Static IP | Internal IP |
|-|-|-|-|-|
| pi0 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.220 | 10.0.0.20 |
| pi1 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.221 | 10.0.0.21 | 
| pi2 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.222 | 10.0.0.22 |

### Dependencies

- Kubernetes
    - `kubectl` - _1.31.6_
    - `kubelet` - _1.31.6_
    - `kubeadm` - _1.31.6_

- CRI
    - `containerd` - _2.0.0_
    - `runc` - _1.1.5_
- CNI
    - `containernetworking-plugins` - _1.1.1_

## Documentation / Notes

- [Cluster setup](./doc/cluster.md)

## References / Inspiration

- ['Kubernetes the hard way'](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/master) - Kelsey Hightower
- ['How to install Kubernetes on Raspberry PI'](https://medium.com/karlmax-berlin/how-to-install-kubernetes-on-raspberry-pi-53b4ce300b58) - Ralph Bergmann
- [Kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/)

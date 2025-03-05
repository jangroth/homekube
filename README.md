# Homekube

Running Upstream Kubernetes on Raspberry Pi.

---

<div style="display: flex; justify-content: space-around;">
  <img src="./doc/images/logo-kubernetes.svg.png" alt="kubernetes" style="height: 50px;">
  <img src="./doc/images/logo-argocd.png" alt="argocd" style="height: 50px;">
  <img src="./doc/images/logo-flannel.png" alt="flannel" style="height: 50px;">
  <img src="./doc/images/logo-metallb.png" alt="metallb" style="height: 50px;">
</div>

---

![Homekube](./doc/images/homekube.png)

---

![Homekube](./doc/images/k9s.png)

---

<!-- TOC -->
- [Overview](#overview)
- [Documentation / Notes](#documentation--notes)
- [References / Inspiration](#thanks--references--inspiration)
<!-- /TOC -->

---

## Overview

### Components
| Component | Package | Version |
|-|-|-|
| Kubernetes | `k8s` | _1.31.6_ |
| CRI | `containerd` | _2.0.0_ |
| | `runc` | _1.1.5_ |
| CNI | `flannel` | _0.26.4_ |
| | `containernetworking-plugins` | _1.1.1_ |
| CSI | `longhorn` | tbd |

### Nodes

| Hostname | Device | OS | Static IP | Internal IP |
|-|-|-|-|-|
| pi0 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.220 | 10.0.0.20 |
| pi1 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.221 | 10.0.0.21 | 
| pi2 | Raspberry Pi 5, 8GB | Raspberry Pi OS Lite 64-bit | 192.168.86.222 | 10.0.0.22 |


### Kubernetes Network Architecture

```mermaid
graph TD
    subgraph Home Network [Home Network 192.168.86.0/24]
        Router[Home Router]
    end
    
    subgraph Kubernetes Cluster
        subgraph Node1 [pi0: Control Plane]
            Pi0[Raspberry Pi 5 8GB]
            Pi0_ext[192.168.86.220]
            Pi0_int[10.0.0.20]
        end
        
        subgraph Node2 [pi1: Worker]
            Pi1[Raspberry Pi 5 8GB]
            Pi1_ext[192.168.86.221]
            Pi1_int[10.0.0.21]
        end
        
        subgraph Node3 [pi2: Worker]
            Pi2[Raspberry Pi 5 8GB]
            Pi2_ext[192.168.86.222]
            Pi2_int[10.0.0.22]
        end
        
        subgraph K8s Services [Kubernetes Services]
            API[kube-apiserver</br> Cluster Ip Network</br>10.96.0.0/12]
            CNI[Flannel CNI]
            Pods[Pod Network</br> 10.244.0.0/16]
        end

        InternalSwitch[Internal Network Switch 10.0.0.0/24]
    end
    
    Router -- External Network --> Pi0_ext
    Router -- External Network --> Pi1_ext
    Router -- External Network --> Pi2_ext
    
    Pi0_int -- Internal Network --> InternalSwitch
    Pi1_int -- Internal Network --> InternalSwitch
    Pi2_int -- Internal Network --> InternalSwitch
    
    Pi0 -- Hosts --> API
    API -- Controls --> CNI
    CNI -- Manages --> Pods
```
### Kubernetes Cluster Architecture

```mermaid
graph TD
    subgraph Kubernetes Cluster
        subgraph ControlPlane [pi0: Control Plane]
            API[kube-apiserver]
            Cont_manager[kube-controller-manager]
            Scheduler[kube-scheduler]
            Etcd[etcd]
        end
        
        subgraph DataPlane [pi1, pi2: Data Plane]
            subgraph NsArgo[ArgoCD]
                argocd[ArgoCD]
                argocd_svc[ArgoCD Service</br> NodePort</br> 30000]
                aoa[Root App]
                app1
                app2
            end
        end
    end

    argocd_svc -- Exposes --> argocd
    argocd -- Deploys --> aoa
    aoa --> app1
    aoa --> app2

```

### Details

See [Configuration & Logs](./doc/01_conf_logs.md).

## Setup

⚠️ The following steps outline the tasks required to install Kubernetes on _my_ Raspberry Pi cluster. It's likely that _your_ cluster is  different. Use this repository as a guide, but don't expect every step to work for your system.

1. [Environment preparation](./doc/02_env_preparation.md) (manual)
2. [Node configuration](./doc/02_node_configuration.md) (Ansible)
3. [Kubernetes installation](./doc/02_kube_installation.md) (kubeadm, semi-manual)
4. [ArgoCD rollout & App of Apps deployment](./doc/02_argo_rollout.md) (OpenTofu/tf)
5. [ArgoCD applications repository](https://github.com/jangroth/homekube-apps)

## References / Inspiration

- ['Kubernetes the hard way'](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/master) - Kelsey Hightower
- ['How to install Kubernetes on Raspberry PI'](https://medium.com/karlmax-berlin/how-to-install-kubernetes-on-raspberry-pi-53b4ce300b58) - Ralph Bergmann
- [Kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/)

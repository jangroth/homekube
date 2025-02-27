## Configuration & Logs

### kubernetes
- conf
  - `/etc/kubernetes`
  
### api-server
- log
  - `k logs -n kube-system -f kube-apiserver-pi0`

### scheduler
- log
  - `k logs -n kube-system -f kube-scheduler-pi0`

### kubelet
- conf
  - `/var/lib/kubelet`
  - `/lib/systemd/system/kubelet.service`
- logs
  - `journalctl -b -u kubelet.service`

### containerd
- conf
  - `/etc/containerd/config.toml`
  - `/etc/systemd/system/containerd.service`
- logs
  - `journalctl -b -u containerd.service`

### CNI-plugins
- conf
  - `/etc/cni/net.d/`
- bin
  - `/opt/cni/bin`
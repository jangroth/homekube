## Configuration & Logs

### kubernetes
- conf
  - `/etc/kubernetes`
  
### api-server
- conf
  - `service-cluster-ip-range`: 10.96.0.0/12 # 1,048,574 (10.96.0.0 -> 10.111.255.255)
- log
  - `k logs -n kube-system -f kube-apiserver-pi0`

### scheduler
- log
  - `k logs -n kube-system -f kube-scheduler-pi0`

### kubelet
- conf
  - `/var/lib/kubelet`  
  - `/var/lib/kubelet/pki`
  - `/var/lib/kubelet/config.yaml`
  - `/lib/systemd/system/kubelet.service`

- via API server:
```shell
kubectl proxy
curl -X GET http://127.0.0.1:8001/api/v1/nodes/pi0/proxy/configz | jq # pi0,1,2
```


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

### CNI
- `pod-network-cidr`:10.244.0.0/16 # 65,536 (10.244.0.0 -> 10.244.255.255)
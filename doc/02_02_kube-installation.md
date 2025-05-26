# 3. kubeadm & CNI

## 3.0 Reset previous installation

```shell
cilium uninstall
sudo kubeadm reset --force
sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet /etc/kubernetes
sudo reboot 0
ansible-playbook 03-setup-k8s-nodes.yml
sudo reboot 0
```

## 3.1 Initialize control plane

- Verify [kubeadm-config.yaml](../ansible/roles/k8s-control-plane/files/kubeadm-config.yaml)
- Verify [cilium-helm-values.yaml](../ansible/roles/k8s-control-plane/files/cilium-helm-values.yaml)

### On control node...
```shell
ansible-playbook 04-setup-k8s-control-plane.yml
```

### On pi0...
```shell
sudo kubeadm init --config ~/kubeadm-config.yaml | tee ~/install_k8s.log
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

- kubeadm runs without errors
- pi0 node "not ready"

### On control node...
```shell
scp pi0:~/install_k8s.log ../downloads
scp pi0:~/.kube/config ~/.kube/config
vi ~/.kube/config # change ip 
```
### On pi0...
```shell
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.17.2 \
   --namespace kube-system \
   -f ~/cilium-helm-values.yaml | tee ~/install_cilium.log
```
- pi0 node ready
- scale cilium deploy to 1
- approve pending csrs
- reboot
- approve (new) pending csrs

### On control node...
```shell
scp pi0:~/install_cilium.log ../downloads
```

### On pi1, pi2...
- join nodes

### On control node
- approve kubelet CSR

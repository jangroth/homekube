# 3. k8s, CNI (cilium), CSI (longhorn)

## 3.0 Optional: Reset previous installation

```shell
longhorn uninstall 
cilium uninstall
sudo kubeadm reset --force
sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet /etc/kubernetes
sudo reboot 0
ansible-playbook 03-setup-k8s-nodes.yml
sudo reboot 0
```

## 3.1 Initialize control plane (k8s)

- Verify [kubeadm-config.yaml](../ansible/roles/k8s-control-plane/files/kubeadm-config.yaml)
- Verify [cilium-helm-values.yaml](../ansible/roles/k8s-control-plane/files/cilium-helm-values.yaml)
- Verify [longhorn-helm-values.yam](../ansible/roles/k8s-control-plane/files/longhorn-helm-values.yaml)

On control node:

```shell
ansible-playbook 04-setup-k8s-control-plane.yml
```

On pi0:

```shell
sudo kubeadm init --config ~/kubeadm-config.yaml | tee ~/install_k8s.log
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

- kubeadm runs without errors
- pi0 node "not ready"

On control node:

```shell
scp pi0:~/install_k8s.log ../downloads
scp pi0:~/.kube/config ~/.kube/config
vi ~/.kube/config # change ip
ansible-playbook 05-setup-cni.yml
```

- pi0 node ready
- approve pending csrs
- reboot
- approve (new) pending csrs

On control node

## 3.2 Add worker nodes

### On pi1, pi2

- join nodes

### On control node

- approve kubelet CSR

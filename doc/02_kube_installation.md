# 3. kubeadm & CNI

## 3.1 Initialize control plane

- Verify [kubeadm-config.yaml](../ansible/roles/kubeadm/files/kubeadm-config.yaml)




- Run kubeadm init
```shell
kubeadm config print init-defaults
kubeadm init --dry-run --config ~/kubeadm-config.yaml
kubeadm init --config ~/kubeadm-config.yaml
```

- Confirm kubelet config has `cgroupDriver` set to `systemd`

- CNI installation
```shell
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

## 3.2 Add nodes to cluster
- Join nodes to cluster
```shell
kubeadm join 10.0.0.20:6443 --token abcde \
	--discovery-token-ca-cert-hash sha256:12345 
```

## 3.3 Later changes
- Generate kubeadm config from existing cluster
```shell
kubectl get configmap kubeadm-config -n kube-system -o yaml
```
- E.g. Add SAN to certs
```shell
# remove old keys
rm /etc/kubernetes/pki/apiserver.crt
rm /etc/kubernetes/pki/apiserver.key
# regenerate cert
kubeadm init phase certs apiserver --config ~/kubeadm-config.yaml
# restart api-server
```




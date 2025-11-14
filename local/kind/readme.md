# HomeKube with Kind

```
colima start
kind get clusters
kind delete cluster --name corekube
```

```
docker pause corekube-worker; docker pause corekube-control-plane
docker unpause corekube-worker; docker unpause corekube-control-plane
```

## Default (./local/kind/kind-config.yaml)

```
kind create cluster --name corekube --config ./local/kind/kind-config.yaml
```

## Cilium (./local/kind/kind-config-cilium.yaml)

```
kind create cluster --name corekube-cilium --config ./local/kind/kind-config-cilium.yaml
cilium install
cilium status
```

## Ingress (./local/kind/kind-config-ingress.yaml)

[reference](https://kind.sigs.k8s.io/docs/user/ingress/)

```
kind create cluster --name corekube-ingress --config ./local/kind/kind-config-ingress.yaml
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/usage.yaml
```

## Kube Dashboard

```
kind create cluster --name kube-dashboard --config ./local/kind/kind-config.yaml
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo search kubernetes-dashboard
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --version 7.13.0
```

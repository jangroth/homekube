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
k create ns cks1
k create ns cks2

k run nginx1 --image=nginx --namespace=cks1
k expose pod nginx1 --port=80 --target-port=80 --namespace=cks1
k run nginx3 --image=nginx --namespace=cks1
k expose pod nginx3 --port=80 --target-port=80 --namespace=cks1
k run nginx2 --image=nginx --namespace=cks2
k expose pod nginx2 --port=80 --target-port=80 --namespace=cks2

```

## Ingress (./local/kind/kind-config-ingress.yaml)

[reference](https://kind.sigs.k8s.io/docs/user/ingress/)

```
kind create cluster --name corekube-ingress --config ./local/kind/kind-config-ingress.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/usage.yaml
curl localhost/foo
curl localhost/bar
```

## Istio (./local/kind/kind-config-istio.yaml)

```
kind create cluster --name corekube-istio --config ./local/kind/kind-config-istio.yaml
docker exec -it corekube-istio-control-plane bash
curl -L https://istio.io/downloadIstio | sh -
./istio-1.28.0/bin/istioctl install
```

## Kube Dashboard

```
kind create cluster --name kube-dashboard --config ./local/kind/kind-config.yaml
helm repo add kubernetes-dashboard <https://kubernetes.github.io/dashboard>
helm repo search kubernetes-dashboard
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --version 7.13.0
```


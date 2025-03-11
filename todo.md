## Todos

### Current

- Metrics Server
    https://github.com/kubernetes-sigs/metrics-server#requirements
->    !!! Kubelet certificate needs to be signed by cluster Certificate Authority (or disable certificate validation by passing --kubelet-insecure-tls to Metrics Server) !!!
    https://github.com/kubernetes-sigs/metrics-server/blob/master/FAQ.md#how-to-run-metrics-server-securely
    https://github.com/kubernetes-sigs/metrics-server/issues/146#issuecomment-459239615
    https://github.com/kubernetes-sigs/metrics-server/issues/576#issuecomment-1820504816

    - ns: metrics-server
-> change kubeadmin config map


### Queue

- ArgoCD
    - LB/TLS setup
    - create argocd projects
    - OIDC
- Implement storage
    - install ssds
    - partition & configure
    - Longhorn
    - s3-csi-driver
- Implement observability
    - Prometheus/Grafana/Loki
    - RaspPi metrics
- Upgrade networking capabilities
    - Cilium
- TLS
    - certmanager
    - write code to update DNS entry on domain with my ip
    - mtls (istio ambient)
- External Connectivity
    - Traefik/Cloudflare/Wireguard/tailscale
- SSO
    - KeyCloak/Crossplane
    - Google OIDC
- service-mesh
    - istio
- Secrets
    - Vault
    - https://external-secrets.io/latest/
- Set up Container registry
- Loadbalancer
    - nginx controller
    - api-gateway
- Security
    - kube-sec, kube-linter
    - kube-bench

### Later
- implement script to check for new releases of everything that's installed
- create user/context for opentofu deployments
- disable password logins on nodes after ssh keys have been configured
- consider ansible-lint
    
## Notes

./.
## Todos

### Current

- 1.31.6 -> 1.32.x



### Queue
- backups
    - etcd
- MetalLB
    - set up loadbalancer class
- kube-dashboard
    - argo app
    - configure for raspi usage
    - user/sa to access
- argocd
    - root-app deletion deletes apps, but not resources
    - move namespace into app manifests
- DNS
    - bind9
- Identity provider
    - Authentik?
    - ArgoCD
    - Dashboard
- ArgoCD
    - LB/TLS setup
    - create argocd projects
    - OIDC
- Implement storage
    - Longhorn
    - s3-csi-driver
    - minio
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

- https://picluster.ricsanfre.com/docs/home/
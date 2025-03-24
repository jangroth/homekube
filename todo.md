## Todos

### Current
root@pi2:/home/homekube# vcgencmd bootloader_version
2025/03/10 17:10:37
version 2bb2ae640058a2f3aa8dcbdc2da33302e509668d (release)
timestamp 1741626637
update-time 1742765095
capabilities 0x0000007f

homekube@pi2:~ $ rpi-eeprom-config
[all]
BOOT_UART=1
POWER_OFF_ON_HALT=0
BOOT_ORDER=0xf461

-> SD, NVME, USB

restore color for bash shell



### Queue
- Longhorn
    - install via helm chart
    - configure to use storage partition
- Implement persistent storage
    - Longhorn
    - s3-csi-driver
    - secret-store-csi driver -> https://github.com/kubernetes-sigs/secrets-store-csi-driver
    - minio
- Implement observability
    - Prometheus/Grafana/Loki
        - store prometheus data on longhorn volumes
    - RaspPi metrics
- Identity provider
    - Authentik?
- SSO
    - KeyCloak/Crossplane
    - Google OIDC
- TLS
    - certmanager
    - write code to update DNS entry on domain with my ip
    - mtls (istio ambient)
- backups
    - etcd
- kube-dashboard
    - sso
    - configure for raspi usage
    - user/sa to access
- argocd
    - sso
    - LB/TLS setup
    - move namespace into app manifests
    - create argocd projects
    - ApplicationSet, pull request generator
- DNS
    - bind9, pihole?
- Upgrade networking capabilities
    - Cilium
- External Connectivity
    - Traefik/Cloudflare/Wireguard/tailscale
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
    - configure podsecurity
    - kube-sec, kube-linter
    - kube-bench
    - trivy, admission-controller for security scans https://github.com/devopstales/trivy-operator
    - Falco
- Tweak Pi
    https://www.jeffgeerling.com/blog/2024/raspberry-pi-boosts-pi-5-performance-sdram-tuning

### Later
- implement script to check for new releases of everything that's installed
- create user/context for opentofu deployments
- disable password logins on nodes after ssh keys have been configured
- consider ansible-lint
    
## Notes

- https://picluster.ricsanfre.com/docs/home/
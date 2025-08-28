# 5. ArgoCD applications

## Init Wave

`argocd.argoproj.io/sync-wave: "-1"`

- [argocd-config](https://github.com/jangroth/homekube-apps/blob/main/applications/wave-00-init/argocd-config.yaml)
- [longhorn](https://github.com/jangroth/homekube-apps/blob/main/applications/wave-00-init/longhorn.yaml)
- [metrics-server](https://github.com/jangroth/homekube-apps/blob/main/applications/wave-00-init/metrics-server.yaml)

## Apps Wave

`argocd.argoproj.io/sync-wave: "1"`
<!-- 
- [test-lb](https://github.com/jangroth/homekube-apps/blob/main/applications/wave-01-apps/test-lb.yaml) -->

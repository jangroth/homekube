# 4. ArgoCD rollout

## 4.1. Deploy via OpenTofu

- Run deployment commands

```shell
ansible-playbook 06-setup-gitops.yml
```

- This will deploy ArgoCD as well as a [root-app](../tofu/manifests/argocd-root-app.yaml) ("App of apps"-pattern).

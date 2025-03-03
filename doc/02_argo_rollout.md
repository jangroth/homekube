# 4. ArgoCD rollout

## 4.1. Deploy via OpenTofu
- Run deployment commands
```shell
cd tofu
tofu init
tofu plan
tofu apply -auto-approve
```
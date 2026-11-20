# kubeadm config is the single source of kubelet config

Kubelet config comes only from `roles/k8s-control-plane/files/kubeadm-config.yaml` and `roles/k8s-worker/templates/join-config.yaml.j2` in `homekube-main`. Playbook runs re-render `/var/lib/kubelet/config.yaml` on every node, so change the templates and re-run.

Replaces [Decision 011](../archive/decisions/DECISIONS-2026-Q2.md).

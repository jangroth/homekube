## Todos

### Current
- install kube on controlplane
- install flannel
- configure kubelet

- Make sure kubelet conf has cgroup driver set to systemd (https://kubernetes.io/docs/setup/production-environment/container-runtimes/#systemd-cgroup-driver)

### Later

- remove manual cni plugins from kthw installtion ansible playbookx
- disable password logins on nodes after ssh keys have been configured
- consider ansible-lint
    
## Notes

- Possibly don't need `br_netfilter` & `overlay` kernel modules (https://www.reddit.com/r/kubernetes/comments/1dpp8iq/br_netfilter_and_overlay_swap_documentation/)
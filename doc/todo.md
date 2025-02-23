## Todos

### Current
- verify system
    - deploy pods
    - check logs
        - OK kubelet x3
        - OK containerd x3
        - OK kubeproxy x3
        - OK apiserver
        - ~ scheduler
        - OK controllermanager
- access from control node

Scheduler:
```
W0223 03:09:03.661753       1 requestheader_controller.go:196] Unable to get configmap/extension-apiserver-authentication in kube-system.  Usually fixed by 'kubectl create rolebinding -n kube-system ROLEBINDING_NAME --role=extension-apiserver-authentication-reader --serviceaccount=YOUR_NS:YOUR_SA'
W0223 03:09:03.661777       1 authentication.go:370] Error looking up in-cluster authentication configuration: configmaps "extension-apiserver-authentication" is forbidden: User "system:kube-scheduler" cannot get resource "configmaps" in API group "" in the namespace "kube-system"
```

### Later

- disable password logins on nodes after ssh keys have been configured
- consider ansible-lint
    
## Notes

- Possibly don't need `br_netfilter` & `overlay` kernel modules (https://www.reddit.com/r/kubernetes/comments/1dpp8iq/br_netfilter_and_overlay_swap_documentation/)
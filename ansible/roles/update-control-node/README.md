# update-control-node

### Updates files on localhost:
- /etc/hosts
- ~/.ssh/known_hosts
- ~/.ssh/config

### Install binaries to manage kubernetes
- k9s
- helm
- cilium-cli

```shell
ansible-playbook 01-update-control-node.yml --ask-become-pass

ansible-playbook 01-update-control-node.yml --tags update-only
```
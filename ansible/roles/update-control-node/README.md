# update-control-node

### Updates files on localhost:
- /etc/hosts
- ~/.ssh/known_hosts
- ~/.ssh/config

```shell
ansible-playbook 01-update-control-node.yml --ask-become-pass
```
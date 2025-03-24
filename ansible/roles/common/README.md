# common

Automated role to prepare Pi for Kubernetes installation.

## Ansible: Execute role

```shell
ansible-playbook 03-setup-nodes.yml --limit pi0|1|2
```
or apply updates only

```shell
ansible-playbook 03-setup-nodes.yml --tags update-only
```
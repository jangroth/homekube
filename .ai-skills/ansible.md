# Ansible Skills for homekube

**Applies to:** All playbooks in `ansible/`, roles in `ansible/roles/`

---

## 1. Variable Hierarchy: Where to Define What

**Rule:** Use the most specific scope that makes sense.

### Variable Precedence (Lowest to Highest)

1. **Role defaults** (`roles/<role>/defaults/main.yml`)
2. **Group vars** (`group_vars/all.yml`, `group_vars/raspberry_pis.yml`)
3. **Host vars** (`inventory/hosts` inline vars)
4. **Playbook vars** (`vars:` section in playbook)
5. **Command-line** (`-e "var=value"`)

### ❌ Bad Example

```yaml
# In playbook: 03-setup-k8s-nodes.yml
- name: Install containerd
  apt:
    name: containerd={{ containerd_version }}
  vars:
    containerd_version: "2.1.4"  # Wrong: version should be in group_vars
```

### ✅ Good Example

```yaml
# In group_vars/all.yml
containerd_version: "2.1.4"

# In playbook: 03-setup-k8s-nodes.yml
- name: Install containerd
  apt:
    name: "containerd={{ containerd_version }}"
```

**Where to Put Variables:**

- **Versions:** `group_vars/all.yml` (single source of truth)
- **Node-specific:** `group_vars/raspberry_pis.yml` or inline in `inventory/hosts`
- **Role defaults:** Only for "sane defaults" that users might override
- **Secrets:** Never in Git; prompt with `vars_prompt` or use Ansible Vault

---

## 2. Idempotency: Make Tasks Re-runnable

**Rule:** Every task must check state before modifying.

### ❌ Bad Example

```yaml
- name: Add Kubernetes apt repository
  shell: |
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

**Problem:** Appends duplicate lines on each run.

### ✅ Good Example

```yaml
- name: Add Kubernetes apt repository
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/ /"
    state: present
    filename: kubernetes
    update_cache: yes
```

**Key Techniques:**

- Use built-in modules (`apt`, `yum`, `copy`, `template`) instead of `shell`/`command`
- Use `creates:` argument for `shell`/`command` when unavoidable
- Check state with `stat` before modifying files
- Use `changed_when: false` for read-only tasks

---

## 3. Module Choice: Use the Right Tool

**Rule:** Always prefer built-in modules over shell commands.

### Common Replacements

| ❌ Don't Use Shell For | ✅ Use Module Instead |
|-------------------------|------------------------|
| `echo "text" > file` | `ansible.builtin.copy` or `ansible.builtin.template` |
| `mkdir -p /path` | `ansible.builtin.file` with `state: directory` |
| `apt-get install pkg` | `ansible.builtin.apt` |
| `systemctl restart svc` | `ansible.builtin.systemd` |
| `curl -O url` | `ansible.builtin.get_url` |
| `tar -xzf file.tar.gz` | `ansible.builtin.unarchive` |
| `grep pattern file` | `ansible.builtin.lineinfile` (for modifications) |

### When to Use `shell`/`command`

- **No Module Exists:** E.g., `kubeadm init`, custom binaries
- **Complex Piping:** When output of one command feeds another
- **Always Add:** `changed_when`, `failed_when`, or `creates` arguments

### Example: `shell` with Safety

```yaml
- name: Initialise Kubernetes control plane
  shell: |
    kubeadm init \
      --config /etc/kubernetes/kubeadm-config.yaml \
      --upload-certs
  args:
    creates: /etc/kubernetes/admin.conf  # Idempotency: only run if file doesn't exist
  register: kubeadm_init
  changed_when: "'Your Kubernetes control-plane has initialized successfully' in kubeadm_init.stdout"
```

---

## 4. Handlers: Restart Services Correctly

**Rule:** Use handlers for service restarts triggered by config changes.

### ❌ Bad Example

```yaml
- name: Update containerd config
  copy:
    src: config.toml
    dest: /etc/containerd/config.toml

- name: Restart containerd
  systemd:
    name: containerd
    state: restarted
```

**Problem:** Restarts even if config didn't change.

### ✅ Good Example

```yaml
- name: Update containerd config
  copy:
    src: config.toml
    dest: /etc/containerd/config.toml
  notify: restart containerd

handlers:
  - name: restart containerd
    systemd:
      name: containerd
      state: restarted
      daemon_reload: yes
```

**Handler Rules:**

- Define handlers in `handlers/main.yml` (roles) or at playbook end
- Use `notify:` in tasks that change state
- Handlers run **once** at end of play, even if notified multiple times
- Force immediate handler run: `meta: flush_handlers`

---

## 5. Tags: Enable Partial Runs

**Rule:** Tag tasks for common workflows (updates, rollbacks).

### ❌ Bad Example

```yaml
- name: Install k9s
  get_url:
    url: "https://github.com/derailed/k9s/releases/download/{{ k9s_version }}/k9s_linux_amd64.tar.gz"
    dest: /tmp/k9s.tar.gz
```

**Problem:** Can't update k9s without running entire playbook.

### ✅ Good Example

```yaml
- name: Install k9s
  get_url:
    url: "https://github.com/derailed/k9s/releases/download/{{ k9s_version }}/k9s_linux_amd64.tar.gz"
    dest: /tmp/k9s.tar.gz
  tags:
    - k9s
    - tools
    - update-only
```

**Standard Tag Conventions:**

- `update-only`: Update packages/tools without config changes
- `init`: First-time setup tasks (non-idempotent)
- `config`: Configuration file updates
- `never`: Tasks that require manual intervention (use `--tags never` to run)

**Usage:**

```bash
# Run only update tasks
ansible-playbook playbook.yml --tags update-only

# Skip update tasks
ansible-playbook playbook.yml --skip-tags update-only

# List available tags
ansible-playbook playbook.yml --list-tags
```

---

## 6. Error Handling: Fail Gracefully

**Rule:** Provide context when tasks fail; don't leave system in broken state.

### ❌ Bad Example

```yaml
- name: Download Cilium CLI
  get_url:
    url: "https://github.com/cilium/cilium-cli/releases/download/{{ cilium_version }}/cilium-linux-amd64.tar.gz"
    dest: /tmp/cilium.tar.gz
```

**Problem:** Fails silently on 404, leaves user guessing.

### ✅ Good Example

```yaml
- name: Download Cilium CLI
  block:
    - name: Download Cilium CLI
      get_url:
        url: "https://github.com/cilium/cilium-cli/releases/download/{{ cilium_version }}/cilium-linux-amd64.tar.gz"
        dest: /tmp/cilium.tar.gz
        timeout: 30
      register: cilium_download

    - name: Extract Cilium CLI
      unarchive:
        src: /tmp/cilium.tar.gz
        dest: /usr/local/bin
        remote_src: yes

  rescue:
    - name: Cleanup failed download
      file:
        path: /tmp/cilium.tar.gz
        state: absent

    - name: Fail with helpful message
      fail:
        msg: |
          Failed to download Cilium CLI {{ cilium_version }}.
          Check if version exists: https://github.com/cilium/cilium-cli/releases
```

**Key Techniques:**

- Use `block`/`rescue`/`always` for error handling
- `register:` output for debugging (`debug: var=result`)
- `failed_when:` for custom failure conditions
- `ignore_errors: yes` sparingly (only for optional tasks)

---

## 7. Templates: Dynamic Configuration

**Rule:** Use Jinja2 templates for complex config files.

### When to Use Templates vs `copy`

- **Static files:** Use `copy` (e.g., scripts, binaries)
- **Minor substitutions:** Use `copy` with `content:` and `{{ var }}`
- **Complex logic:** Use `template` with `.j2` files

### Example: kubeadm Config Template

```yaml
# File: roles/kubeadm/templates/kubeadm-config.yaml.j2
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "{{ kubernetes_version }}"
networking:
  podSubnet: "{{ pod_cidr }}"
  serviceSubnet: "{{ service_cidr }}"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
clusterDNS:
  - "{{ cluster_dns }}"
serverTLSBootstrap: true
```

```yaml
# Task: roles/kubeadm/tasks/main.yml
- name: Generate kubeadm config
  template:
    src: kubeadm-config.yaml.j2
    dest: /etc/kubernetes/kubeadm-config.yaml
    owner: root
    group: root
    mode: '0644'
  notify: restart kubelet
```

**Template Best Practices:**

- Validate Jinja2 syntax locally: `ansible-playbook --syntax-check`
- Use `trim_blocks: yes` and `lstrip_blocks: yes` for cleaner output
- Comment template logic: `{# This section handles CNI config #}`
- Provide variable defaults: `{{ var | default('fallback') }}`

---

## 8. Inventory Management: Keep It Simple

**Rule:** Use static inventory (`inventory/hosts`) for stable clusters.

### ❌ Bad Example: Inline Variables Everywhere

```ini
[raspberry_pis]
pi0 ansible_host=192.168.86.220 ansible_user=homekube static_ip=192.168.86.220 internal_ip=10.0.0.20 role=control-plane
pi1 ansible_host=192.168.86.221 ansible_user=homekube static_ip=192.168.86.221 internal_ip=10.0.0.21 role=worker
pi2 ansible_host=192.168.86.222 ansible_user=homekube static_ip=192.168.86.222 internal_ip=10.0.0.22 role=worker
```

**Problem:** Repetitive, hard to maintain.

### ✅ Good Example: Group Variables

```ini
# File: inventory/hosts
[raspberry_pis]
pi0 internal_ip=10.0.0.20 role=control-plane
pi1 internal_ip=10.0.0.21 role=worker
pi2 internal_ip=10.0.0.22 role=worker
pi3 internal_ip=10.0.0.23 role=worker

[raspberry_pis:vars]
ansible_user=homekube
ansible_python_interpreter=/usr/bin/python3
```

```yaml
# File: group_vars/raspberry_pis.yml
ansible_host: "192.168.86.{{ inventory_hostname[-1] | int + 220 }}"
```

**Inventory Patterns:**

- Use patterns for limits: `--limit 'pi*'`, `--limit 'pi[0:2]'`
- Group by function: `[control_plane]`, `[workers]`
- Avoid dynamic inventory for small, stable clusters

---

## 9. Role Structure: Organise for Reusability

**Standard Role Layout:**

```
roles/
└── example-role/
    ├── defaults/        # Default variables (lowest precedence)
    │   └── main.yml
    ├── tasks/           # Task list (main.yml is entry point)
    │   └── main.yml
    ├── handlers/        # Service restarts, notifications
    │   └── main.yml
    ├── templates/       # Jinja2 templates (.j2 files)
    │   └── config.yaml.j2
    ├── files/           # Static files to copy
    │   └── script.sh
    └── vars/            # Role-specific vars (high precedence)
        └── main.yml
```

### Splitting Task Files

```yaml
# File: roles/k8s-node/tasks/main.yml
---
- import_tasks: packages.yml
  tags: packages

- import_tasks: storage.yml
  tags: storage

- import_tasks: containerd.yml
  tags: containerd

- import_tasks: kubernetes.yml
  tags: kubernetes
```

**Benefits:**

- Easier to navigate large roles
- Tags apply to entire file
- Clear separation of concerns

---

## 10. Testing Playbooks

### Pre-Run Checks

```bash
# Syntax check
ansible-playbook playbook.yml --syntax-check

# List hosts that would be affected
ansible-playbook playbook.yml --list-hosts

# List tasks that would run
ansible-playbook playbook.yml --list-tasks

# Dry-run (check mode)
ansible-playbook playbook.yml --check
```

### Debugging Tasks

```yaml
- name: Check variable value
  debug:
    var: my_variable
    verbosity: 1  # Only show with -v

- name: Debug with custom message
  debug:
    msg: "Kubernetes version is {{ kubernetes_version }}"
```

### Ansible Verbosity Levels

```bash
ansible-playbook playbook.yml -v     # Show task results
ansible-playbook playbook.yml -vv    # Show task input/output
ansible-playbook playbook.yml -vvv   # Show SSH commands
ansible-playbook playbook.yml -vvvv  # Show connection debugging
```

---

## 11. Common Patterns for homekube

### Pattern 1: Package Installation with Version Pinning

```yaml
- name: Install Kubernetes packages
  apt:
    name:
      - "kubelet={{ kubernetes_version }}.*"
      - "kubeadm={{ kubernetes_version }}.*"
      - "kubectl={{ kubernetes_version }}.*"
    state: present
    update_cache: yes
  notify: restart kubelet
```

### Pattern 2: Conditional Tasks Based on Cluster State

```yaml
- name: Check if Kubernetes is initialised
  stat:
    path: /etc/kubernetes/admin.conf
  register: kubeconfig

- name: Initialise control plane
  command: kubeadm init --config /etc/kubernetes/kubeadm-config.yaml
  when: not kubeconfig.stat.exists
```

### Pattern 3: Waiting for Services

```yaml
- name: Wait for Kubernetes API server
  wait_for:
    host: "{{ ansible_default_ipv4.address }}"
    port: 6443
    timeout: 300
  when: role == "control-plane"
```

### Pattern 4: Loop Over Nodes

```yaml
- name: Update /etc/hosts with cluster nodes
  lineinfile:
    path: /etc/hosts
    regexp: "^{{ hostvars[item].ansible_host }}.*{{ item }}$"
    line: "{{ hostvars[item].ansible_host }} {{ item }}"
    state: present
  loop: "{{ groups['raspberry_pis'] }}"
  become: yes
```

---

## 12. Security Best Practices

### Never Commit Secrets

```yaml
# ❌ Bad: Secret in vars file
mysql_root_password: "supersecret123"

# ✅ Good: Prompt at runtime
- name: Prompt for MySQL root password
  vars_prompt:
    - name: mysql_root_password
      prompt: "Enter MySQL root password"
      private: yes

# ✅ Better: Use Ansible Vault
# Create vault: ansible-vault create secrets.yml
# Edit vault: ansible-vault edit secrets.yml
# Run with vault: ansible-playbook playbook.yml --ask-vault-pass
```

### SSH Key Management

```yaml
- name: Add SSH public key to authorised keys
  authorized_key:
    user: homekube
    state: present
    key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
```

### Privilege Escalation

```yaml
- name: Task requiring root
  apt:
    name: kubelet
    state: present
  become: yes  # Use sudo
  become_method: sudo
  become_user: root
```

---

## 13. Ansible Galaxy Collections

### Required Collections for homekube

```yaml
# File: ansible/requirements.yml
---
collections:
  - name: ansible.posix
    version: ">=1.5.0"

  - name: community.general
    version: ">=8.0.0"

  - name: kubernetes.core
    version: ">=2.4.0"
```

### Install Collections

```bash
cd ansible/
ansible-galaxy collection install -r requirements.yml
```

### Using Collection Modules

```yaml
# Full namespace (explicit)
- name: Copy file with ACL
  ansible.posix.synchronize:
    src: /path/to/file
    dest: /path/to/dest

# Short name (if collections defined in playbook)
collections:
  - ansible.posix

- name: Copy file with ACL
  synchronize:
    src: /path/to/file
    dest: /path/to/dest
```

---

## 14. Ansible Linting

### Install ansible-lint

```bash
pip install ansible-lint
```

### Run Linter

```bash
cd ansible/
ansible-lint playbooks/*.yml
ansible-lint roles/*/tasks/*.yml
```

### Common Lint Errors and Fixes

| Error | Fix |
|-------|-----|
| `yaml[line-length]` | Split long lines with `>` or `\|` |
| `no-changed-when` | Add `changed_when: false` to `command`/`shell` |
| `risky-shell-pipe` | Use `\|` for Jinja2 filters, not shell pipes |
| `deprecated-module` | Replace with suggested modern module |
| `name[play]` | Add descriptive names to plays and tasks |

---

## 15. Troubleshooting Playbook Failures

### Common Issues

#### Issue 1: "Undefined variable"

```
TASK [Install package] *******
fatal: [pi0]: FAILED! => {"msg": "The task includes an option with an undefined variable. The error was: 'kubernetes_version' is undefined"}
```

**Fix:** Check variable is defined in `group_vars/all.yml` or passed via `-e`.

#### Issue 2: "Authentication failure"

```
fatal: [pi0]: UNREACHABLE! => {"msg": "Failed to connect to the host via ssh: Permission denied (publickey)."}
```

**Fix:** Run playbook `01-update-control-node.yml` to configure SSH keys.

#### Issue 3: "sudo password required"

```
fatal: [pi0]: FAILED! => {"msg": "Missing sudo password"}
```

**Fix:** Add `--ask-become-pass` flag to playbook command.

#### Issue 4: Task reports "changed" when nothing changed

```
TASK [Restart service] *******
changed: [pi0]
```

**Fix:** Add `changed_when: false` or use module (not `shell`/`command`).

---

**End of Ansible Skills**  
See also: `.ai-skills/shell-scripting.md`, `AI-CONTEXT.md`.

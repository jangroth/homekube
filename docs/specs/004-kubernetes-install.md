# Spec 004 — Kubernetes Install (Phase 4)

**Status:** Draft  
**Phase:** 4  
**Playbooks:** `30-k8s-control-plane.yml`, `31-k8s-workers.yml`, `40-cni.yml`

---

## Problem

Phase 3 is complete: all four pis have containerd, kubelet/kubeadm/kubectl installed (pinned version), cgroup v2 enabled, kernel params set, and 4 GiB swap on NVMe. Kubelet is installed but idle — no cluster exists yet, no `/var/lib/kubelet/config.yaml`.

Phase 4 must:

1. Initialise the control plane on pi0 via `kubeadm init`
2. Deliver the kubelet swap config deferred from Phase 3 (`failSwapOn: false`, `memorySwap.swapBehavior: LimitedSwap`)
3. Wire kubectl access from darth
4. Join pi1, pi2, pi3 as worker nodes
5. Install Cilium so all nodes transition to `Ready`

**Network plane constraint (critical):** Tailscale is the management plane for Ansible/SSH, but it is invisible to Kubernetes. All inter-node k8s traffic (etcd, API server, kubelet, pods) must use the physical switch plane (10.0.0.x). Every kubeadm config and kubelet flag must bind to these IPs, not Tailscale IPs.

**darth is not on the switch.** darth reaches the API server via Tailscale MagicDNS (`pi0`). The API server TLS cert must include `pi0` as a SAN, and the kubeconfig fetched to darth must point to `https://pi0:6443`, not `https://10.0.0.20:6443`.

---

## Preconditions

- Phase 3 complete: `22-k8s-nodes.yml` ran cleanly on all pis
- `ssh homekube@pi0` resolves via Tailscale MagicDNS from darth
- `sudo kubeadm init --dry-run --ignore-preflight-errors=Swap` exits 0 on pi0
- containerd is running: `sudo systemctl is-active containerd` → `active`
- containerd configured for systemd cgroups: `grep SystemdCgroup /etc/containerd/config.toml` shows `SystemdCgroup = true` (must match kubelet `cgroupDriver: systemd`)
- kubelet is installed and stopped (no cluster yet): `sudo systemctl is-active kubelet` → `inactive` or crash-loop is acceptable
- Wired NIC is `eth0` on every pi (verify: `ip -br link | awk '$1 ~ /^e/ {print $1}'` returns `eth0`). All kubeadm/Cilium configs in this spec assume `eth0`; if a pi reports `end0` (newer Pi OS predictable names), update before running.
- **Switch link up and IP assigned** on each pi: `ip -4 addr show eth0` returns the expected `10.0.0.2{0,1,2,3}/24`. A pi with the switch cable unplugged will install fine, but kubelet will fail to bind `--node-ip`.
- **Hostname matches expected node name** on every pi: `hostnamectl --static` returns `pi0`/`pi1`/`pi2`/`pi3` (no `.local`, no domain suffix). The kubeadm `certSANs` entry, the kubeconfig server URL, the Tailscale MagicDNS name, and the `kubectl get nodes` node name all depend on this exact string.
- Time sync active on every pi: `systemctl is-active systemd-timesyncd` → `active` (etcd is intolerant of clock skew >500ms)
- darth has `kubectl`, `helm`, and the Cilium CLI installed — these are provisioned by Phase 2's `20-configure-darth.yml` (`control-node` role); verify with `kubectl version --client && helm version && cilium version --client`

---

## Acceptance Criteria

- [ ] `kubectl get nodes` from darth shows all four nodes (pi0–pi3), all `Ready`
- [ ] `kubectl get nodes -o wide` shows NODE IP column as 10.0.0.x (not Tailscale IPs)
- [ ] `kubectl get pods -n kube-system` — all system pods `Running` or `Completed`
- [ ] `kubectl get pods -n kube-system -l k8s-app=cilium` — one Cilium pod per node, all `Running`
- [ ] `kubectl get pods -n kube-system -l app=cilium-operator` — operator pod `Running`
- [ ] `cilium status` (or `kubectl -n kube-system exec ds/cilium -- cilium status`) — `OK`
- [ ] Swap active on all nodes: `swapon --show` on each pi shows `/var/swap.img`, kubelet not crashing on swap
- [ ] `sudo journalctl -u kubelet --since "10 minutes ago"` — no `failSwapOn` errors
- [ ] Control-plane taint is present on pi0: `kubectl describe node pi0 | grep Taints` shows `node-role.kubernetes.io/control-plane:NoSchedule`
- [ ] Idempotent re-run of `30-k8s-control-plane.yml` (after cluster exists) reports no changes / skips init gracefully
- [ ] kubeconfig on darth points to `https://pi0:6443`; `kubectl cluster-info` succeeds from darth

---

## Out of Scope

- ArgoCD, GitOps, app deployment (Phase 5)
- MetalLB, Longhorn, Prometheus, Grafana, Loki (Phase 5 via ArgoCD)
- HA control plane (single control plane is intentional for this cluster)
- Cilium encryption, Hubble, or advanced network policies (can be added later)
- Upgrading Kubernetes after install
- Tailscale as a pod network (k8s traffic stays on the switch plane)

---

## Approach

### 1. Network plane design

| Plane | Interface | CIDR | Purpose |
|-------|-----------|------|---------|
| Switch (k8s) | `eth0` | 10.0.0.0/24 | API server, etcd, kubelet, pod traffic |
| Tailscale | `tailscale0` | 100.x.x.x | SSH, Ansible, `kubectl` from darth |
| WiFi | `wlan0` | DHCP | Internet access only |

kubeadm must advertise and bind to `eth0` addresses:
- pi0 (control plane): `advertiseAddress: 10.0.0.20`
- All nodes: kubelet `node-ip` set to their switch IP

darth talks to the API server over Tailscale (`pi0:6443`). The API server listens on 10.0.0.20:6443; the cert must include `pi0` as a SAN so TLS validation succeeds from darth. Workers reach the API server over the switch — their join config uses `10.0.0.20:6443` directly.

### 2. `kubeadm-config.yaml` (control plane)

Stored at `roles/k8s-control-plane/files/kubeadm-config.yaml`. Drives `kubeadm init` on pi0.

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "{{ kubernetes_version }}"
controlPlaneEndpoint: "10.0.0.20:6443"
networking:
  podSubnet: "10.244.0.0/16"      # Cilium default; matches --cluster-cidr
  serviceSubnet: "10.96.0.0/12"
apiServer:
  certSANs:
    - "pi0"           # Tailscale MagicDNS — allows kubectl from darth
    - "10.0.0.20"     # switch IP (already in cert by default, explicit for clarity)
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "10.0.0.20"
  bindPort: 6443
nodeRegistration:
  criSocket: "unix:///run/containerd/containerd.sock"
  kubeletExtraArgs:
    - name: node-ip
      value: "10.0.0.20"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd     # must match containerd /etc/containerd/config.toml SystemdCgroup = true
failSwapOn: false
memorySwap:
  swapBehavior: LimitedSwap
resolvConf: /run/systemd/resolve/resolv.conf   # bypass systemd-resolved stub (127.0.0.53) to avoid coredns loop
```

This file is the **single source of truth** for kubelet swap config (deferred from Phase 3 per DECISION-009) and for the kubelet config in general (per DECISION-011). Only the deliberate overrides are set explicitly; kubeadm fills in the rest (`clusterDNS`, `clusterDomain`, `staticPodPath`, `authentication`, `authorization`, etc.) from its computed defaults. Re-running `30-k8s-control-plane.yml` re-renders `/var/lib/kubelet/config.yaml` from this file — do not hand-edit the live kubelet config.

**Why `resolvConf` matters:** Pi OS Bookworm uses `systemd-resolved`. The default `/etc/resolv.conf` points to the local stub `127.0.0.53`. If kubelet hands that to coredns as the upstream `forward` target, coredns either CrashLoops with "Loop detected" or queries itself. Pointing kubelet at the real upstream list (`/run/systemd/resolve/resolv.conf`) breaks the loop. Coredns then forwards to whatever DNS servers systemd-resolved learned via DHCP.

### 3. Playbook: `30-k8s-control-plane.yml`

`hosts: control_plane` (resolves to pi0 per `ansible/inventory/hosts.ini`). Steps:

1. **Check if cluster already initialised** — probe `/etc/kubernetes/admin.conf`; skip init if it exists (idempotency gate)
2. **Pre-pull control-plane images** — `sudo kubeadm config images pull --kubernetes-version {{ kubernetes_version }}`. Avoids the 4 min `timeoutForControlPlane` running out on slow image pulls.
3. **Copy `kubeadm-config.yaml`** to `/tmp/kubeadm-config.yaml` on pi0
4. **Run `kubeadm init`** — `sudo kubeadm init --config /tmp/kubeadm-config.yaml --ignore-preflight-errors=Swap`. The Swap ignore is required: Phase 3 enabled 4 GiB swap (DECISION-009) and kubeadm preflight errors on Swap regardless of `failSwapOn`.
5. **Set up kubeconfig on pi0** — create `~/.kube/` for `homekube`, copy `/etc/kubernetes/admin.conf`, fix ownership
6. **Fetch kubeconfig to darth** — fetch `/etc/kubernetes/admin.conf` from pi0 (Ansible `fetch` with `become: true`, since the file is `root:root 0600`); rewrite the `server` field from `https://10.0.0.20:6443` to `https://pi0:6443` (Tailscale MagicDNS); rename the context to `homekube`; **write to `~/.kube/homekube.config` (not `~/.kube/config`)** to avoid overwriting any existing kubeconfig on darth. Operator activates with `export KUBECONFIG=~/.kube/homekube.config` or merges via `kubectl config view --flatten`.

**Note on token generation:** Token + CA-hash creation is **not** done here. `31-k8s-workers.yml` re-queries pi0 on every run so the worker playbook is self-contained and the two playbooks can be invoked as separate `ansible-playbook` runs without depending on shared facts. See §5.

No CNI is installed here. Nodes will show `NotReady` until Cilium is up; that is expected.

### 4. `join-config.yaml` (workers)

Stored at `roles/k8s-worker/templates/join-config.yaml.j2` (Jinja2 template, node IP injected per host).

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "10.0.0.20:6443"
    token: "{{ kubeadm_token }}"
    caCertHashes:
      - "sha256:{{ kubeadm_ca_hash }}"
nodeRegistration:
  criSocket: "unix:///run/containerd/containerd.sock"
  kubeletExtraArgs:
    - name: node-ip
      value: "{{ node_switch_ip }}"   # 10.0.0.21 / .22 / .23
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
memorySwap:
  swapBehavior: LimitedSwap
resolvConf: /run/systemd/resolve/resolv.conf
```

`node_switch_ip` is set in `group_vars` or `host_vars` per pi.

### 5. Playbook: `31-k8s-workers.yml`

`hosts: data_plane` (pi1, pi2, pi3 per `ansible/inventory/hosts.ini`). Joins may run in parallel — `kubeadm join` is safe concurrent. Steps:

1. **Check if already joined** — probe `/etc/kubernetes/kubelet.conf`; skip join if present
2. **Pre-pull node images** — `sudo kubeadm config images pull --kubernetes-version {{ kubernetes_version }}` on each worker (kube-proxy + pause). Same rationale as control plane.
3. **Re-query token + CA hash from pi0** (always — do not rely on facts from `30-k8s-control-plane.yml`; the two playbooks are run as separate `ansible-playbook` invocations and a token from an earlier run may have expired). `delegate_to: pi0`, `run_once: true`, `become: true`:
   - Token: `kubeadm token create` (fresh 24 h token)
   - CA hash: `openssl x509 -in /etc/kubernetes/pki/ca.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -hex | awk '{print $NF}'`
   Register both as facts on the play; reference as `{{ hostvars['pi0'].kubeadm_token }}` / `{{ hostvars['pi0'].kubeadm_ca_hash }}` in the template.
4. **Template `join-config.yaml`** to `/tmp/join-config.yaml` on each worker
5. **Run `kubeadm join`** — `sudo kubeadm join --config /tmp/join-config.yaml --ignore-preflight-errors=Swap`
6. **Verify registration** — delegate to localhost, run `kubectl --kubeconfig ~/.kube/homekube.config get node <nodename>`; wait up to 60 s for the node object to appear. Status will be `NotReady` until Phase `40-cni.yml` installs Cilium — do **not** wait for `Ready` here.

### 6. Playbook: `40-cni.yml`

Install Cilium using Helm (reproducible, version-pinned to `{{ cilium_version }}` from `group_vars/all.yml`). Runs from darth (`delegate_to: localhost`). The Helm and rollout-wait tasks must set `KUBECONFIG` explicitly so the Ansible-spawned `helm`/`kubectl` processes hit the homekube cluster regardless of the operator's shell state:

```yaml
- name: Install Cilium
  ansible.builtin.shell: |
    helm repo add cilium https://helm.cilium.io/
    helm repo update
    helm upgrade --install cilium cilium/cilium \
      --version {{ cilium_version }} \
      --namespace kube-system \
      --set ipam.mode=kubernetes \
      --set kubeProxyReplacement=false \
      --set k8sServiceHost={{ control_plane_ip }} \
      --set k8sServicePort=6443 \
      --set devices=eth0 \
      --set routingMode=tunnel \
      --set tunnelProtocol=vxlan
  environment:
    KUBECONFIG: "{{ ansible_env.HOME }}/.kube/homekube.config"
  delegate_to: localhost
```

- `ipam.mode=kubernetes` — uses the pod CIDR from kubeadm (10.244.0.0/16)
- `kubeProxyReplacement=false` — kube-proxy is installed by kubeadm; replacing it is a later optimisation
- `devices=eth0` — pin Cilium to the switch interface. Without this, auto-detection may pick `tailscale0` or `wlan0` and break inter-node traffic
- `routingMode=tunnel` / `tunnelProtocol=vxlan` — explicit (defaults), so encap behaviour is self-documenting
- `helm repo update` ensures the pinned version resolves from a current index
- `helm upgrade --install` handles both first-time install and re-runs idempotently
- `cilium_version` and `control_plane_ip` come from `group_vars/all.yml` (§8) — do not hardcode

After Helm deploy, wait for DaemonSet rollout with the same `KUBECONFIG` environment: `kubectl rollout status ds/cilium -n kube-system --timeout=5m`.

### 7. Role structure

```
roles/
  k8s-control-plane/
    tasks/
      main.yml
      init_control_plane.yml
      setup_kubeconfig.yml
    files/
      kubeadm-config.yaml
  k8s-worker/
    tasks/
      main.yml
      query_join_credentials.yml   # delegate_to: pi0, run_once — fresh token + CA hash per run
      join_cluster.yml
    templates/
      join-config.yaml.j2
```

Existing `roles/k8s-node/` from Phase 3 is unchanged — it installs prereqs on all nodes. Phase 4 roles layer on top.

### 8. `group_vars` additions

Versions are already managed in `group_vars/all.yml` — update there, not in playbooks or role files:

```yaml
kubernetes_version: "1.36.1"   # already set
cilium_version: "1.19.4"       # updated from 1.18.2
```

Add the following (not yet present):

```yaml
pod_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"
control_plane_ip: "10.0.0.20"
```

Add per-host switch IPs to `host_vars/piN.yml`:

```yaml
# host_vars/pi0.yml
node_switch_ip: "10.0.0.20"
# host_vars/pi1.yml
node_switch_ip: "10.0.0.21"
# etc.
```

---

## Playbook Run Order

On darth, from `homekube-main/ansible/` (via `task` or `uv run ansible-playbook`):

| Step | Command | Expected state after |
|------|---------|---------------------|
| 1 | `ansible-playbook 30-k8s-control-plane.yml` | Cluster initialised on pi0; kubeconfig on darth; pi0 node shows `NotReady` (no CNI yet) |
| 2 | `kubectl get nodes` | pi0 listed, `NotReady` |
| 3 | `ansible-playbook 31-k8s-workers.yml` | pi1–pi3 joined; four nodes in `kubectl get nodes`, all `NotReady` |
| 4 | `ansible-playbook 40-cni.yml` | Cilium DaemonSet rolled out; all nodes transition to `Ready` within ~2 min |
| 5 | `kubectl get nodes` | All four nodes `Ready` |
| 6 | `kubectl get pods -n kube-system` | All system pods `Running`/`Completed` |

---

## Verification

```bash
# All nodes Ready with correct switch IPs
kubectl get nodes -o wide

# All system pods healthy
kubectl get pods -n kube-system

# Cilium health
kubectl -n kube-system exec ds/cilium -- cilium status

# Swap active and kubelet not crashing
ssh homekube@pi0 "swapon --show && sudo journalctl -u kubelet --since '5 minutes ago' | grep -i swap"

# Test pod-to-pod connectivity across nodes
kubectl run -it --rm ping --image=busybox --restart=Never -- \
  sh -c "ping -c 3 <pod-ip-on-different-node>"
```

---

## Rollback / Recovery

| Failure | Recovery |
|---------|----------|
| `kubeadm init` fails midway (pi0) | `sudo kubeadm reset -f` on pi0; fix the issue; re-run playbook. Reset is safe pre-CNI. |
| `kubeadm join` fails (worker) | `sudo kubeadm reset -f` on that worker; re-run `31-k8s-workers.yml` (join token valid 24 h by default) |
| Token expired before workers join | Re-run `31-k8s-workers.yml` — it mints a fresh 24 h token on pi0 at the start of every run, so this should be self-healing. Manual fallback: `sudo kubeadm token create --print-join-command` on pi0 |
| Cilium pods crashloop | `kubectl describe pod -n kube-system -l k8s-app=cilium`; common causes: wrong pod CIDR, wrong API server IP. `helm uninstall cilium -n kube-system` + fix values + re-run `40-cni.yml` |
| Nodes stuck `NotReady` after Cilium | Wait up to 3 min for CNI to initialise. If still stuck: check Cilium logs, check that `eth0` IPs are correct on each node |
| kubectl from darth refuses connection | Verify kubeconfig `server` is `https://pi0:6443`; verify `pi0` resolves on darth (`ping pi0`); verify `certSANs` includes `pi0` (`openssl s_client -connect pi0:6443 2>/dev/null \| openssl x509 -noout -text \| grep -A1 'Subject Alternative'`) |

---

## Operational Notes

- **Certificate expiry:** kubeadm-issued control-plane certs (`apiserver`, `apiserver-kubelet-client`, `front-proxy-client`, etcd peer/server/client) expire **1 year** after `kubeadm init`. Check with `sudo kubeadm certs check-expiration`. Renew before expiry with `sudo kubeadm certs renew all` followed by a control-plane static-pod restart (`sudo systemctl restart kubelet`, or kill the static pods). The kubelet client cert auto-rotates and is not affected.
- **kubeconfig on darth:** activated via `export KUBECONFIG=~/.kube/homekube.config` (or shell rc). To use it alongside other clusters, merge into the default config: `KUBECONFIG=~/.kube/config:~/.kube/homekube.config kubectl config view --flatten > ~/.kube/merged && mv ~/.kube/merged ~/.kube/config`.
- **etcd backup:** not in Phase 4 scope. Phase 5+ should add periodic `etcdctl snapshot save` to NVMe and off-cluster (e.g. Tailscale-reachable host).

---

## Follow-ups (post-Phase 4)

- **kube-proxy replacement:** migrate to Cilium's full kube-proxy replacement (`kubeProxyReplacement=true`) and remove kubeadm-installed kube-proxy DaemonSet.
- **Cilium encryption / Hubble / network policies:** see Out of Scope.
- **Control-plane HA:** intentionally single control plane for this cluster (see Out of Scope).
- **etcd backup automation** (see Operational Notes).

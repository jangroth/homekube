# Shell Scripting Skills for homekube

**Applies to:** All scripts in `scripts/`, ad-hoc commands in `Taskfile.yml`

---

## 1. Idempotency: Scripts Must Be Re-Runnable

**Rule:** Every script must produce the same result when run multiple times.

### ❌ Bad Example

```bash
#!/bin/bash
echo "node1 192.168.1.10" >> /etc/hosts
```

**Problem:** Appends duplicate entries on each run.

### ✅ Good Example

```bash
#!/bin/bash
set -euo pipefail

NODE_IP="192.168.1.10"
NODE_NAME="node1"

# Remove existing entry if present
sudo sed -i.bak "/^[0-9.]*\s*${NODE_NAME}$/d" /etc/hosts

# Add new entry
echo "${NODE_IP} ${NODE_NAME}" | sudo tee -a /etc/hosts > /dev/null
```

**Key Techniques:**

- Check state before modifying: `if ! grep -q "pattern" file; then ... fi`
- Use idempotent tools: `rsync`, `ln -sf`, `curl -fsSL -o file`
- Delete-then-add for config files (like `sed -i '/pattern/d'`)

---

## 2. Error Handling: Fail Fast, Fail Loud

**Rule:** Scripts must exit on first error and provide clear context.

### ❌ Bad Example

```bash
#!/bin/bash
curl https://example.com/file.tar.gz -o file.tar.gz
tar -xzf file.tar.gz
./install.sh
```

**Problem:** If `curl` fails (404, network), script continues with corrupt/missing file.

### ✅ Good Example

```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

readonly FILE_URL="https://example.com/file.tar.gz"
readonly FILE_PATH="/tmp/file.tar.gz"

echo "Downloading ${FILE_URL}..."
if ! curl -fsSL "${FILE_URL}" -o "${FILE_PATH}"; then
    echo "ERROR: Failed to download ${FILE_URL}" >&2
    exit 1
fi

echo "Extracting ${FILE_PATH}..."
tar -xzf "${FILE_PATH}" || {
    echo "ERROR: Failed to extract ${FILE_PATH}" >&2
    exit 1
}

echo "Running installer..."
./install.sh
```

**Key Techniques:**

- Always use `set -euo pipefail` at the top
- Use `|| { echo "error"; exit 1; }` for critical commands
- Redirect errors to stderr: `>&2`
- Provide context in error messages (which file, which step)

---

## 3. Variable Hygiene: Defensive and Explicit

**Rule:** Use `readonly` for constants, quote all variables, check for undefined.

### ❌ Bad Example

```bash
#!/bin/bash
NODE=$1
ssh $NODE "systemctl restart kubelet"
```

**Problem:** `$NODE` could be empty, unquoted (breaks with spaces), not validated.

### ✅ Good Example

```bash
#!/bin/bash
set -euo pipefail

readonly NODE="${1:-}"  # Default to empty if not provided

if [[ -z "${NODE}" ]]; then
    echo "Usage: $0 <node-ip>" >&2
    exit 1
fi

# Validate IP format (basic check)
if ! [[ "${NODE}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "ERROR: Invalid IP address: ${NODE}" >&2
    exit 1
fi

echo "Restarting kubelet on ${NODE}..."
ssh "homekube@${NODE}" "sudo systemctl restart kubelet"
```

**Key Techniques:**

- `readonly VAR="value"` for constants
- `"${VAR}"` (always quoted) for safe expansion
- `"${VAR:-default}"` for default values
- Validate inputs early (exit before doing damage)

---

## 4. Output: Human-Readable and Machine-Parsable

**Rule:** Provide progress messages (stdout) and structured output when needed.

### ❌ Bad Example

```bash
#!/bin/bash
kubectl get nodes | grep Ready
```

**Problem:** Unclear what the script is checking, output not machine-friendly.

### ✅ Good Example

```bash
#!/bin/bash
set -euo pipefail

echo "Checking cluster node status..."

# Machine-parsable output (JSON)
readonly NODES_JSON=$(kubectl get nodes -o json)

# Human-friendly summary
echo "Ready nodes:"
echo "${NODES_JSON}" | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True")) | .metadata.name'

# Exit code based on actual check
READY_COUNT=$(echo "${NODES_JSON}" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
TOTAL_COUNT=$(echo "${NODES_JSON}" | jq '.items | length')

echo "Status: ${READY_COUNT}/${TOTAL_COUNT} nodes ready"

if [[ "${READY_COUNT}" -lt "${TOTAL_COUNT}" ]]; then
    echo "WARNING: Not all nodes are ready" >&2
    exit 1
fi
```

**Key Techniques:**

- Print what the script is doing (progress messages)
- Use JSON output (`-o json`) for parsing (via `jq`)
- Provide summary/conclusion at the end
- Use colour for emphasis: `echo -e "\033[0;32mSUCCESS\033[0m"`

---

## 5. Integration with Ansible: When to Use Scripts vs Tasks

**Rule:** Prefer Ansible tasks for stateful operations; use scripts for quick checks or local tools.

### Use Scripts For

- **Local Tools:** Detecting external IP (`detect-external-ip.sh`)
- **One-Off Checks:** Testing NodePort connectivity (`test-nodeports.sh`)
- **Development Helpers:** Running commands across nodes (`run-command.sh`)

### Use Ansible For

- **Configuration Changes:** Modifying `/etc/hosts`, SSH config
- **Package Installation:** Installing k9s, helm, cilium-cli
- **Service Management:** Restarting kubelet, containerd
- **Cluster Initialization:** `kubeadm init`, joining nodes

### Example: Script Calling Ansible

```bash
#!/bin/bash
set -euo pipefail

readonly PLAYBOOK="03-setup-k8s-nodes.yml"
readonly TAG="update-only"

echo "Running Ansible playbook: ${PLAYBOOK} (tag: ${TAG})..."
cd "$(dirname "$0")/../ansible" || exit 1

ansible-playbook "${PLAYBOOK}" --tags "${TAG}"
```

---

## 6. Cluster Awareness: Never Guess State

**Rule:** Query cluster state explicitly; never assume pods/nodes are running.

### ❌ Bad Example

```bash
#!/bin/bash
kubectl logs -n kube-system cilium-abcd1234
```

**Problem:** Pod name is ephemeral (changes on restart).

### ✅ Good Example

```bash
#!/bin/bash
set -euo pipefail

readonly NAMESPACE="kube-system"
readonly APP_LABEL="k8s-app=cilium"

echo "Finding Cilium pod in ${NAMESPACE}..."
CILIUM_POD=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -z "${CILIUM_POD}" ]]; then
    echo "ERROR: No Cilium pod found in ${NAMESPACE}" >&2
    exit 1
fi

echo "Fetching logs for pod: ${CILIUM_POD}"
kubectl logs -n "${NAMESPACE}" "${CILIUM_POD}" --tail=50
```

**Key Techniques:**

- Use labels (`-l k8s-app=cilium`) instead of pod names
- Use `jsonpath` or `jq` for extracting specific fields
- Check if results are empty before proceeding
- Always specify namespace explicitly (`-n <namespace>`)

---

## 7. Script Templates for Common Tasks

### Template 1: Cluster Health Check

```bash
#!/bin/bash
set -euo pipefail

echo "=== Homekube Cluster Health Check ==="
echo

echo "1. Node Status:"
kubectl get nodes -o wide
echo

echo "2. System Pods:"
kubectl get pods -n kube-system
echo

echo "3. Storage:"
kubectl get sc,pv,pvc -A
echo

echo "4. Cilium Status:"
kubectl -n kube-system exec ds/cilium -- cilium status --brief
echo

echo "=== Health Check Complete ==="
```

### Template 2: Safe SSH Command Execution

```bash
#!/bin/bash
set -euo pipefail

readonly NODES=("192.168.86.220" "192.168.86.221" "192.168.86.222" "192.168.86.223")
readonly SSH_USER="homekube"
readonly COMMAND="${1:-}"

if [[ -z "${COMMAND}" ]]; then
    echo "Usage: $0 '<command>'" >&2
    echo "Example: $0 'uptime'" >&2
    exit 1
fi

echo "Running command on all nodes: ${COMMAND}"
echo

for node in "${NODES[@]}"; do
    echo "--- Node: ${node} ---"
    if ssh -o ConnectTimeout=5 "${SSH_USER}@${node}" "${COMMAND}"; then
        echo "✓ Success"
    else
        echo "✗ Failed (exit code: $?)" >&2
    fi
    echo
done
```

### Template 3: Safe File Download

```bash
#!/bin/bash
set -euo pipefail

readonly URL="${1:-}"
readonly OUTPUT_FILE="${2:-}"

if [[ -z "${URL}" ]] || [[ -z "${OUTPUT_FILE}" ]]; then
    echo "Usage: $0 <url> <output-file>" >&2
    exit 1
fi

# Create directory if needed
mkdir -p "$(dirname "${OUTPUT_FILE}")"

echo "Downloading: ${URL}"
echo "Destination: ${OUTPUT_FILE}"

# Use temp file for atomic write
readonly TEMP_FILE="${OUTPUT_FILE}.tmp"
trap 'rm -f "${TEMP_FILE}"' EXIT  # Cleanup on exit

if curl -fsSL "${URL}" -o "${TEMP_FILE}"; then
    mv "${TEMP_FILE}" "${OUTPUT_FILE}"
    echo "✓ Download complete"
else
    echo "✗ Download failed" >&2
    exit 1
fi
```

---

## 8. Common Pitfalls in Infrastructure Scripts

### Pitfall 1: Assuming Working Directory

**Problem:** Script fails when run from different directory.

**Solution:** Use absolute paths or `cd` to script directory:

```bash
cd "$(dirname "$0")" || exit 1
```

### Pitfall 2: Silent Failures

**Problem:** Commands fail but script continues (e.g., `grep` returns 1 if no match).

**Solution:** Handle expected failures explicitly:

```bash
if grep -q "pattern" file; then
    echo "Pattern found"
else
    echo "Pattern not found (expected)"
fi
```

### Pitfall 3: Hardcoded IPs/Hostnames

**Problem:** Script breaks when cluster topology changes.

**Solution:** Read from inventory or config:

```bash
readonly NODES=($(awk '/^\[raspberry_pis\]/{f=1;next}/^\[/{f=0}f' ../ansible/inventory/hosts | grep -v '^#' | awk '{print $1}'))
```

### Pitfall 4: No Dry-Run Mode

**Problem:** Can't test script without side effects.

**Solution:** Add `--dry-run` flag:

```bash
readonly DRY_RUN="${DRY_RUN:-false}"

if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY RUN] Would execute: kubectl delete pod xyz"
else
    kubectl delete pod xyz
fi
```

---

## 9. Testing Scripts

### Manual Testing Checklist

- [ ] Run twice in a row (idempotency check)
- [ ] Run with invalid inputs (error handling check)
- [ ] Run from different directories (path check)
- [ ] Run without required tools (dependency check)
- [ ] Check exit codes: `echo $?` after each run

### Shellcheck Integration

```bash
# Install shellcheck (macOS)
brew install shellcheck

# Check all scripts
find scripts/ -type f -name "*.sh" -exec shellcheck {} \;
```

---

## 10. Documentation Standards

**Every script must have:**

1. **Shebang:** `#!/bin/bash` or `#!/usr/bin/env bash`
2. **Description:** One-line comment at top
3. **Usage:** If arguments required, show usage in error message
4. **Dependencies:** Comment if requires `kubectl`, `jq`, etc.

**Example Header:**

```bash
#!/bin/bash
# detect-external-ip.sh - Detects the external IP address of the current machine
# Dependencies: curl, jq
# Usage: ./detect-external-ip.sh

set -euo pipefail
```

---

**End of Shell Scripting Skills**  
See also: `AI-CONTEXT.md` for cluster architecture facts.

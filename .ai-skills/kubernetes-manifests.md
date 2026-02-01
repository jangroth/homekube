# Kubernetes Manifest Skills for homekube

**Applies to:** All YAML manifests in `homekube-apps/`, manual deployments, ArgoCD applications

---

## 1. Namespace Discipline: Always Explicit

**Rule:** Never rely on `default` namespace; always specify explicitly.

### ❌ Bad Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.21
```

**Problem:** Deploys to `default` namespace (orphaned, hard to track).

### ✅ Good Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: web-apps
spec:
  containers:
  - name: nginx
    image: nginx:1.21
```

**Namespace Strategy:**

- **System:** `kube-system`, `kube-public`, `kube-node-lease` (don't modify)
- **Infrastructure:** `metallb-system`, `longhorn-system`, `monitoring`
- **GitOps:** `argocd`
- **Applications:** `<app-name>` (one namespace per application)

---

## 2. Resource Limits: Always Set Requests and Limits

**Rule:** Every container must have CPU and memory requests/limits.

### ❌ Bad Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
```

**Problem:** Can consume all node resources, cause OOM kills.

### ✅ Good Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
    resources:
      requests:
        cpu: "100m"       # Guaranteed 0.1 CPU
        memory: "128Mi"   # Guaranteed 128 MiB
      limits:
        cpu: "500m"       # Max 0.5 CPU
        memory: "256Mi"   # Max 256 MiB (killed if exceeded)
```

**Guidelines for Raspberry Pi Cluster:**

- **Requests:** Conservative (what you actually need)
- **Limits:** Realistic (prevents runaway processes)
- **CPU Units:** `100m` = 0.1 CPU, `1000m` = 1 CPU
- **Memory Units:** `128Mi` (mebibytes), `1Gi` (gibibytes)
- **Total per node:** 4 CPUs, 7Gi usable memory (8GB - system overhead)

---

## 3. Storage: Use Longhorn for Persistent Data

**Rule:** Use `storageClassName: longhorn` for all PVCs.

### ❌ Bad Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

**Problem:** Uses default storage class (may be `local-path`, no replication).

### ✅ Good Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
  namespace: myapp
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

**Access Modes:**

- `ReadWriteOnce` (RWO): One node, read-write (most common)
- `ReadOnlyMany` (ROX): Multiple nodes, read-only
- `ReadWriteMany` (RWX): Multiple nodes, read-write (not supported by Longhorn)

**Longhorn-Specific Annotations:**

```yaml
metadata:
  annotations:
    longhorn.io/volume-replicas: "2"  # Override default (3)
```

---

## 4. Image Selection: ARM64 Architecture Only

**Rule:** All images must support `linux/arm64` (no x86_64).

### ❌ Bad Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:latest  # May be x86_64 only
```

**Problem:** Pulls x86_64 image, fails with `exec format error`.

### ✅ Good Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0-arm64  # Explicit architecture tag
    # OR
    image: myapp:1.0  # Multi-arch image (supports arm64)
```

**How to Verify Image Architecture:**

```bash
# Check manifest
docker manifest inspect nginx:1.21 | jq '.manifests[].platform'

# Output should include:
# {
#   "architecture": "arm64",
#   "os": "linux"
# }
```

**Common Multi-Arch Images:**

- `nginx`, `alpine`, `busybox`
- `ghcr.io/`, `quay.io/` images (usually multi-arch)
- Official Kubernetes images (`registry.k8s.io/*`)

---

## 5. Labels and Selectors: Follow Kubernetes Conventions

**Rule:** Use standard labels for all resources.

### Recommended Labels (Kubernetes Common Labels)

```yaml
metadata:
  labels:
    app.kubernetes.io/name: myapp          # Application name
    app.kubernetes.io/instance: myapp-prod # Unique instance ID
    app.kubernetes.io/version: "1.0"       # Application version
    app.kubernetes.io/component: backend   # Component (backend, frontend, database)
    app.kubernetes.io/part-of: myplatform  # Higher-level application
    app.kubernetes.io/managed-by: argocd   # Tool managing this resource
```

### Service Selector

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/component: backend
  ports:
  - port: 80
    targetPort: 8080
```

**Why This Matters:**

- Consistent labels → easier `kubectl` queries
- ArgoCD uses labels for app tracking
- Monitoring tools (Prometheus) scrape by label

---

## 6. Services: Understand Type Differences

**Rule:** Choose the right Service type for your use case.

### Service Types

| Type | Use Case | Homekube Example |
|------|----------|------------------|
| `ClusterIP` | Internal-only | Database, backend APIs |
| `NodePort` | External access (static port) | ArgoCD UI (30000) |
| `LoadBalancer` | External access (dynamic IP) | Web apps via MetalLB |
| `ExternalName` | Alias to external DNS | Not used in homekube |

### ClusterIP (Default, Internal)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: myapp
spec:
  type: ClusterIP  # Default, can be omitted
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 8080
```

### NodePort (External, Static Port)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30000  # Must be 30000-32767
```

**Access:** `http://<any-node-ip>:30000`

### LoadBalancer (External, Dynamic IP via MetalLB)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-app
  namespace: myapp
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 8080
```

**MetalLB assigns IP from configured pool** (see `metallb` app in `homekube-apps`).

---

## 7. Health Checks: Liveness and Readiness Probes

**Rule:** Define both probes for all long-running containers.

### ❌ Bad Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
```

**Problem:** Kubernetes doesn't know if container is healthy or ready.

### ✅ Good Example

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
    ports:
    - containerPort: 8080
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

**Probe Types:**

- **Liveness:** Restart container if fails (detects deadlocks)
- **Readiness:** Stop sending traffic if fails (detects overload)
- **Startup:** Give slow-starting apps more time (Kubernetes 1.18+)

**Probe Methods:**

- `httpGet`: HTTP request (most common)
- `tcpSocket`: TCP connection (for non-HTTP services)
- `exec`: Run command in container

---

## 8. Security Contexts: Run as Non-Root

**Rule:** Never run containers as root unless absolutely required.

### ❌ Bad Example (Implicit Root)

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
```

### ✅ Good Example

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:1.0
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

**Security Best Practices:**

- `runAsNonRoot: true` — Enforces non-root user
- `readOnlyRootFilesystem: true` — Prevents writes to container filesystem (use volumes for writable paths)
- `capabilities.drop: [ALL]` — Removes all Linux capabilities
- `seccompProfile: RuntimeDefault` — Applies default seccomp profile

---

## 9. ConfigMaps and Secrets: Externalise Configuration

**Rule:** Don't hardcode config in image; use ConfigMaps and Secrets.

### ConfigMap (Non-Sensitive Data)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: myapp
data:
  database_host: postgres.myapp.svc.cluster.local
  database_port: "5432"
  log_level: info
```

### Secret (Sensitive Data)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: myapp
type: Opaque
stringData:
  database_password: "changeme"  # Base64-encoded when stored
```

### Using in Pod

```yaml
spec:
  containers:
  - name: app
    image: myapp:1.0
    env:
    - name: DATABASE_HOST
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: database_host
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: app-secrets
          key: database_password
    volumeMounts:
    - name: config-volume
      mountPath: /etc/app/config
  volumes:
  - name: config-volume
    configMap:
      name: app-config
```

---

## 10. ArgoCD Application Manifests

**Rule:** Define apps as Kubernetes manifests, not via UI.

### Application Structure

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Deploy order
spec:
  project: default
  source:
    repoURL: https://github.com/jangroth/homekube-apps.git
    targetRevision: HEAD
    path: applications/wave-01-apps/myapp
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true      # Delete resources not in Git
      selfHeal: true   # Auto-sync on drift
    syncOptions:
    - CreateNamespace=true
```

### Sync Waves (Control Deployment Order)

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # Deploy first (infrastructure)
```

**Wave Conventions:**

- `-2`: Root app
- `-1`: Infrastructure (metallb, metrics-server)
- `0`: Default (no annotation)
- `1+`: Applications (in order of dependencies)

---

## 11. Kustomize: Overlay Pattern for Environments

**Rule:** Use Kustomize for environment-specific configs (if needed).

### Base Manifests

```yaml
# base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:latest
```

### Overlay (Production)

```yaml
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../../base
replicas:
- name: myapp
  count: 3
images:
- name: myapp
  newTag: 1.0.5
```

**When to Use Kustomize:**

- Multiple environments (staging, production)
- Different resource limits per environment
- Environment-specific secrets

**When to Skip Kustomize:**

- Single environment (just use plain manifests)
- Simple apps (Kustomize adds complexity)

---

## 12. Debugging Manifest Issues

### Common Errors and Fixes

#### Error 1: "ImagePullBackOff"

```bash
kubectl describe pod <pod> -n <namespace>

# Check:
# - Image name correct?
# - Image exists for arm64?
# - Private registry needs imagePullSecrets?
```

#### Error 2: "CrashLoopBackOff"

```bash
kubectl logs <pod> -n <namespace>

# Check:
# - Application logs for errors
# - Liveness probe failing?
# - Missing environment variables?
```

#### Error 3: "Pending" (Not Scheduling)

```bash
kubectl describe pod <pod> -n <namespace>

# Common causes:
# - Insufficient resources (CPU/memory)
# - PVC not bound (storage issue)
# - Node selector doesn't match any nodes
```

#### Error 4: "ErrImagePull" with "exec format error"

```
Error: failed to start container: Error response from daemon: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: exec: "/app": cannot execute binary file: Exec format error
```

**Cause:** Image is x86_64, not arm64.  
**Fix:** Use multi-arch image or arm64-specific tag.

---

## 13. Manifest Validation

### Pre-Apply Checks

```bash
# Dry-run (client-side)
kubectl apply -f manifest.yaml --dry-run=client

# Dry-run (server-side, validates against cluster)
kubectl apply -f manifest.yaml --dry-run=server

# Validate YAML syntax
yamllint manifest.yaml

# Kubernetes manifest linting
kubectl-neat < manifest.yaml  # Removes noise
kube-linter lint manifest.yaml  # Security/best practices
```

### Schema Validation

```bash
# Install kubeval
brew install kubeval

# Validate manifest against Kubernetes 1.35 schema
kubeval --kubernetes-version 1.35.0 manifest.yaml
```

---

## 14. Resource Naming Conventions

**Rule:** Use lowercase, hyphens (not underscores), max 63 characters.

### Valid Names

- `web-app`
- `backend-api`
- `postgres-db`

### Invalid Names

- `webApp` (camelCase not recommended)
- `web_app` (underscores not allowed)
- `my-very-long-application-name-that-exceeds-sixty-three-characters` (too long)

### Namespace Naming

- Use app name: `myapp`, `monitoring`, `logging`
- Avoid generic names: `app`, `test`, `dev` (collision risk)
- System namespaces: `kube-*`, `metallb-system`, `longhorn-system`

---

## 15. Common Manifest Templates

### Template 1: Stateless Application

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:1.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
spec:
  type: ClusterIP
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

### Template 2: Stateful Application (with Storage)

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: postgres
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: postgres
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secrets
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: postgres
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

---

**End of Kubernetes Manifest Skills**  
See also: `AI-CONTEXT.md` (section 5: GitOps Pipeline).

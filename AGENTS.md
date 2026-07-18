# Sync-in Helm Chart

A first-class Helm chart for [Sync-in](https://sync-in.com) — an open-source collaborative platform — based on the official [docker-compose setup](https://sync-in.com/docs/setup-guide/docker/).

Supports optional **OnlyOffice DocumentServer** for in-browser document editing. Does not include Collabora or Euro-Office.

## Source material

- Official docker-compose: `https://github.com/Sync-in/server/releases/latest`
- Local reference: `sync-in-docker/` (downloaded compose stack)
- Docker images: `syncin/server:2`, `onlyoffice/documentserver:9.3.1.2`, `mariadb:11`

## Chart architecture

```
HTTPRoute (Gateway API) → envoy-external
  │
  ▼
nginx:alpine (reverse proxy)
  ├── /         → sync-in:8080
  └── /onlyoffice/ → onlyoffice:80   (gated by onlyoffice.enabled)
                            │
                    ┌───────┴───────┐
                    │  sync-in:8080 │
                    └───────┬───────┘
                            │
                mariadb:11  (single Deployment)
                (inline, no subchart)
```

## Key design decisions

| Decision | Choice |
|----------|--------|
| Database | **Inline `mariadb:11` Deployment** — single instance, matching the official docker-compose exactly. No Galera cluster, no subchart dependency. |
| External access | **Gateway API HTTPRoute** (not Ingress). Configurable parentRefs for envoy-proxy/gateway. |
| OnlyOffice | **Disabled by default** (`onlyoffice.enabled: false`). |
| Secrets | **Dual `existingSecret` pattern**: (1) **field-level** — `auth.existingSecret` + `*SecretKey` and `onlyoffice.existingSecret` + `jwtSecretKey` let you externalize individual secret values while the chart still renders `environment.yaml`; (2) **full-file** — `syncin.existingEnvSecret` replaces the entire `environment.yaml` for fully self-managed config. |
| Storage | Separate storageClass per component: `persistence.data.storageClass` (sync-in data) and `mariadb.persistence.storageClass` (MariaDB data). |
| Auth | Provider selected via `auth.provider` (`mysql` default, or `oidc`). Sensitive values come from either inline `.Values.auth.*` fields OR an `auth.existingSecret` with `*SecretKey` fields (`encryptionKeySecretKey`, `secretSecretKey`, `clientSecretSecretKey`). The chart always renders `environment.yaml` — only full-file escape is `syncin.existingEnvSecret`. |
| OIDC | Optional OpenID Connect login. Set `auth.provider: oidc` + `auth.oidc.*`. Sensitive values (`clientSecret`) come from inline `.Values.auth.oidc.clientSecret` or `auth.oidc.clientSecretSecretKey` (pointing to a key in `auth.existingSecret`). `redirectUri` **must** end with `/api/auth/oidc/callback`. For fully self-managed config, use `syncin.existingEnvSecret`. |

## Deployment modes

### Built-in MariaDB (default)
```bash
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=StrongPassword \
  --set auth.encryptionKey=... \
  --set auth.token.access.secret=... \
  --set auth.token.refresh.secret=...
```

### External database
```bash
helm install sync-in ./sync-in \
  --set mariadb.enabled=false \
  --set externalDatabase.host=my-mysql.svc.local \
  --set externalDatabase.user=syncin \
  --set externalDatabase.password=MyPass \
  --set auth.encryptionKey=... \
  --set auth.token.access.secret=... \
  --set auth.token.refresh.secret=...
```

### With OnlyOffice + HTTPRoute
```bash
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=... \
  --set auth.encryptionKey=... --set auth.token.access.secret=... --set auth.token.refresh.secret=... \
  --set onlyoffice.enabled=true \
  --set onlyoffice.jwtSecret=OOSecret \
  --set route.enabled=true \
  --set route.hostnames[0]=drive.plim.xyz
```

### With pre-created auth secrets
Instead of putting secrets in Helm values, pre-create a Secret and reference it:
```bash
kubectl create secret generic sync-in-auth \
  --from-literal=encryptionKey=<strong-key> \
  --from-literal=accessSecret=<strong-secret> \
  --from-literal=refreshSecret=<strong-secret> \
  -n sync-in

helm install sync-in ./sync-in \
  --set mariadb.rootPassword=... \
  --set auth.existingSecret=sync-in-auth \
  --set auth.encryptionKeySecretKey=encryptionKey \
  --set auth.token.access.secretSecretKey=accessSecret \
  --set auth.token.refresh.secretSecretKey=refreshSecret
```
Note: `helm template` won't resolve `lookup` values — use `helm install` directly.

The same pattern works for OnlyOffice:
```bash
kubectl create secret generic sync-in-onlyoffice \
  --from-literal=jwtSecret=<strong-secret> \
  -n sync-in

helm install sync-in ./sync-in \
  --set onlyoffice.enabled=true \
  --set onlyoffice.existingSecret=sync-in-onlyoffice \
  --set onlyoffice.jwtSecretKey=jwtSecret ...
```

### OIDC authentication
Set `auth.provider=oidc` and provide the `auth.oidc` block. The chart renders the
full `oidc:` section into `environment.yaml`.
```bash
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=... \
  --set auth.encryptionKey=... --set auth.token.access.secret=... --set auth.token.refresh.secret=... \
  --set auth.provider=oidc \
  --set auth.oidc.issuerUrl=https://auth.example.com/realms/main \
  --set auth.oidc.clientId=sync-in \
  --set auth.oidc.clientSecret=<secret> \
  --set auth.oidc.redirectUri=https://drive.plim.xyz/api/auth/oidc/callback \
  --set auth.oidc.options.adminRoleOrGroup=admins \
  --set 'auth.oidc.options.autoCreatePermissions={personal_space,spaces_access}' \
  --set auth.oidc.options.enablePasswordAuth=true   # keep local break-glass login
```

Notes:
- `redirectUri` **must** end with `/api/auth/oidc/callback` or the IdP handshake fails.
- Keep `options.enablePasswordAuth=true` if you still want local/admin password login as a fallback.
- **OIDC works with either secret source.** There are three ways to configure it:
  1. **Chart-generated** (no `existingEnvSecret`): set `auth.provider=oidc` + `auth.oidc.*` and
     the chart renders the `oidc:` block into `environment.yaml` for you.
  2. **Field-level secrets** (`auth.existingSecret` set): provide a Secret with auth values
     (encryptionKey, access/refresh tokens, OIDC clientSecret). Map them to the chart via
     `auth.encryptionKeySecretKey`, `auth.token.access.secretSecretKey`,
     `auth.token.refresh.secretSecretKey`, and `auth.oidc.clientSecretSecretKey`.
     The chart still renders the full `environment.yaml` — only sensitive values come from
     your Secret. Use `helm install/upgrade` (not `helm template`) for live lookups.
  3. **Self-managed** (`syncin.existingEnvSecret` set): put the full `environment.yaml` content —
     including your own `auth:`/`oidc:` block — inside your Secret's `environment.yaml` key.
     This keeps all config out of Helm values/Git.
- `syncin.existingEnvSecret` overrides the **entire** `environment.yaml` file — it's not
  limited to auth. All settings (mysql, applications, auth, etc.) must be in your Secret.
- LDAP is not templated — configure it via `syncin.existingEnvSecret` (case 3).

## Debugging with MCP

**Important**: Always use **read-only** Kubernetes operations (pods list, logs, events, resources get). Never create, update, delete, scale, or exec into cluster resources. Only modify the chart files in this repo — the user will handle syncing the changes to the cluster via Flux.

This chart is deployed on a Kubernetes cluster that provides `kubernetes_*` MCP tools. When pods fail, use these tools (read-only) to diagnose:

### Check deployment status
```
kubernetes_pods_list_in_namespace → namespace: sync-in
kubernetes_events_list → namespace: sync-in
kubernetes_resources_get → HelmRelease sync-in
```

### Check pod logs (read-only)
```
kubernetes_pods_log → pod name, namespace, tail lines
```

### Common past issues

1. **MariaDB bootstrap fails (pre-1.2.0)**: The bitnami/mariadb-galera subchart had compatibility issues with sync-in's SQL queries and complex Galera bootstrapping. **Fixed in 1.2.0 by replacing with inline `mariadb:11` Deployment matching the official docker-compose.**

2. **sync-in pod crashes before MariaDB is ready**: Added an init container (`busybox nc -z`) that polls the MariaDB Service until it has endpoints. Only created when `mariadb.enabled` is true.

3. **HelmRelease stuck with `observedGeneration: -1`**: Flux helm-controller skips reconciliation when the previous attempt left a deadlock. Check helm-controller logs: `kubernetes_pods_log → flux-system/helm-controller-*`. Force reconcile with `flux reconcile helmrelease sync-in -n sync-in`.

## Updating the chart

```bash
# Lint
helm lint ./sync-in

# Template dry-run with test values
helm template test ./sync-in -f test-values.yaml

# Package for OCI / Flux
helm package ./sync-in
```

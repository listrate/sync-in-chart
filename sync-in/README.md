# Sync-in Helm Chart

A Helm chart for [Sync-in](https://sync-in.com) — an open-source collaborative platform — with optional **OnlyOffice DocumentServer** for in-browser document editing.

```sh
helm install sync-in oci://ghcr.io/listrate/charts/sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret
```

## Secret management

The chart provides three ways to manage secrets, with clear separation of concerns:

### 1. Inline values (simplest)

Put secrets directly in `--set` flags or a values file. The chart renders `environment.yaml` with all values.

```sh
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret
```

### 2. Field-level secrets (keep values out of Git)

Pre-create a Kubernetes Secret with individual keys, then reference it via `existingSecret` + `*SecretKey` fields. The chart **still renders `environment.yaml`** — only the referenced sensitive values come from your Secret.

```sh
kubectl create secret generic sync-in-auth \
  --from-literal=encryptionKey=MyEncKey \
  --from-literal=accessSecret=MyAccessSecret \
  --from-literal=refreshSecret=MyRefreshSecret

helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.existingSecret=sync-in-auth \
  --set auth.encryptionKeySecretKey=encryptionKey \
  --set auth.token.access.secretSecretKey=accessSecret \
  --set auth.token.refresh.secretSecretKey=refreshSecret
```

The same pattern works for OnlyOffice:

```sh
kubectl create secret generic sync-in-oo \
  --from-literal=jwtSecret=MyOOSecret

helm install sync-in ./sync-in \
  --set onlyoffice.enabled=true \
  --set onlyoffice.existingSecret=sync-in-oo \
  --set onlyoffice.jwtSecretKey=jwtSecret
```

> **Important**: `helm template` won't resolve `lookup` values (no API server). Use `helm install/upgrade` directly when using `existingSecret`.

### 3. Full-file override (self-managed config)

Set `syncin.existingEnvSecret` to the name of a Secret containing key `environment.yaml`. The chart **skips all `environment.yaml` generation** and mounts your file directly. Use this for LDAP, advanced OIDC, or fully self-managed config.

```sh
kubectl create secret generic sync-in-full-env \
  --from-file=environment.yaml=./my-environment.yaml

helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set syncin.existingEnvSecret=sync-in-full-env
```

### Which approach should I use?

| Use case | Approach |
|---|---|
| Quick dev/test | Inline values (#1) |
| Production, keep secrets out of Git | Field-level secrets (#2) |
| LDAP or custom config not covered by chart values | Full-file override (#3) |

## Common deployments

### Built-in MariaDB (default)

```sh
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret
```

### External database

```sh
helm install sync-in ./sync-in \
  --set mariadb.enabled=false \
  --set externalDatabase.host=my-mysql.svc.local \
  --set externalDatabase.user=syncin \
  --set externalDatabase.password=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret
```

### With OnlyOffice + HTTPRoute

```sh
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret \
  --set onlyoffice.enabled=true \
  --set onlyoffice.jwtSecret=MyOOSecret \
  --set route.enabled=true \
  --set route.hostnames[0]=drive.example.com
```

### OIDC authentication

```sh
helm install sync-in ./sync-in \
  --set mariadb.rootPassword=MyDbPass \
  --set auth.encryptionKey=MyEncKey \
  --set auth.token.access.secret=MyAccessSecret \
  --set auth.token.refresh.secret=MyRefreshSecret \
  --set auth.provider=oidc \
  --set auth.oidc.issuerUrl=https://auth.example.com/realms/main \
  --set auth.oidc.clientId=sync-in \
  --set auth.oidc.clientSecret=MyClientSecret \
  --set auth.oidc.redirectUri=https://drive.example.com/api/auth/oidc/callback \
  --set 'auth.oidc.options.autoCreatePermissions={personal_space,spaces_access}' \
  --set auth.oidc.options.adminRoleOrGroup=admins \
  --set auth.oidc.options.enablePasswordAuth=true
```

> `redirectUri` **must** end with `/api/auth/oidc/callback`.

## Configuration

### Required auth values

| Parameter | Description |
|---|---|
| `auth.encryptionKey` | Server encryption key |
| `auth.token.access.secret` | Access token secret |
| `auth.token.refresh.secret` | Refresh token secret |

When using `auth.existingSecret`, set the corresponding `*SecretKey` fields instead and omit the inline values.

### OnlyOffice

| Parameter | Default | Description |
|---|---|---|
| `onlyoffice.enabled` | `false` | Enable OnlyOffice DocumentServer |
| `onlyoffice.jwtSecret` | `""` | JWT secret (must match between sync-in and onlyoffice) |
| `onlyoffice.existingSecret` | `""` | Existing Secret name for JWT secret |
| `onlyoffice.jwtSecretKey` | `""` | Key in `onlyoffice.existingSecret` |

### HTTPRoute (Gateway API)

| Parameter | Default | Description |
|---|---|---|
| `route.enabled` | `false` | Create an HTTPRoute |
| `route.hostnames` | `[]` | Hostnames for the route |
| `route.parentRefs[0].name` | `envoy-external` | Gateway name |

### MariaDB

| Parameter | Default | Description |
|---|---|---|
| `mariadb.enabled` | `true` | Deploy built-in MariaDB (mariadb:11) |
| `mariadb.database` | `sync_in` | Database name |
| `mariadb.rootPassword` | `""` | Root password (required) |
| `mariadb.resources` | `{}` | Resource requests/limits |
| `mariadb.persistence.enabled` | `true` | Persist MariaDB data |
| `mariadb.persistence.size` | `10Gi` | PVC size |
| `mariadb.persistence.storageClass` | `""` | Storage class |

### External database

| Parameter | Default | Description |
|---|---|---|
| `externalDatabase.host` | `""` | External MySQL host |
| `externalDatabase.port` | `3306` | External MySQL port |
| `externalDatabase.user` | `root` | Database user |
| `externalDatabase.password` | `""` | Database password |
| `externalDatabase.database` | `sync_in` | Database name |
| `externalDatabase.url` | `""` | Full connection URL (overrides host/user/password) |

### Persistence

| Parameter | Default | Description |
|---|---|---|
| `persistence.data.enabled` | `true` | Persist sync-in app data |
| `persistence.data.size` | `10Gi` | PVC size |
| `persistence.data.storageClass` | `""` | Storage class |

## Architecture

```
HTTPRoute → nginx:alpine (reverse proxy)
  ├── /         → sync-in:8080
  └── /onlyoffice/ → onlyoffice:80   (gated by onlyoffice.enabled)
                            │
                    ┌───────┴───────┐
                    │  sync-in:8080 │
                    └───────┬───────┘
                            │
                mariadb:11  (single Deployment)
```

- **Database**: `mariadb:11` single-instance Deployment (matches official docker-compose)
- **External access**: Gateway API HTTPRoute (not Ingress)
- **OnlyOffice**: Disabled by default, uses `onlyoffice/documentserver:9.3.1.2`

## Changelog

### 1.2.0

- **Breaking**: Replace `bitnami/mariadb-galera` subchart with inline `mariadb:11` Deployment matching the official docker-compose setup.
  - `mariadb-galera.*` values removed. Use `mariadb.rootPassword` instead of `mariadb-galera.rootUser.password`.
  - Single-instance MariaDB (no Galera cluster). Matches docker-compose behavior.
  - MariaDB data stored at `/var/lib/mysql` (same as docker-compose).

### 1.1.2

- Add `checksum/*` annotations to deployment pod templates so pods restart when secrets/configmaps change:
  - `deployment-syncin.yaml`: checksum over `secret-env.yaml` (environment config)
  - `deployment-nginx.yaml`: checksum over both nginx ConfigMaps
  - `deployment-onlyoffice.yaml`: checksum over `secret-onlyoffice.yaml`
- Enable MySQL event scheduler at MariaDB startup (`event_scheduler=ON`) to prevent sync-in cache module from failing `SET GLOBAL event_scheduler = ON` on startup

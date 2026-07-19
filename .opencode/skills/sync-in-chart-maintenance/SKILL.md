---
name: sync-in-chart-maintenance
description: Use when maintaining the sync-in Helm chart — processing Renovate PRs, updating dependencies, bumping the chart version, running tests, cutting a release, or cleaning up stale branches. Covers lint/unittest/template verification, auto-bump workflow interaction, and gh CLI operations for the listrate/sync-in-chart repo.
---

# sync-in Helm Chart Maintenance

## Repository

- **GitHub**: `listrate/sync-in-chart`
- **Chart path**: `./sync-in/`
- **Upstream server**: `https://github.com/Sync-in/server`
- **Upstream docker-compose**: `https://github.com/Sync-in/server/releases/latest`
- **OCI registry**: `ghcr.io/listrate/charts`

## Guiding principles

1. **Stay faithful to upstream docker-compose references** — the chart mirrors the official setup. If upstream hasn't bumped MariaDB or other core services, we don't either.
2. **Pin syncin/server to a specific version** — prefer `tag: "2.4.2"` over floating `tag: "2"`. Update `appVersion` in Chart.yaml to match.
3. **Non-server image changes = patch bump**. Server image changes = major bump. CI-only action bumps don't change chart functionality.
4. **Always run the full test suite** (lint + unittest + template) before committing.

## Test commands

```bash
# Lint
helm lint ./sync-in -f test-values.yaml

# Unit tests (68 tests across 17 suites)
helm unittest ./sync-in -f test-values.yaml

# Template dry-run
helm template test-release ./sync-in -f test-values.yaml --no-hooks > /dev/null
```

If tests fail due to image tag changes, update the hardcoded assertions in `sync-in/tests/<template>_test.yaml`.

## Processing Renovate PRs

Renovate opens PRs for Docker image bumps and GitHub Action bumps. The auto-bump workflow pushes a second commit (`chore: bump chart version to X.Y.Z`) onto each Renovate PR. This causes Renovate to disable auto-rebase. Use `rebaseWhen: "behind-base-branch"` in `renovate.json` to fix this.

### When multiple Renovate PRs stack up (8+):

1. **Group PRs by risk**:
   - *Safe*: Minor/patch Docker bumps (OnlyOffice), GitHub Action bumps
   - *Risky*: Major version bumps for core services (MariaDB, nginx), Helm major versions
2. **Check upstream docker-compose** for risky bumps — if the upstream repo hasn't adopted it, close the PR.
3. **Consolidate** — rather than merging 6+ PRs individually (each with conflicting version bumps), create a single commit that applies all safe changes at once.
4. **Close the superseded PRs** after the consolidation commit merges.

### To consolidate into a single release:

Update these files in one commit:

| File | What to change |
|------|----------------|
| `sync-in/values.yaml` | Docker image tags (syncin/server, onlyoffice/documentserver, etc.) |
| `sync-in/Chart.yaml` | `version` (patch bump for deps), `appVersion` (match server tag) |
| `.github/workflows/test.yaml` | `actions/checkout`, `azure/setup-helm`, helm version |
| `.github/workflows/release.yaml` | Same as test.yaml + `docker/login-action`, `softprops/action-gh-release` |
| `.github/workflows/auto-bump.yaml` | `actions/checkout` |
| `sync-in/tests/*_test.yaml` | Any hardcoded image tags in assertions |
| `.github/renovate.json` | Regex patterns if tag format changed (e.g. `\d+` → `[\d.]+`) |

Then:
```bash
helm lint ./sync-in -f test-values.yaml
helm unittest ./sync-in -f test-values.yaml
helm template test-release ./sync-in -f test-values.yaml --no-hooks > /dev/null
git add -A && git commit -m "release: sync-in-chart vX.Y.Z ..."
git push origin main
```

## Release workflow

The release workflow (`release.yaml`) triggers automatically on push to `main` when `sync-in/Chart.yaml` changes. It:
1. Runs lint + unittest + template dry-run (in `test.yaml` workflow)
2. Packages the chart: `helm package ./sync-in`
3. Pushes OCI artifact: `helm push sync-in-*.tgz oci://ghcr.io/listrate/charts`
4. Creates a GitHub Release with the `.tgz` asset

## Cleanup after release

```bash
# List remote Renovate branches
gh api repos/listrate/sync-in-chart/branches --jq '.[].name' | grep renovate

# Delete all stale branches
for branch in <branch-names>; do
  git push origin --delete "$branch"
done

# Close superseded PRs (use correct numbers)
gh pr close 4 --repo listrate/sync-in-chart -c "Superseded by vX.Y.Z release"
gh pr close 5 --repo listrate/sync-in-chart -c "Superseded by vX.Y.Z release"
# ... repeat for all PRs
```

## Version bump rules

The auto-bump workflow (`auto-bump.yaml`) determines the new version:

- **syncin/server image changed**: MAJOR bump (1.2.2 → 2.0.0) AND `appVersion` synced to the new tag
- **Any other change**: PATCH bump (1.2.2 → 1.2.3)

The auto-bump only fires on Renovate PRs (`github.actor == 'renovate[bot]'`). Manual commits must bump explicitly.

## Key files reference

| File | Purpose |
|------|---------|
| `sync-in/Chart.yaml` | Chart version, appVersion, metadata |
| `sync-in/values.yaml` | Default values, image tags, feature toggles |
| `sync-in/templates/` | 18 Kubernetes resource templates |
| `sync-in/tests/` | 17 helm-unittest suites |
| `test-values.yaml` | Minimal secrets for CI test runs |
| `.github/workflows/test.yaml` | PR/push CI: lint, unittest, template |
| `.github/workflows/release.yaml` | Chart packaging + GitHub Release |
| `.github/workflows/auto-bump.yaml` | Auto-bumps Chart.yaml on Renovate PRs |
| `.github/renovate.json` | Renovate config with regex managers for Docker tags |
| `AGENTS.md` | Project documentation and chart architecture |

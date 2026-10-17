---
name: sync-in-chart-maintenance
description: Use when maintaining the sync-in Helm chart — processing Renovate PRs, updating dependencies, bumping the chart version, running tests, cutting a release, or cleaning up stale branches. Covers lint/unittest/template verification, the post-merge release workflow, and gh CLI operations for the listrate/sync-in-chart repo.
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

# Unit tests (91 tests across 20 suites)
helm unittest ./sync-in --values test-values.yaml

# Template dry-run
helm template test-release ./sync-in -f test-values.yaml --no-hooks > /dev/null
```

If tests fail due to image tag changes, update the hardcoded assertions in `sync-in/tests/<template>_test.yaml`.

## Processing Renovate PRs

Renovate opens PRs for Docker image bumps and GitHub Action bumps. **No workflow
edits Renovate branches any more** — the old auto-bump workflow pushed a version
commit onto each PR, which made Renovate mark them "Edited (Blocked)" and stop
rebasing. Version bumps now happen post-merge in `release.yaml`, so Renovate PRs
stay updatable.

`renovate.json` constrains the risky dependencies:

- `mariadb` → `11.x` only (upstream compose uses 11; 13.x is a rolling non-LTS release)
- `onlyoffice/documentserver` → `>=9.3.1.2 <9.4.0` (upstream pins 9.3.1.2; 9.4.0.1 can break Firefox)
- `helm` (CI) → `3.x` (Helm 4 not validated against helm-unittest yet)

### When multiple Renovate PRs stack up:

1. **Group PRs by risk**:
   - *Safe*: Minor/patch Docker bumps, GitHub Action bumps
   - *Risky*: Major version bumps for core services (MariaDB, OnlyOffice, nginx), Helm major versions
2. **Check upstream docker-compose** for risky bumps — if upstream hasn't adopted it, close the PR.
3. **Merge or consolidate** — safe one-line PRs can be merged directly (each merge
   auto-releases a patch). For a larger change, create one commit that applies all
   safe changes and set the release version in `Chart.yaml`.
4. **Close the superseded PRs** after the consolidation commit merges.

### To consolidate into a single release:

Update these files in one commit:

| File | What to change |
|------|----------------|
| `sync-in/values.yaml` | Docker image tags (syncin/server, onlyoffice/documentserver, drawio, etc.) |
| `sync-in/Chart.yaml` | `version` (major if server changed, otherwise patch), `appVersion` (match server tag) |
| `.github/workflows/test.yaml` | `actions/checkout`, `azure/setup-helm`, helm version |
| `.github/workflows/release.yaml` | Same as test.yaml + `docker/login-action`, `softprops/action-gh-release` |
| `sync-in/tests/*_test.yaml` | Any hardcoded image tags in assertions |
| `.github/renovate.json` | Regex patterns if tag format changed (e.g. `\d+` → `[\d.]+`), or `allowedVersions` rules |

Bumping `Chart.yaml` explicitly makes the release workflow use that version; if
you leave it unchanged, the workflow computes the bump from the tags/flags in
the push.

Then:
```bash
helm lint ./sync-in -f test-values.yaml
helm unittest ./sync-in --values test-values.yaml
helm template test-release ./sync-in -f test-values.yaml --no-hooks > /dev/null
git add -A && git commit -m "release: sync-in-chart vX.Y.Z ..."
git push origin main
```

## Release workflow

`release.yaml` runs on any push to `main` that touches `sync-in/Chart.yaml`,
`sync-in/values.yaml`, or `sync-in/templates/**`. It:
1. Uses the pushed `Chart.yaml` version if that file changed; otherwise computes
   the bump (server tag change = major + `appVersion` sync, anything else = patch)
   and commits it back to `main`
2. Packages the chart: `helm package ./sync-in`
3. Pushes the OCI artifact: `helm push sync-in-*.tgz oci://ghcr.io/listrate/charts`
4. Creates a GitHub Release with the `.tgz` asset (skips if the release exists)

Note: pushes made with `GITHUB_TOKEN` do not trigger further workflows, which is
why bump, package and release all live in this one workflow.

`test.yaml` runs lint + unittest + template on every PR and push to `main`.

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

The release workflow (`release.yaml`) determines the new version post-merge:

- **syncin/server image changed**: MAJOR bump (1.2.2 → 2.0.0) AND `appVersion` synced to the new tag
- **Any other chart change**: PATCH bump (1.2.2 → 1.2.3)
- **`Chart.yaml` already changed in the push**: that exact version is used (manual/feature release)

There is no longer a separate auto-bump workflow; do not add one that pushes to
Renovate branches.

## Key files reference

| File | Purpose |
|------|---------|
| `sync-in/Chart.yaml` | Chart version, appVersion, metadata |
| `sync-in/values.yaml` | Default values, image tags, feature toggles |
| `sync-in/templates/` | 20 Kubernetes resource templates |
| `sync-in/tests/` | 20 helm-unittest suites (91 tests) |
| `test-values.yaml` | Minimal secrets for CI test runs |
| `.github/workflows/test.yaml` | PR/push CI: lint, unittest, template |
| `.github/workflows/release.yaml` | Version bump + packaging + OCI push + GitHub Release |
| `.github/renovate.json` | Renovate config: custom managers for Docker tags, version constraints |
| `AGENTS.md` | Project documentation and chart architecture |

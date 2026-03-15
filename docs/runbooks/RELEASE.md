# Release Runbook

## Prerequisites

### GitHub Secrets

These must be configured under **Settings > Secrets and variables > Actions** on the repo before the first release.

| Secret | Required | Notes |
|---|---|---|
| `GITHUB_TOKEN` | Auto-provided | No setup needed |
| `BCR_PUBLISH_TOKEN` | Manual setup | Classic PAT with `repo` scope; must have access to `reutermj/bazel-central-registry` |

**One-time setup for `BCR_PUBLISH_TOKEN`:**
1. Go to GitHub > Settings > Developer settings > Personal access tokens > Tokens (classic)
2. Generate a new token with `repo` scope
3. Add it as a secret named `BCR_PUBLISH_TOKEN` on `reutermj/toolchains_rpmbuild_prebuilt`

### BCR Fork

Your fork `reutermj/bazel-central-registry` must exist and be up to date with `bazelbuild/bazel-central-registry` before publishing.

---

## Release Steps

### 1. Update the version in MODULE.bazel

The version uses date-based format `YYYY.M.D`. Update it to today's date:

```
module(
    name = "toolchains_rpmbuild_prebuilt",
    version = "2026.3.15",   # <-- update this
    ...
)
```

Commit and push to `main`.

### 2. Verify tests pass

Check that the test workflows are green on `main`:

```bash
gh run list --workflow=test_x86_64.yml --branch=main --limit=1
gh run list --workflow=test_aarch64.yml --branch=main --limit=1
```

Both should show `completed` / `success`. If not, do not proceed.

### 3. Trigger the publish workflow

```bash
gh workflow run publish.yml --ref main
```

Watch progress:

```bash
gh run list --workflow=publish.yml --limit=1
# Once you have the run ID:
gh run watch <run-id>
```

The workflow runs two jobs:

**Job 1 — `create-release`**
- Reads the version from `MODULE.bazel`
- Creates `toolchains_rpmbuild_prebuilt-<VERSION>.tar.gz` via `git archive`
- Creates a GitHub Release tagged with the version

**Job 2 — `publish`**
- Calls the `bazel-contrib/publish-to-bcr` reusable workflow
- Pushes a branch `toolchains_rpmbuild_prebuilt-<VERSION>` to the fork `reutermj/bazel-central-registry`
- Opens a draft PR on `bazelbuild/bazel-central-registry` from `reutermj:toolchains_rpmbuild_prebuilt-<VERSION>`

Verify the GitHub Release was created and find the BCR PR:

```bash
gh release view <VERSION> --repo reutermj/toolchains_rpmbuild_prebuilt
gh pr list --repo bazelbuild/bazel-central-registry --author reutermj
```

### 4. Smoke test against the private BCR

Before marking the BCR PR ready for review, validate the registry entry works using the `e2e/` example (see [Smoke test against the private BCR](#smoke-test-against-the-private-bcr) below).

### 5. Mark the BCR PR ready and wait for merge

Once the smoke test passes, mark the draft PR as ready:

```bash
gh pr ready <pr-number> --repo bazelbuild/bazel-central-registry
```

BCR will run presubmit checks (module resolution on Bazel 7.x and 8.x, no test execution). Once approved and merged, the module version is publicly available.

---

## Verifying the Release

After the BCR PR is merged, users can depend on the module with:

```python
bazel_dep(name = "toolchains_rpmbuild_prebuilt", version = "<VERSION>")
register_toolchains("@toolchains_rpmbuild_prebuilt")
```

### Smoke test against the private BCR

The `e2e/` directory contains a standalone Bazel workspace that exercises the full toolchain by building and installing a hello-world RPM. Run it against the private BCR (`reutermj/bazel-central-registry`) to confirm the registry entry works before the official BCR PR is merged:

```bash
cd e2e
bazel test \
  --registry=https://raw.githubusercontent.com/reutermj/bazel-central-registry/toolchains_rpmbuild_prebuilt-<VERSION>/ \
  --registry=https://bcr.bazel.build/ \
  //:validate_rpm
```

A passing test confirms:
- The module resolves correctly from the registry
- The prebuilt rpmbuild binary is downloaded and registered as a toolchain
- `pkg_rpm()` successfully builds an RPM
- The RPM installs correctly

---

## Relevant Files

| File | Purpose |
|---|---|
| [MODULE.bazel](MODULE.bazel) | Module definition — update `version` before each release |
| [.bcr/metadata.template.json](.bcr/metadata.template.json) | BCR metadata (homepage, maintainer) |
| [.bcr/source.template.json](.bcr/source.template.json) | Source URL template for BCR |
| [.bcr/presubmit.yml](.bcr/presubmit.yml) | BCR presubmit config (module resolution only, no tests) |
| [.github/workflows/publish.yml](.github/workflows/publish.yml) | Publish workflow |
| [.github/workflows/publish/publish.sh](.github/workflows/publish/publish.sh) | Script that creates the GitHub Release |
| [e2e/](e2e/) | Standalone smoke-test workspace for validating a registry entry |

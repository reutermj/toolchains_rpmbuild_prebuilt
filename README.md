# Prebuilt rpmbuild Toolchain for Bazel

Prebuilt, statically linked `rpmbuild` binaries for use with
[rules_pkg](https://github.com/bazelbuild/rules_pkg)'s `pkg_rpm()` rule. The binaries are fully self-contained with no system dependencies, making them
ideal for remote execution environments. All binaries are built via GitHub
Actions with [SLSA provenance](https://slsa.dev/) attestations. Provenance is
verified at download time using the [GitHub CLI](https://cli.github.com/)
(`gh` >= 2.49.0); see [SLSA provenance verification](#slsa-provenance-verification)
for details.

## Setup

Add the module dependency and register the toolchain in your `MODULE.bazel`.
Once registered, `pkg_rpm()` picks it up automatically:

```starlark
bazel_dep(name = "toolchains_rpmbuild_prebuilt")
git_override(
    module_name = "toolchains_rpmbuild_prebuilt",
    remote = "https://github.com/reutermj/toolchains_rpmbuild_prebuilt.git",
    commit = "<commit-sha>",
)

prebuilt_rpmbuild_toolchain = use_repo_rule(
    "@toolchains_rpmbuild_prebuilt//:defs.bzl",
    "prebuilt_rpmbuild_toolchain",
)
prebuilt_rpmbuild_toolchain(name = "rpmbuild")
register_toolchains("@rpmbuild")
```

This defaults to RPM 6.0 on the host architecture.

The `version` attribute selects which RPM major.minor version to use. The latest
patch release is resolved automatically:

```starlark
prebuilt_rpmbuild_toolchain(name = "rpmbuild", version = "4.20")
```

When the execution platform differs from the host (e.g. remote execution), set
the `arch` attribute so the correct binary is downloaded:

```starlark
prebuilt_rpmbuild_toolchain(name = "rpmbuild_x86_64", arch = "x86_64")
prebuilt_rpmbuild_toolchain(name = "rpmbuild_aarch64", arch = "aarch64")
```

### `rules_python` toolchain

`rules_pkg`'s `pkg_rpm()` is implemented as a `py_binary`, so a hermetic Python
toolchain is required. Add `rules_python` to your `MODULE.bazel` and register a
Python toolchain:

```starlark
bazel_dep(name = "rules_python", version = "1.9.0")

python = use_extension("@rules_python//python/extensions:python.bzl", "python")
python.toolchain(
    python_version = "3.12",
    is_default = True,
)
```

### IMPORTANT NOTE:

You will likely need to add the following to your `.bazelrc`:

```
common --@rules_python//python/config_settings:bootstrap_impl=script
```

This is not specific to this package. It is a consequence of how `rules_pkg`
invokes `pkg_rpm()` via a `py_binary`. By default, `rules_python` generates a
Python bootstrap script with a `#!/usr/bin/env python3` shebang. If `python3`
is not on the system `PATH`, the action fails before the hermetic interpreter
can be located. Setting `bootstrap_impl=script` generates a shell-based
bootstrap instead, which locates the hermetic Python interpreter from the
runfiles tree without requiring any system Python.

## Supported versions

| RPM version | Architectures       |
|-------------|---------------------|
| 6.0         | x86_64, aarch64     |
| 4.20        | x86_64, aarch64     |
| 4.19        | x86_64, aarch64     |

Only the latest patch release of each `major.minor` version is tracked. The
toolchain resolves the patch version automatically.

## SLSA provenance verification

By default, this module verifies [SLSA build provenance](https://slsa.dev/)
for every downloaded tarball using the
[GitHub CLI](https://cli.github.com/) (`gh`). This confirms the binary was built
by this repository's GitHub Actions workflow and has not been tampered with.

**Requirements:** `gh` >= 2.49.0 on `PATH`, authenticated (`gh auth login`).

To disable verification:

```starlark
prebuilt_rpmbuild_toolchain(name = "rpmbuild", verify_provenance = False)
```

## Version override via environment

The version can also be overridden at build time without modifying
`MODULE.bazel`. This is primarily useful in CI matrices that test multiple RPM
versions:

```
bazel build //my:rpm_target --repo_env=rpmbuild_version=4.19
```

The environment variable name is `{repo_rule_name}_version` — if you named the
repo rule `rpmbuild`, the variable is `rpmbuild_version`.

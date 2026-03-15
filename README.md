# Prebuilt rpmbuild Toolchain for Bazel

Prebuilt, statically linked `rpmbuild` binaries for use with
[rules_pkg](https://github.com/bazelbuild/rules_pkg)'s `pkg_rpm()` rule. The binaries are fully self-contained with no system dependencies, making them
ideal for remote execution environments. All binaries are built via GitHub
Actions with [SLSA provenance](https://slsa.dev/) attestations.

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
prebuilt_rpmbuild_toolchain(name = "rpmbuild", arch = "aarch64")
```

Accepted values: `x86_64`, `aarch64`.

## Supported versions

| RPM version | Architectures       |
|-------------|---------------------|
| 6.0         | x86_64, aarch64     |
| 4.20        | x86_64, aarch64     |
| 4.19        | x86_64, aarch64     |

Only the latest patch release of each `major.minor` version is tracked. The
toolchain resolves the patch version automatically.

## Version override via environment

The version can also be overridden at build time without modifying
`MODULE.bazel`. This is primarily useful in CI matrices that test multiple RPM
versions:

```
bazel build //my:rpm_target --repo_env=rpmbuild_version=4.19
```

The environment variable name is `{repo_rule_name}_version` — if you named the
repo rule `rpmbuild`, the variable is `rpmbuild_version`.

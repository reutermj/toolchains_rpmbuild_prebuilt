"""Macro that declares an rpmbuild toolchain and registers it."""

load("@rules_pkg//toolchains/rpm:rpmbuild.bzl", "rpmbuild_toolchain")

def declare_rpmbuild_toolchain(name, data, version, cpu, visibility = None):
    """Declares an rpmbuild toolchain with platform constraints.

    Args:
        name: Name for the toolchain rule.
        data: glob of all RPM runtime config files to include when executing rpmbuild.
        version: RPM version string.
        cpu: CPU architecture for exec_compatible_with (e.g. "x86_64", "aarch64").
        visibility: Visibility of the toolchain.
    """
    rpmbuild_toolchain(
        name = name + "_info",
        data = data,
        version = version,
        visibility = ["//visibility:private"],
    )

    native.toolchain(
        name = name,
        toolchain = ":" + name + "_info",
        toolchain_type = "@rules_pkg//toolchains/rpm:rpmbuild_toolchain_type",
        exec_compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:" + cpu,
        ],
        visibility = visibility,
    )

"""Public API for toolchains_rpmbuild_prebuilt."""

load("//private:prebuilt_rpmbuild_toolchain.bzl", _prebuilt_rpmbuild_toolchain = "prebuilt_rpmbuild_toolchain")

prebuilt_rpmbuild_toolchain = _prebuilt_rpmbuild_toolchain

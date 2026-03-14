"""Public API for toolchains_rpmbuild_prebuilt."""

load("//private:rpmbuild_repo.bzl", _prebuilt_rpmbuild_toolchain = "prebuilt_rpmbuild_toolchain")

prebuilt_rpmbuild_toolchain = _prebuilt_rpmbuild_toolchain

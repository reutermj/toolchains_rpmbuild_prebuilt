"""Public API for toolchains_rpmbuild_prebuilt."""

load("//private:rpmbuild_repo.bzl", _rpmbuild_repo = "rpmbuild_repo")

rpmbuild_repo = _rpmbuild_repo

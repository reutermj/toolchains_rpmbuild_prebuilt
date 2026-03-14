load("@rules_pkg//toolchains/rpm:rpmbuild.bzl", "rpmbuild_toolchain")

rpmbuild_toolchain(
    name = "rpmbuild_info",
    path = "{rpmbuild_path}",
    version = "{version}",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "rpmbuild_toolchain",
    toolchain = ":rpmbuild_info",
    toolchain_type = "@rules_pkg//toolchains/rpm:rpmbuild_toolchain_type",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:{cpu}",
    ],
    visibility = ["//visibility:public"],
)

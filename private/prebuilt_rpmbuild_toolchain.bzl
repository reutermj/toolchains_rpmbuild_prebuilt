"""Repository rule that downloads and declares a prebuilt rpmbuild toolchain."""

_DOWNLOAD_BASE_URL = "https://github.com/reutermj/toolchains_rpmbuild_prebuilt/releases/download/binaries"

_ARCH_MAP = {
    "amd64": "x86_64",
    "x86_64": "x86_64",
    "aarch64": "aarch64",
    "arm64": "aarch64",
}

_TARBALL_TO_SHA256 = {
    "rpmbuild-x86_64-linux-6.0.1-20260314.tar.xz": "25afc406f24e688beb1e3cf83d4e79864e3360b28efb066709d78925824d2b98",
    "rpmbuild-aarch64-linux-6.0.1-20260314.tar.xz": "227a1de5a954f0af2d35ae25e9b7b35de395d7dba63191ac23368a023f0223bd",
    "rpmbuild-x86_64-linux-4.20.1-20260314.tar.xz": "7ce9e6cdabaae146938bdfde774fdca0380837c80ad0edaf0e7feee02108c41b",
    "rpmbuild-aarch64-linux-4.20.1-20260314.tar.xz": "9826fdc1e24509ba5c2ca4a02c2d797226959f8accba19d43cbbf5456d0fb498",
    "rpmbuild-x86_64-linux-4.19.1.1-20260314.tar.xz": "9e58e003722307217ecd0bdc5c7d183aadb5d6302fa64e4e6fed5b228da12ad0",
    "rpmbuild-aarch64-linux-4.19.1.1-20260314.tar.xz": "58dfeea006f0684e218ac30a4316c3febfc648e51a72f147d19c17bf53acb3e5",
}

# Maps major.minor version to the latest supported patch version and build date.
_VERSION_MAP = {
    "6.0": ("6.0.1", "20260314"),
    "4.20": ("4.20.1", "20260314"),
    "4.19": ("4.19.1.1", "20260314"),
}

def _prebuilt_rpmbuild_toolchain(rctx):
    if rctx.attr.arch:
        arch = _ARCH_MAP.get(rctx.attr.arch, None)
        if arch == None:
            fail("Unsupported architecture: {}. Supported: {}".format(
                rctx.attr.arch,
                ", ".join(_ARCH_MAP.keys()),
            ))
    else:
        arch = _ARCH_MAP.get(rctx.os.arch, None)
        if arch == None:
            fail("Unsupported host architecture: {}".format(rctx.os.arch))

    # Allow overriding version via --repo_env={name}_version=<major.minor>
    env_var = "{}_version".format(rctx.original_name)
    version = rctx.getenv(env_var)
    if version == None:
        version = rctx.attr.version

    entry = _VERSION_MAP.get(version, None)
    if entry == None:
        fail("Unsupported rpmbuild version: {}. Supported: {}".format(
            version,
            ", ".join(_VERSION_MAP.keys()),
        ))

    patch_version, date = entry
    tarball_name = "rpmbuild-{}-linux-{}-{}.tar.xz".format(arch, patch_version, date)
    sha256 = _TARBALL_TO_SHA256.get(tarball_name, "")
    if sha256 == "":
        fail("No sha256 for {}. Supported tarballs: {}".format(
            tarball_name,
            ", ".join(_TARBALL_TO_SHA256.keys()),
        ))

    rctx.download_and_extract(
        url = "{}/{}".format(_DOWNLOAD_BASE_URL, tarball_name),
        sha256 = sha256,
    )

    # The rpmbuild binary resolves its config paths (lib/rpm/rpmrc, etc.)
    # relative to its own location via /proc/self/exe. The tarball extracts
    # to: bin/rpmbuild, lib/rpm/*, share/misc/magic.mgc
    rpmbuild_path = str(rctx.path("bin/rpmbuild"))

    # RPM 6 requires at least one .attr file in the fileattrs directory.
    # Provide a minimal one so file processing doesn't fail.
    rctx.file("lib/rpm/fileattrs/none.attr", "")

    rctx.file(
        "BUILD.bazel",
        """
load("@toolchains_rpmbuild_prebuilt//private:declare_toolchain.bzl", "declare_rpmbuild_toolchain")

declare_rpmbuild_toolchain(
    name = "{name}",
    rpmbuild_path = "{rpmbuild_path}",
    version = "{version}",
    cpu = "{cpu}",
    visibility = ["//visibility:public"],
)
""".lstrip().format(
            name = rctx.original_name,
            rpmbuild_path = rpmbuild_path,
            version = patch_version,
            cpu = arch,
        ),
    )

prebuilt_rpmbuild_toolchain = repository_rule(
    implementation = _prebuilt_rpmbuild_toolchain,
    attrs = {
        "arch": attr.string(
            doc = "Target CPU architecture (e.g. \"x86_64\", \"aarch64\"). Defaults to the host architecture if not specified. Set this when the remote execution platform differs from the host.",
        ),
        "version": attr.string(
            default = "6.0",
            doc = "RPM major.minor version to download (e.g. \"6.0\", \"4.20\"). The latest patch release is used automatically. Can be overridden with --repo_env={name}_version=<major.minor>.",
        ),
    },
)

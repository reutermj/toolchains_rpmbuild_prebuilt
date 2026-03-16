"""Repository rule that downloads and declares a prebuilt rpmbuild toolchain."""

_DOWNLOAD_BASE_URL = "https://github.com/reutermj/toolchains_rpmbuild_prebuilt/releases/download/binaries"

_ARCH_MAP = {
    "amd64": "x86_64",
    "x86_64": "x86_64",
    "aarch64": "aarch64",
    "arm64": "aarch64",
}

_TARBALL_TO_SHA256 = {
    "rpmbuild-x86_64-linux-6.0.1-20260316.tar.xz": "f43a61a2611d04446b3be35f4a6bb23af0dc08176ed2e8a6c22c722c26aee3f3",
    "rpmbuild-aarch64-linux-6.0.1-20260316.tar.xz": "6e020c25b40b8223edd3b1ffc789f63f914de028db5a99bd9fe4948ea55d92b8",
    "rpmbuild-x86_64-linux-4.20.1-20260316.tar.xz": "b118700fbf88a1671d6d14810517b4bb4e26c23ad1cd5ff5f4a018e1e0a6de5a",
    "rpmbuild-aarch64-linux-4.20.1-20260316.tar.xz": "92132a21c062d9333f369096dfa04a7bd002f51fd810eeea6fad9137e6b34bc6",
    "rpmbuild-x86_64-linux-4.19.1.1-20260316.tar.xz": "41eafd9eb05ff597ae867ea265d03ba04127bb1e078dbcd0f35d781f283bd8de",
    "rpmbuild-aarch64-linux-4.19.1.1-20260316.tar.xz": "6da65afc33107569f86c898f7274bab1336eabae7f3c91c26f9ddbdc862f2966",
}

# Maps major.minor version to the latest supported patch version and build date.
_VERSION_MAP = {
    "6.0": ("6.0.1", "20260316"),
    "4.20": ("4.20.1", "20260316"),
    "4.19": ("4.19.1.1", "20260316"),
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

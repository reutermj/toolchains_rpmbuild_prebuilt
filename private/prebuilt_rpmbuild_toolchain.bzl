"""Repository rule that downloads and declares a prebuilt rpmbuild toolchain."""

_DOWNLOAD_BASE_URL = "https://github.com/reutermj/toolchains_rpmbuild_prebuilt/releases/download/binaries"
_ATTESTATION_REPO = "reutermj/toolchains_rpmbuild_prebuilt"

# Minimum gh CLI version that supports `gh attestation verify`.
_MIN_GH_VERSION = (2, 49, 0)

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

def _parse_gh_version(version_string):
    """Parses a 'gh version X.Y.Z (date)' string into a (major, minor, patch) tuple."""
    for line in version_string.split("\n"):
        line = line.strip()
        if line.startswith("gh version "):
            parts = line.split(" ")[2].split(".")
            if len(parts) >= 3:
                return (int(parts[0]), int(parts[1]), int(parts[2]))
    return None

def _format_error(rule_name, message):
    """Formats an error message with a header and footer banner."""
    return """
---------------===============[[ Begin toolchains_rpmbuild_prebuilt error ]]===============---------------
{}
- install it from https://cli.github.com/, or
- to skip verification, set verify_provenance = False on the {} rule.
---------------===============[[  End toolchains_rpmbuild_prebuilt error  ]]===============---------------
""".format(message, rule_name)

def _verify_provenance(rctx, tarball_path):
    """Verifies SLSA provenance for a downloaded tarball using gh attestation verify."""
    gh = rctx.which("gh")
    if not gh:
        fail(_format_error(rctx.original_name, "SLSA provenance verification requires the GitHub CLI (gh) but it was not found on PATH."))

    result = rctx.execute([gh, "version"])
    if result.return_code != 0:
        fail("Failed to run 'gh version': {}".format(result.stderr))

    version = _parse_gh_version(result.stdout)
    if version == None:
        fail("Could not parse gh CLI version from: {}".format(result.stdout))
    if version < _MIN_GH_VERSION:
        fail(_format_error(
            rctx.original_name,
            "gh CLI version {}.{}.{} is too old for attestation verification (need >= {}.{}.{}).".format(
                version[0],
                version[1],
                version[2],
                _MIN_GH_VERSION[0],
                _MIN_GH_VERSION[1],
                _MIN_GH_VERSION[2],
            ),
        ))

    result = rctx.execute([
        gh,
        "attestation",
        "verify",
        tarball_path,
        "--repo",
        _ATTESTATION_REPO,
    ])
    if result.return_code != 0:
        fail(_format_error(
            rctx.original_name,
            "SLSA provenance verification failed for {}:\n{}\n{}".format(
                tarball_path,
                result.stdout,
                result.stderr,
            ),
        ))

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

    tarball_path = rctx.path(tarball_name)
    rctx.download(
        url = "{}/{}".format(_DOWNLOAD_BASE_URL, tarball_name),
        output = tarball_path,
        sha256 = sha256,
    )

    if rctx.attr.verify_provenance:
        _verify_provenance(rctx, tarball_path)

    rctx.extract(tarball_path)
    rctx.delete(tarball_path)

    # RPM 6 requires at least one .attr file in the fileattrs directory.
    # Provide a minimal one so file processing doesn't fail.
    rctx.file("lib/rpm/fileattrs/none.attr", "")

    rctx.file(
        "BUILD.bazel",
        """
load("@toolchains_rpmbuild_prebuilt//private:declare_toolchain.bzl", "declare_rpmbuild_toolchain")

declare_rpmbuild_toolchain(
    name = "{name}",
    version = "{version}",
    data = glob(["**"]),
    cpu = "{cpu}",
    visibility = ["//visibility:public"],
)
""".lstrip().format(
            name = rctx.original_name,
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
        "verify_provenance": attr.bool(
            default = True,
            doc = "Verify SLSA build provenance of the downloaded tarball using the GitHub CLI (gh). Requires gh >= 2.49.0 on PATH. Set to False to skip verification.",
        ),
        "version": attr.string(
            default = "6.0",
            doc = "RPM major.minor version to download (e.g. \"6.0\", \"4.20\"). The latest patch release is used automatically. Can be overridden with --repo_env={name}_version=<major.minor>.",
        ),
    },
)

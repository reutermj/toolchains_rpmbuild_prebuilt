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
}

_RELEASE_TO_DATE = {
    "6.0.1": "20260314",
}

def _rpmbuild_repo(rctx):
    arch = _ARCH_MAP.get(rctx.os.arch, None)
    if arch == None:
        fail("Unsupported host architecture: {}".format(rctx.os.arch))

    version = rctx.attr.version
    date = _RELEASE_TO_DATE.get(version, None)
    if date == None:
        fail("Unsupported rpmbuild version: {}. Supported: {}".format(
            version,
            ", ".join(_RELEASE_TO_DATE.keys()),
        ))

    tarball_name = "rpmbuild-{}-linux-{}-{}.tar.xz".format(arch, version, date)
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

    rctx.template(
        "BUILD.bazel",
        Label("//private:BUILD.bazel.tpl"),
        substitutions = {
            "{rpmbuild_path}": rpmbuild_path,
            "{version}": version,
            "{cpu}": arch,
        },
    )

rpmbuild_repo = repository_rule(
    implementation = _rpmbuild_repo,
    attrs = {
        "version": attr.string(
            default = "6.0.1",
            doc = "RPM version to download.",
        ),
    },
)

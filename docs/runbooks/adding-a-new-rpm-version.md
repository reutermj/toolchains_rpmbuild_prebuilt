# Adding a New RPM Version

This runbook documents the end-to-end process for adding support for a new RPM
version to the prebuilt rpmbuild toolchain.

## Prerequisites

- Write access to this repository
- `gh` CLI authenticated with permissions to trigger workflows and upload
  release assets
- The RPM version you want to add (e.g. `4.20.1`, `4.19.1.1`, `6.0.1`)

## 1. Create the source tarball

The build workflows download RPM source from the `binaries` GitHub release.
Check if the source tarball already exists:

```bash
gh release view binaries --json assets -q '.assets[].name' | grep "rpm-"
```

If the tarball for your version is missing, trigger the source tarball creation
workflow to download from upstream, repackage, attest, and upload it:

```bash
gh workflow run "Create Source Tarballs" --ref main \
    -f component=rpm -f version=<VERSION>
```

Wait for the workflow to complete, then verify the tarball was uploaded:

```bash
gh run list --workflow="Create Source Tarballs" --limit 2
gh release view binaries --json assets -q '.assets[].name' | grep "rpm-<VERSION>"
```

## 2. Review existing patches

Read through the patch documentation in `patches/<MAJOR.MINOR>/` for the
closest existing version to understand what issues each patch fixes:

```
.github/workflows/build_rpmbuild/patches/
├── 4.19/
│   ├── relocatable-configdir.md # Makes RPM_CONFIGDIR resolve via /proc/self/exe
│   ├── relocatable-configdir.patch
│   ├── relocatable-sysconfdir.md # Makes SYSCONFDIR resolve via /proc/self/exe
│   ├── relocatable-sysconfdir.patch
│   ├── static-linking.md        # Switches libraries to static, links rpmbuild statically
│   └── static-linking.patch
├── 4.20/
│   ├── fix-compiler-flag-check.md  # Fixes CMake cache bug in compiler flag detection
│   ├── fix-compiler-flag-check.patch
│   ├── no-buildsubdir.md        # Removes per-package build subdirectory
│   ├── no-buildsubdir.patch
│   ├── no-rm-builddir.md        # Prevents rm -rf of build directory
│   ├── no-rm-builddir.patch
│   ├── relocatable-configdir.md # Makes RPM_CONFIGDIR resolve via /proc/self/exe
│   ├── relocatable-configdir.patch
│   ├── relocatable-sysconfdir.md # Makes SYSCONFDIR resolve via /proc/self/exe
│   ├── relocatable-sysconfdir.patch
│   ├── static-linking.md        # Switches libraries to static, links rpmbuild statically
│   └── static-linking.patch
└── 6.0/
    └── ...
```

### Understanding each patch

| Patch | Why it exists | Introduced in |
|-------|---------------|---------------|
| `no-buildsubdir` | RPM 4.20+ creates `BUILD/<Name>-<Version>-build/` subdirectories. `rules_pkg` populates `BUILD/` directly, so the subdirectory causes `%install` to fail with "file not found". | RPM 4.20.0 |
| `no-rm-builddir` | RPM 4.20+ runs `rm -rf` on the build directory before `%prep`. Since `rules_pkg` pre-populates `BUILD/` before calling rpmbuild, this wipes all the files. | RPM 4.20.0 |
| `relocatable-configdir` | `RPM_CONFIGDIR` is a compile-time absolute path (e.g. `/tmp/prefix/lib/rpm`). A prebuilt binary extracted to a different location can't find its config files. The patch resolves the path relative to the binary via `/proc/self/exe`. | All versions |
| `relocatable-sysconfdir` | `SYSCONFDIR` is a compile-time string literal used in C string concatenation (e.g. `SYSCONFDIR "/rpmrc"`). Same relocatability issue as configdir, but requires replacing each usage site individually because `#define`ing SYSCONFDIR to a function breaks string literal concatenation. | All versions |
| `static-linking` | Produces a self-contained static binary for remote execution environments. Changes `SHARED` to `STATIC` in CMakeLists.txt, removes soversion properties, removes export targets, adds `-static` link flag. | All versions |
| `fix-compiler-flag-check` | CMake reuses a cached variable name when testing multiple compiler flags, causing untested flags (e.g. `-fhardened`) to be added. The patch uses unique variable names per flag. | RPM 4.20.0 |

### Determining which patches apply

- **RPM < 4.20**: `no-buildsubdir`, `no-rm-builddir`, and
  `fix-compiler-flag-check` are NOT needed
- **RPM >= 4.20**: All patches are needed (including `fix-compiler-flag-check`
  for the `-fhardened` flag issue)
- **All versions**: `relocatable-configdir`, `relocatable-sysconfdir`, and
  `static-linking` are always needed for prebuilt distribution

## 3. Create patches for the new version

Create a new patch directory using the major.minor version:

```bash
mkdir -p .github/workflows/build_rpmbuild/patches/<MAJOR.MINOR>
```

### Download and inspect the source

```bash
# Download the source to inspect
wget https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-<VERSION>-release.tar.gz
tar xzf rpm-<VERSION>-release.tar.gz -C /tmp/rpm-<VERSION>-source/
```

### Key files to inspect

For each patch, find the corresponding code in the new version:

| Patch | File in 6.x | File in 4.20.x | What to look for |
|-------|-------------|----------------|------------------|
| `no-buildsubdir` | `build/parsePreamble.cc` | `build/parsePreamble.c` | `spec->buildDir` assignment with `%{NAME}-%{VERSION}-build` |
| `no-rm-builddir` | `build/build.cc` | `build/build.c` | `doBuildDir()` function with `%{__rm} -rf` |
| `relocatable-configdir` | `rpmio/rpmfileutil.cc` | `rpmio/rpmfileutil.c` | `rpmConfigDir()` / `setConfigDir()` using `RPM_CONFIGDIR` |
| `relocatable-sysconfdir` | `lib/rpmrc.cc` | `lib/rpmrc.c` | All uses of `SYSCONFDIR` as string literal concatenation |
| `static-linking` | Various `CMakeLists.txt` | Same | `add_library(libXXX SHARED)`, soversion properties, export targets |

### Important: C vs C++ differences

RPM 6.x uses `.cc` (C++) files while 4.20.x uses `.c` (C) files. The patches
need adaptation:

- **C++ (6.x)**: Uses `std::string`, structured bindings (`auto [ign, doDir]`),
  `macros().expand({...})`
- **C (4.20.x)**: Uses `char *`, `rpmExpand(...)`, `xstrdup()`, `rasprintf()`

The `relocatable-configdir` patch differs most between versions:
- 6.x patches a `rpmConfDir` struct constructor (C++ class)
- 4.20.x patches the `setConfigDir()` C function

### Generate patches

Make changes to a copy of the source, then diff against the pristine copy:

```bash
cp -r /tmp/rpm-<VERSION>-source /tmp/rpm-<VERSION>-pristine

# Make your changes to /tmp/rpm-<VERSION>-source/...

# Generate each patch
diff -ruN --label a/<file> --label b/<file> \
    /tmp/rpm-<VERSION>-pristine/<file> \
    /tmp/rpm-<VERSION>-source/<file> \
    > patches/<MAJOR.MINOR>/<patch-name>.patch
```

### Verify patches apply cleanly

```bash
cp -r /tmp/rpm-<VERSION>-pristine /tmp/rpm-<VERSION>-test
for p in .github/workflows/build_rpmbuild/patches/<MAJOR.MINOR>/*.patch; do
    echo "Applying $(basename $p)..."
    patch -d /tmp/rpm-<VERSION>-test -p1 < "$p"
done
```

## 4. Write patch documentation

Each patch needs a corresponding `.md` file in the same directory. Use the
existing docs as templates. Each doc should include:

- **File(s) modified** — with the correct extension for the version
- **Problem** — what behavior exists in upstream RPM and why it breaks
  `rules_pkg` or prebuilt distribution
- **Code snippets** — with GitHub permalink URLs to the exact commit for the
  RPM version (use the release tag commit hash, not `HEAD`)
- **Cross-references** — link to the equivalent code in other RPM versions
  (4.19.x for pre-buildsubdir context, 4.20.x vs 6.x for C vs C++ differences)
- **`rules_pkg` references** — link to the `make_rpm.py` / `rpm_pfg.bzl` code
  that is affected
- **Fix** — what the patch changes and why

### Finding the commit hash for permalink URLs

```bash
# Look up the tagged commit:
git ls-remote https://github.com/rpm-software-management/rpm.git refs/tags/rpm-<VERSION>-release

# Known commits:
# RPM 4.19.1.1: bc2f9b7e797e8f519872ad154bd7a32ee8f411ad
# RPM 4.20.1:   c8dc5ea575a2e9c1488036d12f4b75f6a5a49120
# RPM 6.0.1:    58a917a6c5e24e9e8a01976c17d2eee06249b9b6

# URL format:
# https://github.com/rpm-software-management/rpm/blob/<COMMIT>/<file>#L<line>
```

## 5. Check CMake configure compatibility

Compare the CMake options in the new RPM version against the flags in
`step-04_build_rpm`:

```bash
grep "^option(" /tmp/rpm-<VERSION>-source/CMakeLists.txt
```

Verify that all `-D` flags used in `step-04_build_rpm` exist in the new
version. The build script has a `case` statement on `RPM_MAJOR_MINOR` that
sets version-specific CMake flags. Key differences between versions:

| Flag | RPM < 4.20 | RPM >= 4.20 |
|------|-----------|-------------|
| `WITH_INTERNAL_OPENPGP` | Use `ON` for OpenSSL-based crypto | Removed (use `WITH_SEQUOIA` instead) |
| `WITH_SEQUOIA` | Does not exist | Use `OFF` (we use OpenSSL) |
| `WITH_ARCHIVE` | Exists (default ON), set `OFF` | Removed |
| `WITH_ICONV` | Does not exist as option | Use `OFF` |
| `WITH_LIBDW` | Detected automatically | Use `OFF` |
| `WITH_LIBELF` | Detected automatically | Use `OFF` |
| `WITH_DOXYGEN` | Detected automatically | Use `OFF` |

If the new version changes which options exist, add a new case to the
`VERSION_FLAGS` block in `step-04_build_rpm`.

## 6. Test the build locally with Docker

**Important:** The source tarball from step 1 must be available on the
`binaries` release before running the Docker build, since the Dockerfile
downloads it.

Verify the full build works locally using the Dockerfile. This catches issues
like missing patches, compiler flag incompatibilities, or CMake configure
errors without burning CI minutes:

```bash
docker build \
    --build-arg GH_TOKEN=$(gh auth token) \
    --build-arg RPM_VERSION=<VERSION> \
    -f .github/workflows/build_rpmbuild/Dockerfile \
    .
```

The Dockerfile runs the complete pipeline: install dependencies, download all
sources, build all static libraries, apply patches, build RPM, collect licenses,
and package the tarball. A successful build means the patches apply cleanly,
CMake configures correctly, and the resulting binary is statically linked and
relocatable.

If the build fails, fix the patches and retry. Common issues:

- **Compiler flag errors** (e.g. `-fhardened`): May need a patch to fix CMake
  flag detection logic (see `fix-compiler-flag-check` in the 4.20 patches)
- **Missing CMake options**: The new RPM version may not have all the `-D` flags
  used in `step-04_build_rpm` — add a case to the `VERSION_FLAGS` block
- **C vs C++ differences**: Ensure patches target the correct file extension
  (`.c` vs `.cc`) and use the correct language idioms

## 7. Add the version to build workflows

The build workflows (`build_rpmbuild_x86_64.yml` and
`build_rpmbuild_aarch64.yml`) use a `workflow_dispatch` input with a choice
list. Add the new version:

```yaml
inputs:
  rpm_version:
    description: "RPM version to build"
    required: true
    type: choice
    options:
      - "6.0.1"
      - "4.20.1"
      - "4.19.1.1"
      - "<NEW_VERSION>"  # Add here
```

## 8. Update `rpmbuild_repo.bzl`

Add a version map entry for the new version. The key is major.minor, the value
is a tuple of (latest patch version, build date):

```python
_VERSION_MAP = {
    "6.0": ("6.0.1", "20260314"),
    "4.20": ("4.20.1", "20260314"),
    "4.19": ("4.19.1.1", "20260314"),
    "<MAJOR.MINOR>": ("<VERSION>", "<YYYYMMDD>"),
}
```

## 9. Commit, push, and trigger builds

```bash
git add -A
git commit -m "Add RPM <VERSION> support with patches"
git push

# Trigger builds for both architectures
gh workflow run "Build rpmbuild (x86_64)" --ref main -f rpm_version=<VERSION>
gh workflow run "Build rpmbuild (aarch64)" --ref main -f rpm_version=<VERSION>
```

## 10. Wait for builds and update sha256 hashes

Monitor the builds:

```bash
gh run list --limit 4
gh run watch <RUN_ID> --exit-status
```

Once both builds complete, download the attested artifacts and get their
sha256 hashes:

```bash
gh release download binaries \
    --pattern "rpmbuild-x86_64-linux-<VERSION>-*.tar.xz" \
    --dir /tmp/new-tarball --clobber
gh release download binaries \
    --pattern "rpmbuild-aarch64-linux-<VERSION>-*.tar.xz" \
    --dir /tmp/new-tarball --clobber

sha256sum /tmp/new-tarball/rpmbuild-*-linux-<VERSION>-*.tar.xz
```

Add the sha256 entries to `rpmbuild_repo.bzl`:

```python
_TARBALL_TO_SHA256 = {
    # ... existing entries ...
    "rpmbuild-x86_64-linux-<VERSION>-<DATE>.tar.xz": "<SHA256>",
    "rpmbuild-aarch64-linux-<VERSION>-<DATE>.tar.xz": "<SHA256>",
}
```

## 11. Verify with Bazel

Test the new version locally:

```bash
# In MODULE.bazel, temporarily change the version:
# prebuilt_rpmbuild_toolchain(name = "rpmbuild", version = "<MAJOR.MINOR>", dev_dependency = True)

bazel clean --expunge
bazel build //tests/rpm:hello-rpm
```

## 12. Final commit

```bash
git add private/rpmbuild_repo.bzl
git commit -m "Add RPM <VERSION> tarball sha256 hashes"
git push
```

The CI test workflows will automatically run on push and verify the build
works on both x86_64 and aarch64.

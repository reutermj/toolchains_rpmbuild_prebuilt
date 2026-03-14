# no-rm-builddir

**File:** `build/build.c`

## Problem

Before running any build phases, RPM executes `%mkbuilddir` via the
`doBuildDir()` function. This function runs a shell sequence that tests if the
build directory exists, fixes its permissions, deletes it entirely, and
recreates it. This behavior was introduced in RPM 4.20.0 alongside the
per-package build subdirectory and is present in both the 4.20.x and 6.x
release lines.

The relevant code in
[RPM 4.20.1 `build.c` (lines 323-331)](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/build/build.c#L323-L331):

```c
static rpmRC doBuildDir(rpmSpec spec, int test, int inPlace, StringBuf *sbp)
{
    char *doDir = rpmExpand("test -d '", spec->buildDir, "' && ",
                   "%{_fixperms} '", spec->buildDir, "'\n",
                   "%{__rm} -rf '", spec->buildDir, "'\n",
                   "%{__mkdir_p} '", spec->buildDir, "'\n",
                   "%{__mkdir_p} '%{specpartsdir}'\n",
                   NULL);
```

The `doBuildDir()` function does not exist in RPM 4.19.x and earlier. In those
versions, the only cleanup happens via `RPMBUILD_RMBUILD` which removes just
the source subdirectory (`%{buildsubdir}`), not a parent wrapper. See
[RPM 4.19.1 `build.c` (lines 196-204)](https://github.com/rpm-software-management/rpm/blob/98b301ebb44fb5cabb56fc24bc3aaa437c47c038/build/build.c#L196-L204).

### Why RPM assumes `rm -rf` is safe

In a traditional RPM workflow, the build directory is populated by the `%prep`
phase — typically via the `%setup` macro, which extracts a source tarball into
`BUILD/`. The `%build` phase compiles in that directory, and `%install` copies
the results into `BUILDROOT/`. Since `%mkbuilddir` runs *before* `%prep`, the
build directory is expected to be empty (or stale from a previous build), so
wiping it is safe.

### Why it breaks `rules_pkg`

`rules_pkg` uses rpmbuild only for the packaging step — it skips `%prep` and
`%build` entirely. Instead,
[`SetupWorkdir()` in `make_rpm.py`](https://github.com/bazelbuild/rules_pkg/blob/e15c3316b04d7f363f04afafd160fa634ce4276c/pkg/make_rpm.py#L255-L260)
populates `BUILD/` directly with pre-built files *before*
[`CallRpmBuild()`](https://github.com/bazelbuild/rules_pkg/blob/e15c3316b04d7f363f04afafd160fa634ce4276c/pkg/make_rpm.py#L438-L442)
invokes `rpmbuild`. When `%mkbuilddir` runs, the `rm -rf` wipes all those
files, causing `%install` to fail because the sources no longer exist.

## Fix

The patch removes the `test -d`, `%{_fixperms}`, and `%{__rm} -rf` lines,
keeping only the `mkdir -p` calls. This ensures the build directory is created
if it doesn't exist, but files already placed there by external tools are
preserved.

This patch works together with `no-buildsubdir.patch` — without both patches,
`rules_pkg`'s `pkg_rpm()` cannot function with RPM 4.20+ or 6.x.

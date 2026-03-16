# relocatable-configdir

**File:** `rpmio/rpmfileutil.c`

## Problem

RPM resolves its configuration directory (`lib/rpm/`) — containing `rpmrc`,
`macros`, `platform`, and `fileattrs/` — via the `rpmConfigDir()` function.
By default, this returns the compile-time constant `RPM_CONFIGDIR`, which is
the absolute path set by `-DCMAKE_INSTALL_PREFIX` during the build
(e.g. `/tmp/prefix/lib/rpm`).

The relevant code in
[RPM 4.19.1.1 `rpmfileutil.c` (lines 482-492)](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/rpmio/rpmfileutil.c#L482-L492):

```c
static void setConfigDir(void)
{
    char *rpmenv = getenv("RPM_CONFIGDIR");
    rpm_config_dir = rpmenv ? xstrdup(rpmenv) : RPM_CONFIGDIR;
}

const char *rpmConfigDir(void)
{
    pthread_once(&configDirSet, setConfigDir);
    return rpm_config_dir;
}
```

The return value of `rpmConfigDir()` is used in `setDefaults()` in `rpmrc.c`
to construct all default config file search paths (`confdir/rpmrc`,
`confdir/macros`, `confdir/platform/...`, etc.). When `confdir` resolves to a
hardcoded build-time path like `/tmp/prefix/lib/rpm`, none of these files can
be found. The binary only works when installed to the exact prefix it was
compiled with. For a prebuilt toolchain distributed as a tarball and extracted
to an arbitrary location by Bazel, the binary cannot find its configuration
files.

This function is identical to the one in
[RPM 4.20.1](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/rpmio/rpmfileutil.c#L484-L494),
and the patch is functionally the same as the 4.20 version.

## Fix

The patch replaces the `setConfigDir()` function to resolve the configuration
directory relative to the binary's own location at runtime. It reads
`/proc/self/exe` to find the binary's absolute path, then walks up the
directory tree looking for a `BUILD.bazel` file — a marker for the root of a
Bazel runfiles tree. Once found, it uses that directory as the base and appends
`/lib/rpm`:

```c
static void setConfigDir(void)
{
    char *rpmenv = getenv("RPM_CONFIGDIR");
    if (rpmenv) {
        rpm_config_dir = xstrdup(rpmenv);
    } else {
        char _exe[4096] = {};
        ssize_t _len = readlink("/proc/self/exe", _exe, sizeof(_exe) - 1);
        if (_len > 0) {
            _exe[_len] = '\0';
            char *_dir = strdup(_exe);
            int _found = 0;
            char *_sep;
            while ((_sep = strrchr(_dir, '/')) != NULL && _sep != _dir) {
                *_sep = '\0';
                char _marker[4096];
                snprintf(_marker, sizeof(_marker), "%s/BUILD.bazel", _dir);
                struct stat _st;
                if (stat(_marker, &_st) == 0) {
                    rasprintf((char **)&rpm_config_dir, "%s/lib/rpm", _dir);
                    _found = 1;
                    break;
                }
            }
            if (!_found)
                rpm_config_dir = RPM_CONFIGDIR;
            free(_dir);
        } else {
            rpm_config_dir = RPM_CONFIGDIR;
        }
    }
}
```

For example, if the binary is at `/some/path/bin/rpmbuild` and
`/some/path/BUILD.bazel` exists, `confdir` resolves to `/some/path/lib/rpm`,
and the search paths become `/some/path/lib/rpm/rpmrc`,
`/some/path/lib/rpm/macros`, etc.

The `RPM_CONFIGDIR` environment variable is still respected as an override, and
the compile-time `RPM_CONFIGDIR` constant is used as a final fallback if
`/proc/self/exe` cannot be read.

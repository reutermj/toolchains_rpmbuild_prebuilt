# relocatable-configdir

**File:** `rpmio/rpmfileutil.c`

## Problem

RPM resolves its configuration directory (`lib/rpm/`) — containing `rpmrc`,
`macros`, `platform`, and `fileattrs/` — via the `rpmConfigDir()` function.
By default, this returns the compile-time constant `RPM_CONFIGDIR`, which is
the absolute path set by `-DCMAKE_INSTALL_PREFIX` during the build
(e.g. `/tmp/prefix/lib/rpm`).

The relevant code in
[RPM 4.20.1 `rpmfileutil.c` (lines 484-494)](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/rpmio/rpmfileutil.c#L484-L494):

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

## Fix

The patch replaces the `setConfigDir()` function to resolve the configuration
directory relative to the binary's own location at runtime using
`/proc/self/exe`:

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
            /* strip "bin/rpmbuild" -> two path components */
            char *_s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            _s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            char *_buf = NULL;
            rasprintf(&_buf, "%s/lib/rpm", _exe);
            rpm_config_dir = _buf;
        } else {
            rpm_config_dir = RPM_CONFIGDIR;
        }
    }
}
```

For example, if the binary is at `/some/path/bin/rpmbuild`, `confdir` resolves
to `/some/path/lib/rpm`, and the search paths become
`/some/path/lib/rpm/rpmrc`, `/some/path/lib/rpm/macros`, etc.

The `RPM_CONFIGDIR` environment variable is still respected as an override, and
the compile-time `RPM_CONFIGDIR` constant is used as a final fallback if
`/proc/self/exe` cannot be read.

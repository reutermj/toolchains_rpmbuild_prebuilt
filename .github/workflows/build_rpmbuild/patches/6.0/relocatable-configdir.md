# relocatable-configdir

**File:** `rpmio/rpmfileutil.cc`

## Problem

RPM resolves its configuration directory (`lib/rpm/`) — containing `rpmrc`,
`macros`, `platform`, and `fileattrs/` — via the `rpmConfigDir()` function.
By default, this returns the compile-time constant `RPM_CONFIGDIR`, which is
the absolute path set by `-DCMAKE_INSTALL_PREFIX` during the build
(e.g. `/tmp/prefix/lib/rpm`).

The relevant code in
[RPM 6.0.1 `rpmfileutil.cc` (lines 434-447)](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/rpmio/rpmfileutil.cc#L434-L447):

```cpp
struct rpmConfDir {
    std::string path;
    rpmConfDir() {
        char *rpmenv = getenv("RPM_CONFIGDIR");
        path = rpmenv ? rpmenv : RPM_CONFIGDIR;
    };
};
```

Note: RPM 4.20.1 uses a different implementation with a static variable and
`setConfigDir()` helper (see
[`rpmfileutil.c` (lines 484-494)](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/rpmio/rpmfileutil.c#L484-L494)),
but the underlying issue is the same — a hardcoded compile-time path.

The return value of `rpmConfigDir()` is used in
[`setDefaults()` in `rpmrc.cc` (line 1347)](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc#L1341-L1388)
to construct all default config file search paths:

```cpp
const char *confdir = rpmConfigDir();

defrcfiles = rstrscat(NULL, confdir, "/rpmrc", ":",
                      confdir, "/" RPM_VENDOR "/rpmrc", ":",
                      SYSCONFDIR "/rpmrc", ":",
                      userrc, NULL);

macrofiles = rstrscat(NULL, confdir, "/macros", ":",
                      confdir, "/macros.d/macros.*", ":",
                      confdir, "/platform/%{_target}/macros", ":",
                      confdir, "/fileattrs/*.attr", ":",
                      confdir, "/" RPM_VENDOR "/macros", ":",
                      ...);
```

When `confdir` resolves to a hardcoded build-time path like
`/tmp/prefix/lib/rpm`, none of these files can be found. The binary only works
when installed to the exact prefix it was compiled with. For a prebuilt
toolchain distributed as a tarball and extracted to an arbitrary location by
Bazel, the binary cannot find its configuration files.

## Fix

The patch replaces the `rpmConfDir` constructor to resolve the configuration
directory relative to the binary's own location at runtime. It reads
`/proc/self/exe` to find the binary's absolute path, then walks up the
directory tree looking for a `BUILD.bazel` file — a marker for the root of a
Bazel runfiles tree. Once found, it uses that directory as the base and appends
`/lib/rpm`:

```cpp
rpmConfDir() {
    char *rpmenv = getenv("RPM_CONFIGDIR");
    if (rpmenv) {
        path = rpmenv;
    } else {
        char _exe[4096] = {};
        ssize_t _len = readlink("/proc/self/exe", _exe, sizeof(_exe) - 1);
        if (_len > 0) {
            _exe[_len] = '\0';
            std::string _dir(_exe);
            bool _found = false;
            while (!_dir.empty() && _dir != "/") {
                auto _pos = _dir.rfind('/');
                if (_pos == std::string::npos) break;
                _dir.erase(_pos);
                struct stat _st;
                std::string _marker = _dir + "/BUILD.bazel";
                if (stat(_marker.c_str(), &_st) == 0) {
                    path = _dir + "/lib/rpm";
                    _found = true;
                    break;
                }
            }
            if (!_found) {
                path = RPM_CONFIGDIR;
            }
        } else {
            path = RPM_CONFIGDIR;
        }
    }
};
```

For example, if the binary is at `/some/path/bin/rpmbuild` and
`/some/path/BUILD.bazel` exists, `confdir` resolves to `/some/path/lib/rpm`,
and the search paths become `/some/path/lib/rpm/rpmrc`,
`/some/path/lib/rpm/macros`, etc.

The `RPM_CONFIGDIR` environment variable is still respected as an override, and
the compile-time `RPM_CONFIGDIR` constant is used as a final fallback if
`/proc/self/exe` cannot be read.

# relocatable-sysconfdir

**File:** `lib/rpmrc.c`

## Problem

RPM uses the `SYSCONFDIR` macro (set at compile time to `<prefix>/etc`) to
locate system-wide configuration files. The macro is used as a C string literal
concatenation throughout
[`rpmrc.c`](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/lib/rpmrc.c)
to construct default config file search paths.

For the rpmrc search path
([line 462](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/lib/rpmrc.c#L462)):

```c
defrcfiles = rstrscat(NULL, confdir, "/rpmrc", ":",
                      confdir, "/" RPM_VENDOR "/rpmrc", ":",
                      SYSCONFDIR "/rpmrc", ":",
                      "~/.rpmrc", NULL);
```

For the macro file search path
([lines 473-475](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/lib/rpmrc.c#L473-L475)):

```c
macrofiles = rstrscat(NULL, confdir, "/macros", ":",
                      ...
                      SYSCONFDIR "/rpm/macros.*", ":",
                      SYSCONFDIR "/rpm/macros", ":",
                      SYSCONFDIR "/rpm/%{_target}/macros", ":",
                      "~/.rpmmacros", NULL);
```

And for the platform detection file
([line 1120](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/lib/rpmrc.c#L1120)):

```c
const char * const platform_path = SYSCONFDIR "/rpm/platform";
```

This is one more usage site than
[RPM 4.20.1](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c#L1147),
which also has `platform_path`, and the
[4.20 version of this patch](../4.20/relocatable-sysconfdir.md) patches that
same set of sites.

Because `SYSCONFDIR` is a compile-time string literal (e.g. `/tmp/prefix/etc`),
all of these paths are hardcoded absolute paths baked in during the build. When
the binary is distributed as a prebuilt toolchain and extracted to an arbitrary
location, `SYSCONFDIR` points to a path that does not exist, causing RPM to fail
to load its configuration.

## Fix

The patch inserts a helper function `_relocSysconfdir()` after the
[`#include "debug.h"` line](https://github.com/rpm-software-management/rpm/blob/bc2f9b7e797e8f519872ad154bd7a32ee8f411ad/lib/rpmrc.c#L41)
that resolves `<prefix>/etc` relative to the binary's location at runtime. It
reads `/proc/self/exe` to find the binary's absolute path, then walks up the
directory tree looking for a `BUILD.bazel` file — a marker for the root of a
Bazel runfiles tree. Once found, it uses that directory as the base and appends
`/etc`:

```c
static const char *_relocSysconfdir(const char *suffix) {
    static char *_prefix = NULL;
    static char _buf[8192];
    if (!_prefix) {
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
                    _prefix = (char *)malloc(strlen(_dir) + 5);
                    sprintf(_prefix, "%s/etc", _dir);
                    _found = 1;
                    break;
                }
            }
            if (!_found)
                _prefix = SYSCONFDIR;
            free(_dir);
        } else {
            _prefix = SYSCONFDIR;
        }
    }
    snprintf(_buf, sizeof(_buf), "%s%s", _prefix, suffix ? suffix : "");
    return _buf;
}
```

Because `SYSCONFDIR` is used in C string literal concatenation (e.g.
`SYSCONFDIR "/rpmrc"`), it cannot simply be `#define`'d to a function call —
that would break compilation. Instead, the patch replaces each usage site
individually:

```c
// Before:
SYSCONFDIR "/rpmrc"
// After:
_relocSysconfdir("/rpmrc")
```

The prefix is computed once on first call and cached in a static pointer. The
compile-time `SYSCONFDIR` value is used as a fallback if `/proc/self/exe`
cannot be read.

This patch works together with `relocatable-configdir.patch` to make the
rpmbuild binary fully relocatable — no hardcoded paths from the build
environment are used at runtime.

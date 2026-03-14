# relocatable-sysconfdir

**File:** `lib/rpmrc.c`

## Problem

RPM uses the `SYSCONFDIR` macro (set at compile time to `<prefix>/etc`) to
locate system-wide configuration files. The macro is used as a C string literal
concatenation throughout
[`rpmrc.c`](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c)
to construct default config file search paths.

For the rpmrc search path
([line 488](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c#L488)):

```c
defrcfiles = rstrscat(NULL, confdir, "/rpmrc", ":",
                      confdir, "/" RPM_VENDOR "/rpmrc", ":",
                      SYSCONFDIR "/rpmrc", ":",
                      userrc, NULL);
```

For the macro file search path
([lines 499-501](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c#L499-L501)):

```c
macrofiles = rstrscat(NULL, confdir, "/macros", ":",
                      ...
                      SYSCONFDIR "/rpm/macros.*", ":",
                      SYSCONFDIR "/rpm/macros", ":",
                      SYSCONFDIR "/rpm/%{_target}/macros", ":",
                      usermacros, NULL);
```

And for the platform detection file
([line 1147](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c#L1147)):

```c
static const char * const platform_path = SYSCONFDIR "/rpm/platform";
```

Because `SYSCONFDIR` is a compile-time string literal (e.g. `/tmp/prefix/etc`),
all of these paths are hardcoded absolute paths baked in during the build. When
the binary is distributed as a prebuilt toolchain and extracted to an arbitrary
location, `SYSCONFDIR` points to a path that does not exist, causing RPM to fail
to load its configuration.

## Fix

The patch inserts a helper function `_relocSysconfdir()` after the
[`#include "debug.h"` line](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c#L41)
that resolves `<prefix>/etc` relative to the binary's location at runtime using
`/proc/self/exe`:

```c
static const char *_relocSysconfdir(const char *suffix) {
    static char *_prefix = NULL;
    static char _buf[8192];
    if (!_prefix) {
        char _exe[4096] = {};
        ssize_t _len = readlink("/proc/self/exe", _exe, sizeof(_exe) - 1);
        if (_len > 0) {
            _exe[_len] = '\0';
            char *_s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            _s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            strcat(_exe, "/etc");
            _prefix = strdup(_exe);
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

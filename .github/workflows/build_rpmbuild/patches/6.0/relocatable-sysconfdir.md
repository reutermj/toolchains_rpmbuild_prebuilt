# relocatable-sysconfdir

**File:** `lib/rpmrc.cc`

## Problem

RPM uses the `SYSCONFDIR` macro (set at compile time to `<prefix>/etc`) to
locate system-wide configuration files. The macro is used as a C string literal
concatenation throughout
[`rpmrc.cc`](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc)
(and similarly in
[RPM 4.20.1 `rpmrc.c`](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/lib/rpmrc.c))
to construct default config file search paths.

For the rpmrc search path
([line 393](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc#L390-L395)):

```cpp
defrcfiles = rstrscat(NULL, confdir, "/rpmrc", ":",
                      confdir, "/" RPM_VENDOR "/rpmrc", ":",
                      SYSCONFDIR "/rpmrc", ":",
                      userrc, NULL);
```

For the macro file search path
([lines 404-406](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc#L398-L408)):

```cpp
macrofiles = rstrscat(NULL, confdir, "/macros", ":",
                      confdir, "/macros.d/macros.*", ":",
                      confdir, "/platform/%{_target}/macros", ":",
                      confdir, "/fileattrs/*.attr", ":",
                      confdir, "/" RPM_VENDOR "/macros", ":",
                      SYSCONFDIR "/rpm/macros.*", ":",
                      SYSCONFDIR "/rpm/macros", ":",
                      SYSCONFDIR "/rpm/%{_target}/macros", ":",
                      usermacros, NULL);
```

And for the platform detection file
([line 1053](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc#L1053)):

```cpp
const char * const platform_path = SYSCONFDIR "/rpm/platform";
```

Because `SYSCONFDIR` is a compile-time string literal (e.g. `/tmp/prefix/etc`),
all of these paths are hardcoded absolute paths baked in during the build. When
the binary is distributed as a prebuilt toolchain and extracted to an arbitrary
location, `SYSCONFDIR` points to a path that does not exist, causing RPM to fail
to load its configuration.

## Fix

The patch inserts a helper function `_relocSysconfdir()` after the
[`#include "debug.h"` line](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/rpmrc.cc#L46)
that resolves `<prefix>/etc` relative to the binary's location at runtime using
`/proc/self/exe`:

```cpp
static std::string _relocSysconfdir(const char *suffix = "") {
    static std::string _prefix;
    if (_prefix.empty()) {
        char _exe[4096] = {};
        ssize_t _len = readlink("/proc/self/exe", _exe, sizeof(_exe) - 1);
        if (_len > 0) {
            _exe[_len] = '\0';
            // strip "bin/rpmbuild" -> two path components
            char *_s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            _s = strrchr(_exe, '/');
            if (_s) *_s = '\0';
            _prefix = std::string(_exe) + "/etc";
        } else {
            _prefix = SYSCONFDIR;
        }
    }
    return _prefix + suffix;
}
```

Because `SYSCONFDIR` is used in C string literal concatenation (e.g.
`SYSCONFDIR "/rpmrc"`), it cannot simply be `#define`'d to a function call —
that would break compilation. Instead, the patch replaces each usage site
individually:

```cpp
// Before:
SYSCONFDIR "/rpmrc"
// After:
_relocSysconfdir("/rpmrc").c_str()
```

The prefix is computed once on first call and cached in a static string. The
compile-time `SYSCONFDIR` value is used as a fallback if `/proc/self/exe`
cannot be read.

This patch works together with `relocatable-configdir.patch` to make the
rpmbuild binary fully relocatable — no hardcoded paths from the build
environment are used at runtime.

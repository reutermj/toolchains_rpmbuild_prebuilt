# fix-compiler-flag-check

**File:** `CMakeLists.txt`

## Problem

RPM 4.20.1's top-level `CMakeLists.txt` has a bug in its compiler flag
detection loop
([lines 418-424](https://github.com/rpm-software-management/rpm/blob/c8dc5ea575a2e9c1488036d12f4b75f6a5a49120/CMakeLists.txt#L418-L424)):

```cmake
foreach (flag -fno-strict-overflow -fno-delete-null-pointer-checks -fhardened)
	check_c_compiler_flag(${flag} found)
	if (found)
		add_compile_options(${flag})
	endif()
	unset(found)
endforeach()
```

All three iterations reuse the same CMake cache variable name `found`. Once
`check_c_compiler_flag` caches a result under `found`, subsequent calls return
the cached value instead of actually testing the next flag. On `ubuntu-latest`,
`-fno-strict-overflow` succeeds and sets `found=TRUE` in the cache. The
`unset(found)` only clears the local variable, not the cache entry, so
`-fhardened` is added without being tested — causing a compilation failure
because `gcc` on the CI runner does not support `-fhardened`.

This was fixed in RPM 6.0.1
([`CMakeLists.txt` lines 435-440](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/CMakeLists.txt#L435-L440))
by using a unique variable name per flag: `compiler-supports${flag}`.

## Fix

The patch adopts the RPM 6.0.1 approach — each flag gets its own result
variable (`compiler-supports${flag}`), ensuring each flag is independently
tested before being added.

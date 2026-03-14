# static-linking

**Files:** `rpmio/CMakeLists.txt`, `lib/CMakeLists.txt`, `build/CMakeLists.txt`,
`sign/CMakeLists.txt`, `tools/CMakeLists.txt`, `CMakeLists.txt`

## Problem

This project distributes a prebuilt `rpmbuild` binary intended for use in
Bazel remote execution environments, where builds run on arbitrary worker
machines with minimal, unpredictable tooling installed. A fully static binary
eliminates any dependency on the host's shared libraries — there is nothing to
`LD_LIBRARY_PATH` to, no `.so` version mismatches to debug, and no need to
coordinate library installation across a fleet of workers. The binary is
self-contained: copy it anywhere and it runs.

RPM's build system produces shared libraries (`librpmio.so`, `librpm.so`,
`librpmbuild.so`, `librpmsign.so`) and dynamically links its executables
against them, which does not meet this requirement.

RPM's CMake files declare each internal library as `SHARED`:

- [`rpmio/CMakeLists.txt` line 1](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/rpmio/CMakeLists.txt#L1):
  `add_library(librpmio SHARED)`
- [`lib/CMakeLists.txt` line 1](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/lib/CMakeLists.txt#L1):
  `add_library(librpm SHARED)`
- [`build/CMakeLists.txt` line 1](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/build/CMakeLists.txt#L1):
  `add_library(librpmbuild SHARED)`
- [`sign/CMakeLists.txt` line 1](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/sign/CMakeLists.txt#L1):
  `add_library(librpmsign SHARED)`

Each library also sets `VERSION` and `SOVERSION` properties for shared library
versioning (e.g.
[`rpmio/CMakeLists.txt` lines 46-49](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/rpmio/CMakeLists.txt#L46-L49)):

```cmake
set_target_properties(librpmio PROPERTIES
	VERSION ${RPM_LIBVERSION}
	SOVERSION ${RPM_SOVERSION}
)
```

The top-level
[`CMakeLists.txt` lines 556-563](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/CMakeLists.txt#L556-L563)
exports these shared library targets for downstream CMake consumers:

```cmake
export(TARGETS librpm librpmio librpmbuild librpmsign
	FILE rpm-targets.cmake
	NAMESPACE rpm::
)
install(EXPORT rpm-targets
	DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${CMAKE_PROJECT_NAME}
	NAMESPACE rpm::
)
```

## Fix

The patch makes four coordinated changes to produce a single, self-contained
static `rpmbuild` binary:

### 1. Switch internal libraries from SHARED to STATIC

Each `add_library(libXXX SHARED)` is changed to `add_library(libXXX STATIC)`.
This causes CMake to produce `.a` archives instead of `.so` shared objects,
and the linker embeds all library code directly into the final executable.

### 2. Remove soversion properties

`VERSION` and `SOVERSION` properties are only meaningful for shared libraries
(they control the `.so.N.N.N` symlink chain). They are removed from all four
library targets since static archives don't use versioned filenames.

### 3. Remove export/install-export targets

The `export(TARGETS ...)` and `install(EXPORT ...)` blocks are removed from
the top-level `CMakeLists.txt`. These generate CMake import files for
downstream projects to `find_package(rpm)` and link against the shared
libraries. With static libraries that are linked into the binary itself, there
are no library targets to export.

### 4. Add static link flags for rpmbuild

The patch appends to
[`tools/CMakeLists.txt`](https://github.com/rpm-software-management/rpm/blob/58a917a6c5e24e9e8a01976c17d2eee06249b9b6/tools/CMakeLists.txt):

```cmake
target_link_options(rpmbuild PRIVATE -static)
target_link_libraries(rpmbuild PRIVATE dl pthread)
```

`-static` tells the linker to produce a fully static ELF binary. `dl` and
`pthread` are added explicitly because glibc's static linking requires them
when the code uses `dlopen` (via libmagic) or pthreads.

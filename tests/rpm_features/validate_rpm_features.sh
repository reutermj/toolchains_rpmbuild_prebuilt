#!/usr/bin/env bash
set -euo pipefail

# Validate an RPM that exercises config files, directories, symlinks,
# and file permissions.

RPM_PATH="${1:?Usage: validate_rpm_features.sh <path-to-rpm>}"

if [[ ! -f "$RPM_PATH" ]]; then
  echo "ERROR: RPM file not found: $RPM_PATH" >&2
  exit 1
fi

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

echo "=== RPM package info ==="
rpm -qip "$RPM_PATH"

echo ""
echo "=== RPM file list (verbose) ==="
rpm -qlvp "$RPM_PATH"

# Capture file list and flags for assertions
FILE_LIST=$(rpm -qlp "$RPM_PATH")
FILE_DUMP=$(rpm -qp --dump "$RPM_PATH")

# --- Config file ---
echo ""
echo "=== Checking config file ==="
if echo "$FILE_LIST" | grep -q '/etc/myapp/myapp.conf'; then
  pass "/etc/myapp/myapp.conf present in package"
else
  fail "/etc/myapp/myapp.conf not found in package"
fi

# Check config flag via queryformat
CONFIG_FLAGS=$(rpm -qp --qf '[%{FILEFLAGS:fflags} %{FILENAMES}\n]' "$RPM_PATH")
if echo "$CONFIG_FLAGS" | grep '/etc/myapp/myapp.conf' | grep -q 'c'; then
  pass "/etc/myapp/myapp.conf marked as config file"
else
  fail "/etc/myapp/myapp.conf not marked as config file"
fi

# --- Directory ownership ---
echo ""
echo "=== Checking directory ownership ==="
DIR_LIST=$(rpm -qlvp "$RPM_PATH")
if echo "$DIR_LIST" | grep -q 'd.*/var/lib/myapp$'; then
  pass "/var/lib/myapp owned as directory"
else
  fail "/var/lib/myapp not owned as directory"
fi

if echo "$DIR_LIST" | grep -q 'd.*/var/log/myapp$'; then
  pass "/var/log/myapp owned as directory"
else
  fail "/var/log/myapp not owned as directory"
fi

# --- Symlink ---
echo ""
echo "=== Checking symlink ==="
if echo "$FILE_LIST" | grep -q '/usr/local/bin/myapp'; then
  pass "/usr/local/bin/myapp present in package"
else
  fail "/usr/local/bin/myapp not found in package"
fi

SYMLINK_TARGET=$(rpm -qp --dump "$RPM_PATH" | awk '$1 == "/usr/local/bin/myapp" {print $NF}')
if [[ "$SYMLINK_TARGET" == "/usr/bin/myapp" ]]; then
  pass "/usr/local/bin/myapp -> /usr/bin/myapp symlink correct"
else
  fail "/usr/local/bin/myapp symlink target is '$SYMLINK_TARGET', expected '/usr/bin/myapp'"
fi

# --- File permissions ---
echo ""
echo "=== Checking file permissions ==="

# Binary should be 0755
BIN_MODE=$(rpm -qp --dump "$RPM_PATH" | awk '$1 == "/usr/bin/myapp" {print $5}')
if [[ "$BIN_MODE" == "0100755" || "$BIN_MODE" == "0755" ]]; then
  pass "/usr/bin/myapp has mode 0755"
else
  fail "/usr/bin/myapp has mode '$BIN_MODE', expected 0755"
fi

# Config should be 0644
CONF_MODE=$(rpm -qp --dump "$RPM_PATH" | awk '$1 == "/etc/myapp/myapp.conf" {print $5}')
if [[ "$CONF_MODE" == "0100644" || "$CONF_MODE" == "0644" ]]; then
  pass "/etc/myapp/myapp.conf has mode 0644"
else
  fail "/etc/myapp/myapp.conf has mode '$CONF_MODE', expected 0644"
fi

# --- Installation test ---
echo ""
echo "=== Installing RPM ==="
INSTALL_DBDIR="$TEST_TMPDIR/rpm-db"
INSTALL_ROOT="$TEST_TMPDIR/rpm-root"
mkdir -p "$INSTALL_DBDIR" "$INSTALL_ROOT"
rpm -ivh --nodeps --dbpath "$INSTALL_DBDIR" --relocate /="$INSTALL_ROOT" --badreloc "$RPM_PATH"

echo ""
echo "=== Verifying installed files ==="
if [[ -f "$INSTALL_ROOT/usr/bin/myapp" ]]; then
  pass "/usr/bin/myapp installed"
else
  fail "/usr/bin/myapp not found after install"
fi

if [[ -f "$INSTALL_ROOT/etc/myapp/myapp.conf" ]]; then
  pass "/etc/myapp/myapp.conf installed"
else
  fail "/etc/myapp/myapp.conf not found after install"
fi

if [[ -d "$INSTALL_ROOT/var/lib/myapp" ]]; then
  pass "/var/lib/myapp directory created"
else
  fail "/var/lib/myapp directory not found after install"
fi

if [[ -d "$INSTALL_ROOT/var/log/myapp" ]]; then
  pass "/var/log/myapp directory created"
else
  fail "/var/log/myapp directory not found after install"
fi

if [[ -L "$INSTALL_ROOT/usr/local/bin/myapp" ]]; then
  INSTALLED_TARGET=$(readlink "$INSTALL_ROOT/usr/local/bin/myapp")
  if [[ "$INSTALLED_TARGET" == "/usr/bin/myapp" ]]; then
    pass "/usr/local/bin/myapp symlink points to /usr/bin/myapp"
  else
    fail "/usr/local/bin/myapp points to '$INSTALLED_TARGET', expected '/usr/bin/myapp'"
  fi
else
  fail "/usr/local/bin/myapp is not a symlink after install"
fi


# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

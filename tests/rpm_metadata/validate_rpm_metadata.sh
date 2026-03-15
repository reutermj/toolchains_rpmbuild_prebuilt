#!/usr/bin/env bash
set -euo pipefail

# Validate an RPM that exercises scriptlets, dependencies, epoch,
# and version/release from files.

RPM_PATH="${1:?Usage: validate_rpm_metadata.sh <path-to-rpm>}"

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

# --- Version and release from files ---
echo ""
echo "=== Checking version/release/epoch ==="

VERSION=$(rpm -qp --qf '%{VERSION}' "$RPM_PATH")
if [[ "$VERSION" == "2.5.0" ]]; then
  pass "version is 2.5.0 (from file)"
else
  fail "version is '$VERSION', expected '2.5.0'"
fi

RELEASE=$(rpm -qp --qf '%{RELEASE}' "$RPM_PATH")
if [[ "$RELEASE" == "3" ]]; then
  pass "release is 3 (from file)"
else
  fail "release is '$RELEASE', expected '3'"
fi

EPOCH=$(rpm -qp --qf '%{EPOCH}' "$RPM_PATH")
if [[ "$EPOCH" == "2" ]]; then
  pass "epoch is 2"
else
  fail "epoch is '$EPOCH', expected '2'"
fi

# --- Scriptlets ---
echo ""
echo "=== Checking scriptlets ==="

SCRIPTS=$(rpm -qp --scripts "$RPM_PATH")

if echo "$SCRIPTS" | grep -q 'pre-install: preparing metadata-test'; then
  pass "pre_scriptlet content present"
else
  fail "pre_scriptlet content not found"
fi

if echo "$SCRIPTS" | grep -q 'post-install: configuring metadata-test'; then
  pass "post_scriptlet content present"
else
  fail "post_scriptlet content not found"
fi

if echo "$SCRIPTS" | grep -q 'pre-uninstall: cleaning metadata-test'; then
  pass "preun_scriptlet content present"
else
  fail "preun_scriptlet content not found"
fi

# --- Dependencies: requires ---
echo ""
echo "=== Checking requires ==="

REQUIRES=$(rpm -qp --requires "$RPM_PATH")

if echo "$REQUIRES" | grep -q 'bash'; then
  pass "requires bash"
else
  fail "requires bash not found"
fi

if echo "$REQUIRES" | grep -q 'coreutils >= 8.0'; then
  pass "requires coreutils >= 8.0"
else
  fail "requires coreutils >= 8.0 not found"
fi

# --- Dependencies: provides ---
echo ""
echo "=== Checking provides ==="

PROVIDES=$(rpm -qp --provides "$RPM_PATH")

if echo "$PROVIDES" | grep -q 'metadata-test-capability'; then
  pass "provides metadata-test-capability"
else
  fail "provides metadata-test-capability not found"
fi

# --- Dependencies: conflicts ---
echo ""
echo "=== Checking conflicts ==="

CONFLICTS=$(rpm -qp --conflicts "$RPM_PATH")

if echo "$CONFLICTS" | grep -q 'conflicting-pkg'; then
  pass "conflicts with conflicting-pkg"
else
  fail "conflicts with conflicting-pkg not found"
fi

# --- Dependencies: obsoletes ---
echo ""
echo "=== Checking obsoletes ==="

OBSOLETES=$(rpm -qp --obsoletes "$RPM_PATH")

if echo "$OBSOLETES" | grep -q 'old-metadata-pkg'; then
  pass "obsoletes old-metadata-pkg"
else
  fail "obsoletes old-metadata-pkg not found"
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

# Validate a built RPM package:
#   1. Check rpm -qip (query info) succeeds
#   2. Check rpm -qlp (list files) shows expected contents
#   3. Install the RPM and verify the installed file exists

RPM_PATH="${1:?Usage: validate_rpm.sh <path-to-rpm>}"

if [[ ! -f "$RPM_PATH" ]]; then
  echo "ERROR: RPM file not found: $RPM_PATH" >&2
  exit 1
fi

echo "=== RPM package info ==="
rpm -qip "$RPM_PATH"

echo ""
echo "=== RPM file list ==="
rpm -qlp "$RPM_PATH"

echo ""
echo "=== Verifying expected file in package ==="
if ! rpm -qlp "$RPM_PATH" | grep -q '/usr/share/hello/hello.txt'; then
  echo "ERROR: /usr/share/hello/hello.txt not found in RPM" >&2
  exit 1
fi
echo "OK: /usr/share/hello/hello.txt found in package"

echo ""
echo "=== Installing RPM ==="
rpm -ivh --nodeps "$RPM_PATH"

echo ""
echo "=== Verifying installed file ==="
if [[ ! -f /usr/share/hello/hello.txt ]]; then
  echo "ERROR: /usr/share/hello/hello.txt not found on disk after install" >&2
  exit 1
fi
echo "OK: /usr/share/hello/hello.txt exists on disk"

echo ""
echo "=== All validations passed ==="

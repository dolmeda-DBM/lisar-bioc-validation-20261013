#!/usr/bin/env bash
# Installation is restricted to the ephemeral public GitHub-hosted macOS runner.
set -euo pipefail
test "$(uname -s)" = Darwin
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
test "${LISAR_REPOSITORY_PRIVATE:-}" = false
test "${GITHUB_REPOSITORY:-}" = dolmeda-DBM/lisar-bioc-validation-20261013
test -n "${LISAR_VALIDATION_ROOT:-}"
test -d "$LISAR_VALIDATION_ROOT"
test "$LISAR_VALIDATION_ROOT" = /private/tmp/l
test ! -L "$LISAR_VALIDATION_ROOT"
test "$(cd "$LISAR_VALIDATION_ROOT" && pwd -P)" = /private/tmp/l
test -f "$LISAR_VALIDATION_ROOT/run-intent.json"
python3 ci/bioc_runner.py verify-root
printf '%s\n' 'XQuartz 2.8.6; official checksum-pinned signed pkg; no GUI start' > "$LISAR_VALIDATION_ROOT/xquartz-intent.txt"
pkg="$LISAR_VALIDATION_ROOT/XQuartz-2.8.6.pkg"
curl --fail --location --show-error --connect-timeout 30 --max-time 600 --output "$pkg" 'https://github.com/XQuartz/XQuartz/releases/download/XQuartz-2.8.6/XQuartz-2.8.6.pkg'
printf '%s  %s\n' '9ac35a505095bfbd3009c3b4772f0c6421e2f79c4210ab908459270d1c447909' "$pkg" | shasum -a 256 -c -
pkgutil --check-signature "$pkg"
sudo installer -pkg "$pkg" -target /
pkgutil --pkg-info org.xquartz.X11
for lib in /opt/X11/lib/libSM.6.dylib /opt/X11/lib/libXrender.1.dylib; do
  test -r "$lib"
  file "$lib"
  otool -L "$lib"
done
printf '%s\n' 'INSTALL_COMPLETED_NOT_RENDERING_PASS' > "$LISAR_VALIDATION_ROOT/xquartz-terminal.txt"

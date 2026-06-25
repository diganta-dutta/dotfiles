#!/usr/bin/env bash
# run-tests.sh — shell-verifiable check for Review Queue, no GUI, no claude.
#   backend smoke test: review-queue --list-json -> [PRItem] decode
#
# (The parser self-test and its fixture were removed after dev — the only
# realistic fixture was a capture of a private PR. The parser was validated
# against it during development; regenerate a sanitized capture if you want the
# regression test back.)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../tests
APP="$(cd "${HERE}/.." && pwd)"                        # .../review-queue-app

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "== backend smoke test (no claude) =="
xcrun --sdk macosx swiftc \
  "${APP}/Sources/Backend.swift" \
  "${APP}/Sources/ReviewStreamParser.swift" \
  "${HERE}/Smoke.swift" \
  -o "${TMP}/smoke"
"${TMP}/smoke"

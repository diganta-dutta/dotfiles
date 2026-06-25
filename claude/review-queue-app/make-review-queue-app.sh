#!/usr/bin/env bash
# make-review-queue-app.sh — (re)build "~/Applications/Review Queue.app".
#
# A menu-bar (LSUIElement) SwiftUI app that is a thin front-end over the
# `review-queue` shell workhorse (in this directory) and the stream parser
# (Sources/ReviewStreamParser.swift). Like Claude Launcher's
# make-launcher-app.sh, this builds the bundle from scratch each run
# (idempotent), copies Claude.app's icon, and registers with Launch Services.
#
# Usage:  ./make-review-queue-app.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../dotfiles/claude/review-queue-app
SRC="${REPO_DIR}/Sources"

APP="${HOME}/Applications/Review Queue.app"
REAL_APP="/Applications/Claude.app"
TARGET="arm64-apple-macos14.0"

echo "Building ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

# --- compile all Swift sources into the bundle executable --------------------
xcrun --sdk macosx swiftc -O \
  -target "${TARGET}" \
  -o "${APP}/Contents/MacOS/ReviewQueue" \
  "${SRC}"/*.swift
echo "  compiled ${SRC}/*.swift -> ReviewQueue"

# --- Contents/Info.plist -----------------------------------------------------
cat > "${APP}/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Review Queue</string>
  <key>CFBundleDisplayName</key>     <string>Review Queue</string>
  <key>CFBundleIdentifier</key>      <string>com.diganta.review-queue</string>
  <key>CFBundleVersion</key>         <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleExecutable</key>      <string>ReviewQueue</string>
  <key>CFBundleIconFile</key>        <string>icon</string>
  <key>LSUIElement</key>             <true/>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

# --- copy Claude's icon so the menu-bar/about tile looks on-brand ------------
icns="$(ls "${REAL_APP}/Contents/Resources/"*.icns 2>/dev/null | head -1 || true)"
if [[ -n "${icns}" ]]; then
  cp "${icns}" "${APP}/Contents/Resources/icon.icns"
  echo "  icon: copied from ${icns##*/}"
else
  echo "  WARN: no .icns found in ${REAL_APP}; app will use a generic icon"
fi

# Refresh Launch Services so Finder & the menu bar pick up the new bundle.
touch "${APP}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "${APP}" >/dev/null 2>&1 || true

echo "Done: ${APP}"
echo "Launch it:  open \"${APP}\""

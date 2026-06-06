#!/usr/bin/env bash
#
# Assemble a self-contained ArchSight.app bundle.
#
# The bundle layout places the Go core and ripgrep beside the app's resources so
# the shipped app runs with no environment configuration:
#
#   dist/ArchSight.app/
#     Contents/
#       Info.plist
#       MacOS/ArchSight              # SwiftUI shell (also a fallback core dir)
#       Resources/ArchSight.icns     # app icon
#       Resources/bin/archsight-core # Go core service
#       Resources/bin/rg             # bundled ripgrep
#
# At run time CoreBinaryLocator finds Resources/bin/archsight-core and the core
# finds Resources/bin/rg via ResolveRipgrepPath, both relative to their own
# location. Development runs instead use scripts/setup.sh + ARCHSIGHT_CORE_PATH.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ArchSight.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
RES_BIN="$CONTENTS/Resources/bin"
APP_VERSION="0.1.0"

log() { printf '== %s\n' "$1"; }

log "Cleaning $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_BIN"

log "Building Go core (release)"
go build -trimpath -o "$RES_BIN/archsight-core" ./core/cmd/archsight-core

log "Building Swift shell (release)"
swift build --package-path "$ROOT_DIR/apps/macos" -c release --product ArchSight
SWIFT_BIN="$(swift build --package-path "$ROOT_DIR/apps/macos" -c release --show-bin-path)"
cp "$SWIFT_BIN/ArchSight" "$MACOS_DIR/ArchSight"

log "Bundling app icon"
"$ROOT_DIR/scripts/generate-app-icon.py"
cp "$ROOT_DIR/apps/macos/Resources/ArchSight.icns" "$RES_DIR/ArchSight.icns"

log "Bundling ripgrep"
if RG_PATH="$(command -v rg 2>/dev/null)"; then
  cp "$RG_PATH" "$RES_BIN/rg"
  printf '   bundled rg from %s\n' "$RG_PATH"
else
  printf '   WARNING: rg not found on PATH; search will require a system rg or ARCHSIGHT_RG_PATH\n'
fi

log "Writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ArchSight</string>
  <key>CFBundleDisplayName</key><string>ArchSight</string>
  <key>CFBundleIdentifier</key><string>com.cmg.archsight</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleVersion</key><string>${APP_VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>????</string>
  <key>CFBundleExecutable</key><string>ArchSight</string>
  <key>CFBundleIconFile</key><string>ArchSight</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

chmod +x "$MACOS_DIR/ArchSight" "$RES_BIN/archsight-core"
[[ -f "$RES_BIN/rg" ]] && chmod +x "$RES_BIN/rg"

log "Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_DIR"

log "Done: $APP_DIR"
printf '   open %s\n' "$APP_DIR"

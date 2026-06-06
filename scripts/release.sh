#!/usr/bin/env bash
#
# Package ArchSight.app into a distributable zip and wire the value into the
# Homebrew cask. Repeatable release chain:
#
#   build-app.sh  ->  ditto zip  ->  sha256  ->  patch Casks/archsight.rb
#
# After this runs, upload the zip to a GitHub Release tagged v<version> and
# push the updated cask to your tap. The exact commands are printed at the end.
#
# Usage:
#   scripts/release.sh             # build, zip, compute sha256, patch the cask
#   scripts/release.sh --no-build  # reuse an existing dist/ArchSight.app
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/ArchSight.app"
CASK_FILE="$ROOT_DIR/Casks/archsight.rb"

log() { printf '== %s\n' "$1"; }

if [[ "${1:-}" != "--no-build" ]]; then
  log "Building app bundle"
  "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "error: $APP_DIR not found (run without --no-build first)" >&2
  exit 1
fi

# Single source of truth for the version: the built bundle's Info.plist.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$APP_DIR/Contents/Info.plist")"
ZIP_NAME="ArchSight-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

log "Packaging $ZIP_NAME"
rm -f "$ZIP_PATH"
# ditto preserves the bundle layout, symlinks, extended attributes, and the
# code signature far more reliably than `zip` for a macOS .app.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
log "sha256 = $SHA256"

if [[ -f "$CASK_FILE" ]]; then
  log "Patching $CASK_FILE (version + sha256)"
  # macOS/BSD sed in-place editing.
  /usr/bin/sed -i '' \
    -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"${SHA256}\"/" \
    "$CASK_FILE"
fi

TAP_REPO="${ARCHSIGHT_TAP_DIR:-$HOME/Dev/homebrew-tap}"

cat <<EOF

== Done. Artifact: $ZIP_PATH

Next steps (manual — these publish to GitHub and your tap):

  1. Create the release and upload the zip:
       gh release create "v${VERSION}" "$ZIP_PATH" \\
         --repo CarlLee1983/ArchSight --title "v${VERSION}" --generate-notes

  2. Copy the patched cask into your tap and push it:
       mkdir -p "$TAP_REPO/Casks"
       cp "$CASK_FILE" "$TAP_REPO/Casks/archsight.rb"
       (cd "$TAP_REPO" && git add Casks/archsight.rb \\
          && git commit -m "archsight ${VERSION}" && git push)

  3. Users install, then clear quarantine once (the app is not notarized;
     Homebrew's --no-quarantine flag was removed, so this is done after):
       brew install --cask CarlLee1983/tap/archsight
       xattr -dr com.apple.quarantine /Applications/ArchSight.app
EOF

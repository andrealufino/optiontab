#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, package and publish a GitHub Release.
#
# Usage:  ./release.sh <version>
# Example: ./release.sh 1.0.0
#
# Requires: Xcode, create-dmg, gh, a notarytool keychain profile.
#   brew install create-dmg gh
#   xcrun notarytool store-credentials "optiontab-notary" \
#       --apple-id "you@example.com" --team-id "EZ9L78NW47" --password "<app-specific-pw>"
#
set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
APP_NAME="OptionTab"
SCHEME="release"
PROJECT="optiontab.xcodeproj"
BUNDLE_ID="com.andrealufino.optiontab"
TEAM_ID="EZ9L78NW47"
SIGN_IDENTITY="Developer ID Application: Andrea Mario Lufino (${TEAM_ID})"
NOTARY_PROFILE="optiontab-notary"
BUILD_DIR="./build"

# ─── Colors ────────────────────────────────────────────────────────────────
C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_RED="\033[1;31m"; C_DIM="\033[2m"; C_OFF="\033[0m"
step() { echo -e "${C_BLUE}▸${C_OFF} $*"; }
ok()   { echo -e "${C_GREEN}✓${C_OFF} $*"; }
die()  { echo -e "${C_RED}✗${C_OFF} $*" >&2; exit 1; }

# ─── Args ──────────────────────────────────────────────────────────────────
[[ $# -eq 1 ]] || die "Usage: $0 <version>   e.g. $0 1.0.0"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be semver X.Y.Z (got: $VERSION)"
TAG="v${VERSION}"

# ─── Prerequisites ─────────────────────────────────────────────────────────
step "Checking prerequisites…"
command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"
command -v create-dmg >/dev/null || die "create-dmg not found (brew install create-dmg)"
command -v gh         >/dev/null || die "gh CLI not found (brew install gh)"
gh auth status >/dev/null 2>&1   || die "gh not authenticated (run: gh auth login)"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' not found. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <…> --team-id $TEAM_ID --password <app-specific-pw>"

security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
  || die "Signing identity not found in keychain: $SIGN_IDENTITY"

[[ -z "$(git status --porcelain)" ]] || die "Git working tree not clean. Commit or stash first."
! git rev-parse "$TAG" >/dev/null 2>&1 || die "Tag $TAG already exists."

COMMIT_SHA="$(git rev-parse HEAD)"
ok "Prerequisites OK — releasing $TAG from $(git rev-parse --short HEAD)"

# ─── Clean & paths ─────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
STAGING_DIR="${BUILD_DIR}/staging"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

# ─── Archive ───────────────────────────────────────────────────────────────
step "Archiving (scheme: $SCHEME)…"
xcodebuild -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  archive
ok "Archive created"

# ─── Export (Developer ID signed, hardened runtime) ────────────────────────
step "Exporting signed .app…"
cat > "${BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -quiet -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR"

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name "*.app" -type d | head -n 1)"
[[ -d "$APP_PATH" ]] || die "Exported .app not found under $EXPORT_DIR"
ok "Exported: $(basename "$APP_PATH")"

# Sanity: confirm Developer ID signature + hardened runtime
codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 \
  || die "Signature verification failed"
CODESIGN_INFO="$(codesign -dv "$APP_PATH" 2>&1)"
echo "$CODESIGN_INFO" | grep -q "flags=.*runtime" \
  || die "Hardened runtime not enabled on exported app"
ok "Signature + hardened runtime verified"

# ─── DMG ───────────────────────────────────────────────────────────────────
step "Building DMG…"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

create-dmg \
  --volname "$APP_NAME" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "$(basename "$APP_PATH")" 160 180 \
  --app-drop-link 380 180 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGING_DIR" >/dev/null
ok "DMG: $DMG_PATH"

# ─── Notarize ──────────────────────────────────────────────────────────────
step "Submitting to Apple notary service (2–5 min)…"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
ok "Notarization accepted"

# ─── Staple ────────────────────────────────────────────────────────────────
step "Stapling ticket…"
xcrun stapler staple "$DMG_PATH" >/dev/null
xcrun stapler validate "$DMG_PATH" >/dev/null
ok "Stapled and validated"

# ─── Tag + push ────────────────────────────────────────────────────────────
step "Tagging $TAG on $(git rev-parse --short "$COMMIT_SHA")…"
git tag -a "$TAG" "$COMMIT_SHA" -m "Release $VERSION"
git push origin "$TAG"
ok "Tag pushed"

# ─── GitHub Release ────────────────────────────────────────────────────────
step "Creating GitHub Release…"
gh release create "$TAG" \
  "$DMG_PATH" \
  --title "$VERSION" \
  --generate-notes
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo
ok "Release published 🎉"
echo -e "${C_DIM}https://github.com/${REPO}/releases/tag/${TAG}${C_OFF}"

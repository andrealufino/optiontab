#!/usr/bin/env bash
#
# release.sh — Build, sign, notarize, package and publish a GitHub Release.
#
# Usage:  ./release.sh
#
# Must be run from the `develop` branch with a clean, up-to-date working tree.
# Reads the version from the VERSION file (semver X.Y.Z), then:
#   1. Validates prerequisites
#   2. Bumps MARKETING_VERSION and CURRENT_PROJECT_VERSION in .pbxproj, commits and pushes to develop
#   3. Merges develop → main (--no-ff), pushes main
#   4. Archives, signs, notarizes, packages to DMG
#   5. Tags the main merge commit, pushes the tag
#   6. Creates the GitHub Release with the DMG attached
#   7. Fast-forward merges main → develop to keep branches in sync, pushes develop
#
# Requires: Xcode, create-dmg, gh, a notarytool keychain profile.
#   brew install create-dmg gh
#   xcrun notarytool store-credentials "optiontab-notary" \
#       --apple-id "you@example.com" --team-id "<your-team-id>" --password "<app-specific-pw>"
#
set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
APP_NAME="OptionTab"
SCHEME="release"
PROJECT="optiontab.xcodeproj"
BUNDLE_ID="com.andrealufino.optiontab"
NOTARY_PROFILE="optiontab-notary"
SIGN_IDENTITY_PREFIX="Developer ID Application:"
BUILD_DIR="./build"
PBXPROJ="${PROJECT}/project.pbxproj"

# ─── Colors ────────────────────────────────────────────────────────────────
C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_RED="\033[1;31m"; C_DIM="\033[2m"; C_OFF="\033[0m"
step() { echo -e "${C_BLUE}▸${C_OFF} $*"; }
ok()   { echo -e "${C_GREEN}✓${C_OFF} $*"; }
die()  { echo -e "${C_RED}✗${C_OFF} $*" >&2; exit 1; }

# ─── Error trap ────────────────────────────────────────────────────────────
# Emits a recovery hint when the script fails after the merge to main is pushed.
MERGE_COMMIT_SHA=""
on_error() {
    local exit_code=$?
    if [[ -n "${MERGE_COMMIT_SHA}" ]]; then
        echo ""
        echo -e "${C_RED}✗${C_OFF} Release aborted after merge to main was already pushed."
        echo -e "${C_DIM}  main and develop are at ${MERGE_COMMIT_SHA:0:7} on origin."
        echo -e "  To recover: investigate the failure, bump VERSION to a new number, rerun release.sh.${C_OFF}"
    fi
    exit $exit_code
}
trap on_error ERR

# ─── Read version from file ────────────────────────────────────────────────
step "Reading version from VERSION file..."
VERSION_FILE="./VERSION"
[[ -f "$VERSION_FILE" ]] || die "VERSION file not found at $VERSION_FILE"
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ -n "$VERSION" ]] || die "VERSION file is empty"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be semver X.Y.Z (got: $VERSION)"
TAG="${VERSION}"
ok "Version: $VERSION (tag: $TAG)"

# ─── Prerequisites ─────────────────────────────────────────────────────────
step "Checking prerequisites..."

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$CURRENT_BRANCH" == "develop" ]] \
  || die "release.sh must be run from develop (current: $CURRENT_BRANCH)"

command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"
command -v create-dmg >/dev/null || die "create-dmg not found (brew install create-dmg)"
command -v gh         >/dev/null || die "gh CLI not found (brew install gh)"
gh auth status >/dev/null 2>&1   || die "gh not authenticated (run: gh auth login)"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notary profile '$NOTARY_PROFILE' not found. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <...> --team-id <...> --password <app-specific-pw>"

security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY_PREFIX" \
  || die "No Developer ID Application signing identity found in keychain. Check Local.xcconfig and your certificate."

[[ -z "$(git status --porcelain)" ]] || die "Git working tree not clean. Commit or stash first."

# Verify develop is in sync with origin
git fetch origin develop main
LOCAL_DEVELOP="$(git rev-parse develop)"
REMOTE_DEVELOP="$(git rev-parse origin/develop)"
[[ "$LOCAL_DEVELOP" == "$REMOTE_DEVELOP" ]] \
  || die "develop is not in sync with origin/develop. Push or pull first."

# Verify origin/main is not ahead of local main
MAIN_BEHIND="$(git rev-list --count main..origin/main)"
[[ "$MAIN_BEHIND" -eq 0 ]] \
  || die "origin/main has $MAIN_BEHIND commit(s) not in local main. Run: git checkout main && git pull"

! git rev-parse "$TAG" >/dev/null 2>&1 || die "Tag $TAG already exists."
ok "Prerequisites OK"

# ─── Bump version in .pbxproj ─────────────────────────────────────────────
step "Bumping version in $PBXPROJ..."

CURRENT_BUILD="$(grep -E 'CURRENT_PROJECT_VERSION = [0-9]+' "$PBXPROJ" | head -1 | grep -oE '[0-9]+')"
[[ -n "$CURRENT_BUILD" ]] || die "Could not read CURRENT_PROJECT_VERSION from $PBXPROJ"
NEW_BUILD=$(( CURRENT_BUILD + 1 ))

sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/g" "$PBXPROJ"

git diff --quiet "$PBXPROJ" && die "VERSION file matches current .pbxproj — nothing to bump. Update VERSION to a new version first."

git add "$PBXPROJ"
git commit -m "chore: bump version to $VERSION ($NEW_BUILD)"
git push origin develop
ok "Bumped to $VERSION (build $NEW_BUILD), pushed to develop"

BUMP_COMMIT_SHA="$(git rev-parse HEAD)"

# ─── Merge develop → main ─────────────────────────────────────────────────
step "Merging develop into main..."
git checkout main
git pull --ff-only origin main
git merge --no-ff develop -m "release: $VERSION"
git push origin main
MERGE_COMMIT_SHA="$(git rev-parse HEAD)"
ok "Merged develop into main (commit ${MERGE_COMMIT_SHA:0:7})"

# ─── Clean & paths ─────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
STAGING_DIR="${BUILD_DIR}/staging"
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

# ─── Archive ───────────────────────────────────────────────────────────────
step "Archiving (scheme: $SCHEME)..."
xcodebuild -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$NEW_BUILD" \
  archive
ok "Archive created"

# ─── Resolve signing identity ─────────────────────────────────────────────
SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep "$SIGN_IDENTITY_PREFIX" | head -1 | sed 's/.*"\(.*\)"/\1/')"
[[ -n "$SIGN_IDENTITY" ]] || die "Could not resolve signing identity"

# ─── Export (Developer ID signed, hardened runtime) ────────────────────────
step "Exporting signed .app..."
TEAM_ID="$(security find-identity -v -p codesigning | grep "$SIGN_IDENTITY_PREFIX" | head -1 | grep -oE '\([A-Z0-9]{10}\)' | tr -d '()')"
[[ -n "$TEAM_ID" ]] || die "Could not extract Team ID from signing identity"

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
step "Building DMG..."
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
step "Submitting to Apple notary service (2-5 min)..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
ok "Notarization accepted"

# ─── Staple ────────────────────────────────────────────────────────────────
step "Stapling ticket..."
xcrun stapler staple "$DMG_PATH" >/dev/null
xcrun stapler validate "$DMG_PATH" >/dev/null
ok "Stapled and validated"

# ─── Tag on main merge commit ─────────────────────────────────────────────
step "Tagging $TAG on main merge commit ${MERGE_COMMIT_SHA:0:7}..."
git tag -a "$TAG" "$MERGE_COMMIT_SHA" -m "Release $VERSION"
git push origin "$TAG"
ok "Tag pushed"

# ─── GitHub Release ────────────────────────────────────────────────────────
step "Creating GitHub Release..."
gh release create "$TAG" \
  "$DMG_PATH" \
  --title "$VERSION" \
  --generate-notes
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo
ok "Release published"
echo -e "${C_DIM}https://github.com/${REPO}/releases/tag/${TAG}${C_OFF}"

# ─── Sync develop with main ────────────────────────────────────────────────
step "Syncing develop with main..."
git checkout develop
git merge --ff-only main
git push origin develop
ok "develop synced with main"

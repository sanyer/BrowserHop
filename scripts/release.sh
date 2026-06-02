#!/bin/bash
set -euo pipefail

# BrowserHop Release Script
# Builds, signs, creates DMG, notarizes, and staples.
#
# Prerequisites:
#   brew install xcodegen
#   gh auth login
#   xcrun notarytool store-credentials "BrowserHop" \
#     --apple-id YOUR_APPLE_ID \
#     --team-id X6URN8G7V8
#
# Usage:
#   ./scripts/release.sh [version]        # build + notarize only
#   ./scripts/release.sh 1.1.0            # build specific version
#   ./scripts/release.sh 1.1.0 --publish  # build + create GitHub release

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BrowserHop"
SCHEME="BrowserHop"
SIGNING_IDENTITY="Developer ID Application: Roman Zhuzha (X6URN8G7V8)"
NOTARY_PROFILE="BrowserHop"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/.build/release"

# --- Helpers ---

info()  { printf "\033[1;34m→\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31m✗\033[0m %s\n" "$1" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

# --- Args ---

PUBLISH=false
VERSION=""
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=true ;;
        *) VERSION="$arg" ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION=$(grep 'MARKETING_VERSION' "$ROOT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
fi
BUILD_NUMBER=$(date +%Y%m%d%H%M)

info "Release: $APP_NAME v$VERSION (build $BUILD_NUMBER)"

# --- Preflight ---

require_command xcodegen
require_command xcodebuild
require_command codesign
require_command hdiutil
require_command xcrun
require_command gh
require_command git-cliff
require_command git-cliff

# Verify signing identity exists
security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY" \
    || fail "Signing identity not found: $SIGNING_IDENTITY"

# --- Clean & Build ---

rm -rf "$DERIVED_DATA" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

info "Generating Xcode project"
(cd "$ROOT_DIR" && xcodegen generate >/dev/null)

info "Building $APP_NAME (Release)"
xcodebuild \
    -project "$ROOT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build \
    -quiet

APP_PATH=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d | head -1)
[[ -d "$APP_PATH" ]] || fail "Build product not found"
ok "Built: $APP_PATH"

# --- Sign ---

info "Signing app bundle"
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ok "Signed and verified"

# --- Create DMG ---

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

info "Creating DMG"
STAGE_DIR="$(mktemp -d)"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null
rm -rf "$STAGE_DIR"

# Sign the DMG too
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
ok "DMG created: $DMG_PATH"

# --- Notarize ---

info "Submitting for notarization (this may take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# --- Staple ---

info "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
ok "Notarization complete"

# --- GitHub Release ---

if [[ "$PUBLISH" == true ]]; then
    info "Creating GitHub release v$VERSION"

    TAG="v$VERSION"

    # Tag if not already tagged
    if ! git rev-parse "$TAG" >/dev/null 2>&1; then
        git tag -a "$TAG" -m "Release $VERSION"
        git push origin "$TAG"
    fi

    # Generate release notes from commits since last tag
    NOTES=$(git-cliff --current --strip header 2>/dev/null || echo "")
    NOTES="${NOTES:-(No conventional commits since last release)}

---
**Install:** Download \`$DMG_NAME\`, open it, drag $APP_NAME to Applications.
Signed with Developer ID · Notarized by Apple"

    gh release create "$TAG" "$DMG_PATH" \
        --title "$APP_NAME $VERSION" \
        --notes "$NOTES" \
        --latest

    ok "GitHub release published: $TAG"
fi

# --- Done ---

echo ""
ok "Release ready: $OUTPUT_DIR/$DMG_NAME"
echo "  Version: $VERSION"
echo "  Build:   $BUILD_NUMBER"
echo "  Size:    $(du -h "$DMG_PATH" | cut -f1)"
[[ "$PUBLISH" == true ]] && echo "  GitHub:  https://github.com/sanyer/BrowserHop/releases/tag/v$VERSION"

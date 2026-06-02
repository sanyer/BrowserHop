#!/bin/bash
set -euo pipefail

# BrowserHop Release Script
# Builds, signs, creates DMG, notarizes, staples, and optionally publishes to GitHub.
#
# Prerequisites:
#   brew install xcodegen git-cliff
#   gh auth login
#   xcrun notarytool store-credentials "BrowserHop" \
#     --apple-id YOUR_APPLE_ID \
#     --team-id X6URN8G7V8
#
# Usage:
#   ./scripts/release.sh patch             # bump 1.0.2 → 1.0.3, build + notarize
#   ./scripts/release.sh minor --publish   # bump 1.0.2 → 1.1.0, build + publish
#   ./scripts/release.sh major --publish   # bump 1.0.2 → 2.0.0, build + publish
#   ./scripts/release.sh 1.2.0 --publish   # set exact version, build + publish
#   ./scripts/release.sh --publish         # use current version, build + publish
#
# Flags:
#   --skip-build      reuse last build (skip xcodebuild)
#   --skip-notarize   skip notarization + stapling
#   --force           allow release from dirty working tree

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BrowserHop"
SCHEME="BrowserHop"
SIGNING_IDENTITY="Developer ID Application: Roman Zhuzha (X6URN8G7V8)"
NOTARY_PROFILE="BrowserHop"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/.build/release"
PROJECT_YML="$ROOT_DIR/project.yml"

# --- Helpers ---

info()  { printf "\033[1;34m→\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31m✗\033[0m %s\n" "$1" >&2; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

# --- Semver helpers ---

read_version() {
    grep 'MARKETING_VERSION' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/'
}

write_version() {
    local new_version="$1"
    sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$new_version\"/" "$PROJECT_YML"
}

bump_version() {
    local current="$1" part="$2"
    local major minor patch
    IFS='.' read -r major minor patch <<< "$current"

    case "$part" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "${major}.$((minor + 1)).0" ;;
        patch) echo "${major}.${minor}.$((patch + 1))" ;;
        *) fail "Invalid bump type: $part (use major, minor, or patch)" ;;
    esac
}

# --- Args ---

PUBLISH=false
SKIP_BUILD=false
SKIP_NOTARIZE=false
FORCE=false
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=true ;;
        --skip-build) SKIP_BUILD=true ;;
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --force) FORCE=true ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

# --- Resolve version ---

CURRENT_VERSION=$(read_version)

if [[ -z "$VERSION_ARG" ]]; then
    VERSION="$CURRENT_VERSION"
elif [[ "$VERSION_ARG" =~ ^(major|minor|patch)$ ]]; then
    VERSION=$(bump_version "$CURRENT_VERSION" "$VERSION_ARG")
    info "Bumping version: $CURRENT_VERSION → $VERSION"
    write_version "$VERSION"
    git add "$PROJECT_YML"
    git commit -m "release: bump version to $VERSION"
elif [[ "$VERSION_ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$VERSION_ARG"
    if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
        info "Setting version: $CURRENT_VERSION → $VERSION"
        write_version "$VERSION"
        git add "$PROJECT_YML"
        git commit -m "release: bump version to $VERSION"
    fi
else
    fail "Invalid version argument: $VERSION_ARG (use major/minor/patch or X.Y.Z)"
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

# Verify signing identity exists
security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY" \
    || fail "Signing identity not found: $SIGNING_IDENTITY"

# Verify working tree is clean (after version bump commit)
if [[ "$FORCE" == false && -n "$(git status --porcelain)" ]]; then
    fail "Working tree not clean. Commit or stash changes, or use --force."
fi

# --- Clean & Build ---

mkdir -p "$OUTPUT_DIR"

if [[ "$SKIP_BUILD" == false ]]; then
    rm -rf "$DERIVED_DATA"

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
else
    info "Skipping build (--skip-build)"
fi

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

if [[ "$SKIP_NOTARIZE" == false ]]; then
    info "Submitting for notarization (this may take a few minutes)"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    info "Stapling notarization ticket"
    xcrun stapler staple "$DMG_PATH"
    ok "Notarization complete"
else
    info "Skipping notarization (--skip-notarize)"
fi

# --- GitHub Release ---

if [[ "$PUBLISH" == true ]]; then
    info "Creating GitHub release v$VERSION"

    TAG="v$VERSION"

    # Push version bump commit if needed
    git push origin main

    # Tag if not already tagged
    if ! git rev-parse "$TAG" >/dev/null 2>&1; then
        git tag -a "$TAG" -m "Release $VERSION"
    fi
    git push origin "$TAG"

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

#!/bin/bash
set -euo pipefail

# =============================================================================
# clipboard-bridge — Build, Sign, Notarize, Release
#
# Steps:
#   1) Build universal binary (arm64 + x86_64)
#   2) Codesign with Developer ID + hardened runtime
#   3) Notarize via notarytool
#   4) Tag + push
#   5) Create GitHub release with binary + install script
#
# Prerequisites:
#   - Developer ID Application certificate in Keychain
#   - .env file with notarization credentials (see ramble/.env)
#   - gh CLI authenticated
#
# Usage:
#   ./scripts/release.sh                    (auto-bumps patch)
#   ./scripts/release.sh --version 1.0.0
#   ./scripts/release.sh --skip-push
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
BINARY_NAME="clipboard-bridge"
SOURCE="$PROJECT_DIR/$BINARY_NAME.m"
RELEASE_REPO="${RELEASE_REPO:-elomid/clipboard-bridge}"
ENV_FILE="${ENV_FILE:-$HOME/Developer/ramble/.env}"

VERSION=""
SKIP_PUSH=0

usage() {
    cat <<EOF
Usage: ./scripts/release.sh [options]

Options:
  --version X.Y.Z    Release version (default: bump patch of latest tag)
  --repo owner/repo  GitHub repo (default: $RELEASE_REPO)
  --env PATH         Path to .env file (default: $ENV_FILE)
  --skip-push        Build + sign locally, don't push or publish
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)  VERSION="${2:-}"; shift 2 ;;
        --repo)     RELEASE_REPO="${2:-}"; shift 2 ;;
        --env)      ENV_FILE="${2:-}"; shift 2 ;;
        --skip-push) SKIP_PUSH=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

# Load .env for notarization credentials
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE" >&2
    echo "Create one with NOTARIZE_KEY_ID, NOTARIZE_ISSUER, NOTARIZE_KEY_PATH" >&2
    exit 1
fi

for var in NOTARIZE_KEY_ID NOTARIZE_ISSUER NOTARIZE_KEY_PATH; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: $var not set in $ENV_FILE" >&2
        exit 1
    fi
done

# Auto-detect version from latest tag
if [[ -z "$VERSION" ]]; then
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    LATEST_TAG="${LATEST_TAG#v}"
    MAJOR="${LATEST_TAG%%.*}"
    REST="${LATEST_TAG#*.}"
    MINOR="${REST%%.*}"
    PATCH="${REST#*.}"
    SUGGESTED="${MAJOR}.${MINOR}.$((PATCH + 1))"

    echo "Latest tag: v${LATEST_TAG}"
    read -rp "Release version [${SUGGESTED}]: " USER_VERSION
    VERSION="${USER_VERSION:-$SUGGESTED}"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Version must be X.Y.Z (got: $VERSION)" >&2
    exit 1
fi

if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "ERROR: Tag v${VERSION} already exists" >&2
    exit 1
fi

# Find signing identity
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [[ -z "$IDENTITY" ]]; then
    echo "ERROR: No 'Developer ID Application' certificate found in Keychain" >&2
    exit 1
fi

TOTAL_STEPS=5
[[ "$SKIP_PUSH" -eq 1 ]] && TOTAL_STEPS=3

echo ""
echo "=== clipboard-bridge release ==="
echo "Version: $VERSION"
echo "Signing: $IDENTITY"
echo "Repo:    $RELEASE_REPO"
echo ""

# -----------------------------------------------------------------------------
# 1. Build universal binary
# -----------------------------------------------------------------------------
echo "[1/${TOTAL_STEPS}] Building universal binary..."

mkdir -p "$BUILD_DIR"
rm -f "$BUILD_DIR/$BINARY_NAME"

clang -O2 -fobjc-arc -framework AppKit \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=11.0 \
    -o "$BUILD_DIR/$BINARY_NAME" \
    "$SOURCE"

file "$BUILD_DIR/$BINARY_NAME"
echo "  Built $BINARY_NAME ($(du -h "$BUILD_DIR/$BINARY_NAME" | cut -f1))"

# -----------------------------------------------------------------------------
# 2. Codesign
# -----------------------------------------------------------------------------
echo ""
echo "[2/${TOTAL_STEPS}] Signing with Developer ID..."

codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" \
    "$BUILD_DIR/$BINARY_NAME"

codesign --verify --strict "$BUILD_DIR/$BINARY_NAME"
echo "  Signature OK"

# -----------------------------------------------------------------------------
# 3. Notarize
# -----------------------------------------------------------------------------
echo ""
echo "[3/${TOTAL_STEPS}] Notarizing..."

NOTARIZE_ZIP="$BUILD_DIR/$BINARY_NAME-notarize.zip"
ditto -c -k "$BUILD_DIR/$BINARY_NAME" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
    --key-id "$NOTARIZE_KEY_ID" \
    --issuer "$NOTARIZE_ISSUER" \
    --key "$NOTARIZE_KEY_PATH" \
    --wait

rm -f "$NOTARIZE_ZIP"

SHA256="$(shasum -a 256 "$BUILD_DIR/$BINARY_NAME" | awk '{print $1}')"
echo "  Notarized"
echo "  SHA-256: $SHA256"

if [[ "$SKIP_PUSH" -eq 1 ]]; then
    echo ""
    echo "=== Release prepared (local only) ==="
    echo "Binary: $BUILD_DIR/$BINARY_NAME"
    echo "SHA-256: $SHA256"
    exit 0
fi

# -----------------------------------------------------------------------------
# 4. Tag + push
# -----------------------------------------------------------------------------
echo ""
echo "[4/${TOTAL_STEPS}] Tagging + pushing..."

git tag -a "v${VERSION}" -m "clipboard-bridge ${VERSION}"
git push origin HEAD
git push origin "v${VERSION}"

# -----------------------------------------------------------------------------
# 5. GitHub release
# -----------------------------------------------------------------------------
echo ""
echo "[5/${TOTAL_STEPS}] Publishing GitHub release..."

NOTES=$(cat <<EOF
## clipboard-bridge ${VERSION}

Signed and notarized universal binary (arm64 + x86_64).

### Install

\`\`\`bash
curl -fsSL https://github.com/${RELEASE_REPO}/releases/latest/download/install.sh | bash
\`\`\`

### Uninstall

\`\`\`bash
curl -fsSL https://github.com/${RELEASE_REPO}/releases/latest/download/install.sh | bash -s -- --uninstall
\`\`\`

**SHA-256:** \`${SHA256}\`
EOF
)

gh release create "v${VERSION}" \
    "$BUILD_DIR/$BINARY_NAME" \
    "$PROJECT_DIR/install.sh" \
    --repo "$RELEASE_REPO" \
    --title "clipboard-bridge ${VERSION}" \
    --notes "$NOTES"

echo ""
echo "=== Release complete ==="
echo "Version:  ${VERSION}"
echo "SHA-256:  ${SHA256}"
echo "Release:  https://github.com/${RELEASE_REPO}/releases/tag/v${VERSION}"

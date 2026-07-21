#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${1:-0.1.0}
BUILD_NUMBER=${2:-1}
SIGNING_IDENTITY=${AVESTACODE_SIGNING_IDENTITY:-Developer ID Application: Avesta Barzegar (7H66Q22DJD)}
NOTARY_PROFILE=${AVESTACODE_NOTARY_PROFILE:-AvestaCodeNotary}
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$ROOT_DIR/.build/release/AvestaCode.app"
ENTITLEMENTS_PATH="$ROOT_DIR/App/AvestaCode.entitlements"
UPLOAD_PATH="$DIST_DIR/AvestaCode-$VERSION-notarization.zip"
NOTARY_RESULT_PATH="$DIST_DIR/AvestaCode-$VERSION-notarization.json"

case "$VERSION" in
  ''|*[!0-9A-Za-z.-]*) echo "invalid version: $VERSION" >&2; exit 2 ;;
esac
case "$BUILD_NUMBER" in
  ''|*[!0-9.]*) echo "invalid build number: $BUILD_NUMBER" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

AVESTACODE_VERSION="$VERSION" \
AVESTACODE_BUILD_NUMBER="$BUILD_NUMBER" \
AVESTACODE_CLEAN_BUILD=1 \
  sh "$ROOT_DIR/Scripts/build-app.sh" release

codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ARCHITECTURES=$(lipo -archs "$APP_PATH/Contents/MacOS/AvestaCode")
if [ "$ARCHITECTURES" = "x86_64 arm64" ] || [ "$ARCHITECTURES" = "arm64 x86_64" ]; then
  PLATFORM=universal
else
  PLATFORM=$(echo "$ARCHITECTURES" | tr ' ' '-')
fi
ARTIFACT_PATH="$DIST_DIR/AvestaCode-$VERSION-macos-$PLATFORM.zip"
CHECKSUM_PATH="$ARTIFACT_PATH.sha256"

rm -f "$UPLOAD_PATH" "$NOTARY_RESULT_PATH" "$ARTIFACT_PATH" "$CHECKSUM_PATH"
ditto -c -k --keepParent "$APP_PATH" "$UPLOAD_PATH"

xcrun notarytool submit "$UPLOAD_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT_PATH"

NOTARY_STATUS=$(plutil -extract status raw -o - "$NOTARY_RESULT_PATH")
if [ "$NOTARY_STATUS" != Accepted ]; then
  echo "notarization failed with status: $NOTARY_STATUS" >&2
  plutil -p "$NOTARY_RESULT_PATH" >&2
  exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ARTIFACT_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ARTIFACT_PATH")" > "$(basename "$CHECKSUM_PATH")")

echo "$ARTIFACT_PATH"
echo "$CHECKSUM_PATH"

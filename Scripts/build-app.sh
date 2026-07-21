#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${1:-release}
VERSION=${AVESTACODE_VERSION:-${2:-0.1.0}}
BUILD_NUMBER=${AVESTACODE_BUILD_NUMBER:-${3:-1}}
APP_NAME=AvestaCode
OUTPUT_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SCRATCH_DIR=

case "$CONFIGURATION" in
  debug|release) ;;
  *) echo "configuration must be debug or release" >&2; exit 2 ;;
esac
case "$VERSION" in
  ''|*[!0-9A-Za-z.-]*) echo "invalid version: $VERSION" >&2; exit 2 ;;
esac
case "$BUILD_NUMBER" in
  ''|*[!0-9.]*) echo "invalid build number: $BUILD_NUMBER" >&2; exit 2 ;;
esac

cleanup() {
  if [ -n "$SCRATCH_DIR" ] && [ -d "$SCRATCH_DIR" ]; then
    rm -rf "$SCRATCH_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

cd "$ROOT_DIR"
if [ "${AVESTACODE_CLEAN_BUILD:-$([ "$CONFIGURATION" = release ] && echo 1 || echo 0)}" = 1 ]; then
  mkdir -p "$ROOT_DIR/.build"
  SCRATCH_DIR=$(mktemp -d "$ROOT_DIR/.build/avestacode-$CONFIGURATION.XXXXXX")
  swift build --scratch-path "$SCRATCH_DIR" -c "$CONFIGURATION"
  BUILD_DIR=$(swift build --scratch-path "$SCRATCH_DIR" -c "$CONFIGURATION" --show-bin-path)
else
  swift build -c "$CONFIGURATION"
  BUILD_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

for bundle in "$BUILD_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  ditto "$bundle" "$RESOURCES_DIR/$(basename "$bundle")"
done

echo "$APP_DIR"

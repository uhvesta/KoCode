#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${1:-release}
APP_NAME=AvestaCode
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>AvestaCode</string>
	<key>CFBundleExecutable</key>
	<string>AvestaCode</string>
	<key>CFBundleIdentifier</key>
	<string>com.avestacode.workbench</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>AvestaCode</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSQuitAlwaysKeepsWindows</key>
	<false/>
</dict>
</plist>
PLIST

if [ -d "$ROOT_DIR/App/Assets.xcassets" ]; then
  cp -R "$ROOT_DIR/App/Assets.xcassets" "$RESOURCES_DIR/Assets.xcassets"
fi

for bundle in "$BUILD_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$RESOURCES_DIR/$(basename "$bundle")"
done

echo "$APP_DIR"

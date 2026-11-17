#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AssetManager"
BUNDLE_ID="dev.wbm.asset-manager"
OUT_DIR="${1:-$HOME/Desktop}"
APP_PATH="$OUT_DIR/$APP_NAME.app"

echo "==> Building release binary"
cd "$PROJECT_DIR"
swift build -c release

BUILT="$PROJECT_DIR/.build/release/$APP_NAME"
if [[ ! -f "$BUILT" ]]; then
  echo "Build failed: $BUILT not found"
  exit 1
fi

echo "==> Assembling $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BUILT" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Asset Manager</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

cat > "$APP_PATH/Contents/PkgInfo" <<EOF
APPL????
EOF

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "Built: $APP_PATH"
echo "Double-click it in Finder to launch. Look for 'AM' in your menu bar."

#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/bin"
LA_DIR="$HOME/Library/LaunchAgents"
LA_LABEL="dev.wbm.asset-manager"
LA_PATH="$LA_DIR/$LA_LABEL.plist"
BIN_PATH="$BIN_DIR/asset-manager"

echo "==> Building release binary"
cd "$PROJECT_DIR"
swift build -c release

BUILT="$PROJECT_DIR/.build/release/AssetManager"
if [[ ! -f "$BUILT" ]]; then
  echo "Build failed: $BUILT not found"
  exit 1
fi

echo "==> Installing binary to $BIN_PATH"
mkdir -p "$BIN_DIR"
cp "$BUILT" "$BIN_PATH"
chmod +x "$BIN_PATH"

echo "==> Ad-hoc signing"
codesign --force --sign - "$BIN_PATH"

echo "==> Stopping any running instance"
launchctl bootout "gui/$(id -u)/$LA_LABEL" 2>/dev/null || true
pkill -f "$BIN_PATH" 2>/dev/null || true

echo "==> Writing LaunchAgent at $LA_PATH"
mkdir -p "$LA_DIR"
cat > "$LA_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LA_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_PATH</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key><false/>
    <key>Crashed</key><true/>
  </dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/tmp/asset-manager.log</string>
  <key>StandardErrorPath</key><string>/tmp/asset-manager.err</string>
</dict>
</plist>
EOF

echo "==> Loading LaunchAgent"
launchctl bootstrap "gui/$(id -u)" "$LA_PATH"

echo ""
echo "Installed. Look for 'AM' in your menu bar."
echo "Logs: /tmp/asset-manager.log /tmp/asset-manager.err"
echo "Uninstall: bash $PROJECT_DIR/scripts/uninstall.sh"

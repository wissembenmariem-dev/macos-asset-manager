#!/bin/bash
set -u
BIN_PATH="$HOME/bin/asset-manager"
LA_LABEL="dev.wbm.asset-manager"
LA_PATH="$HOME/Library/LaunchAgents/$LA_LABEL.plist"

echo "==> Stopping LaunchAgent"
launchctl bootout "gui/$(id -u)/$LA_LABEL" 2>/dev/null || true
pkill -f "$BIN_PATH" 2>/dev/null || true

echo "==> Removing LaunchAgent plist"
rm -f "$LA_PATH"

echo "==> Removing binary"
rm -f "$BIN_PATH"

echo "==> Done. Config and rules left at ~/.config/asset-manager/ (delete manually if unwanted)."

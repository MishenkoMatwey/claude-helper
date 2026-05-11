#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="ClaudeAgentsMonitor"
BUNDLE="dist/${APP_NAME}.app"

echo "▶ swift build -c release"
swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
echo "▶ assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN_PATH}/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# App icon
if [ -f "Resources/AppIcon.icns" ]; then
  cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
fi

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>com.mishchenko.claudeagents</string>
  <key>CFBundleName</key><string>Claude Agents</string>
  <key>CFBundleDisplayName</key><string>Claude Agents</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

echo "✓ built: ${BUNDLE}"
echo "  drag it to /Applications, or open with: open '${BUNDLE}'"

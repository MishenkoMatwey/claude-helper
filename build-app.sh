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

# SwiftPM resource bundle — Bundle.module reads from ${APP_NAME}_${APP_NAME}.bundle
# placed alongside the executable inside the .app.
RES_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${BIN_PATH}/${RES_BUNDLE}" ]; then
  cp -R "${BIN_PATH}/${RES_BUNDLE}" "${BUNDLE}/Contents/MacOS/${RES_BUNDLE}"
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

# SwiftPM resource bundle (${APP_NAME}_${APP_NAME}.bundle) is flat by default —
# codesign rejects that layout. Re-wrap it into the standard Contents/Info.plist + Contents/Resources/ form.
RES_BUNDLE_PATH="${BUNDLE}/Contents/MacOS/${RES_BUNDLE}"
if [ -d "${RES_BUNDLE_PATH}" ] && [ ! -f "${RES_BUNDLE_PATH}/Contents/Info.plist" ]; then
  mkdir -p "${RES_BUNDLE_PATH}/Contents/Resources"
  # Move ALL top-level entries (files AND directories, e.g. .copy'd AgentScripts)
  # into Contents/Resources/ — leaving anything in the bundle root fails codesign.
  find "${RES_BUNDLE_PATH}" -maxdepth 1 -mindepth 1 ! -name Contents \
    -exec mv {} "${RES_BUNDLE_PATH}/Contents/Resources/" \;
  cat > "${RES_BUNDLE_PATH}/Contents/Info.plist" <<RESPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.mishchenko.claudeagents.resources</string>
  <key>CFBundleName</key><string>${APP_NAME}_${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
RESPLIST
fi

# Sign with stable self-signed certificate so macOS TCC permissions (Desktop/Documents/...)
# persist across rebuilds. Falls back to ad-hoc if the cert isn't in keychain.
CERT_NAME="ClaudeAgentsMonitor Self-Signed"
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "▶ codesign --sign '$CERT_NAME'"
  # Sign nested resource bundle first (so the outer --deep pass doesn't choke on its previous adhoc sig).
  [ -d "${RES_BUNDLE_PATH}" ] && codesign --force --options runtime --sign "$CERT_NAME" "${RES_BUNDLE_PATH}" 2>&1 | sed 's/^/  /'
  codesign --force --deep --options runtime \
    --sign "$CERT_NAME" \
    --identifier "com.mishchenko.claudeagents" \
    "${BUNDLE}" 2>&1 | sed 's/^/  /'
  codesign -dv "${BUNDLE}" 2>&1 | grep -E 'Signature|Authority|Identifier' | sed 's/^/  /'
else
  echo "⚠ No trusted self-signed certificate '$CERT_NAME' as a code-signing identity."
  echo "  TCC prompts will repeat on every rebuild. To fix once:"
  echo "  1) Open Keychain Access"
  echo "  2) Certificate Assistant → Create a Certificate…"
  echo "  3) Name: $CERT_NAME · Identity Type: Self-Signed Root · Certificate Type: Code Signing"
  codesign --force --deep --sign - "${BUNDLE}" 2>&1 | sed 's/^/  /'
fi

echo "✓ built: ${BUNDLE}"
echo "  drag it to /Applications, or open with: open '${BUNDLE}'"

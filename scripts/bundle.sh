#!/usr/bin/env bash
# Wraps the SwiftPM release binary in a menu-bar-only .app (no Dock icon) at build/Shepherd.app.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-release}"
version="$(git -C "$root" describe --tags --always 2>/dev/null || echo 0.0.0)"

swift build --package-path "$root" -c "$config"
bin="$(swift build --package-path "$root" -c "$config" --show-bin-path)/Shepherd"

app="$root/build/Shepherd.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Shepherd"

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.flexipie.shepherd</string>
  <key>CFBundleName</key><string>Shepherd</string>
  <key>CFBundleExecutable</key><string>Shepherd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS runs it locally; real signing and notarising come later.
codesign --force --sign - "$app" >/dev/null
echo "$app"

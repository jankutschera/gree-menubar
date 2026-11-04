#!/bin/zsh
# Builds AC.app (menu bar only, no Dock icon) into ./build and ad-hoc signs it.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/AC.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AC "$APP/Contents/MacOS/AC"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.truebrewbirdie.ac</string>
  <key>CFBundleName</key><string>AC</string>
  <key>CFBundleExecutable</key><string>AC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Talks to your Gree air conditioner on the local network.</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"

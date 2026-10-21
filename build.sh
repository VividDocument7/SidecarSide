#!/bin/zsh
# Builds SidecarSide.app (menu bar only, no Dock icon) into ./build
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SidecarSide.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# The newest Command Line Tools SDK can be ahead of the installed swiftc; use the newest SDK it accepts.
SDK=""
for s in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk | sort -rV); do
  if echo 'import AppKit' | swiftc -sdk "$s" -typecheck - 2>/dev/null; then SDK=$s; break; fi
done
[[ -n "$SDK" ]] || { echo "No SDK compatible with $(swiftc --version 2>&1 | head -1)"; exit 1; }
echo "Using SDK $SDK"

swiftc -O -sdk "$SDK" -target arm64-apple-macosx13.0 Sources/*.swift -o "$APP/Contents/MacOS/SidecarSide-arm64"
swiftc -O -sdk "$SDK" -target x86_64-apple-macosx13.0 Sources/*.swift -o "$APP/Contents/MacOS/SidecarSide-x86_64"

# App icon, drawn from SF Symbols
mkdir -p "$APP/Contents/Resources" build/tmp
swiftc -sdk "$SDK" tools/make-icon.swift -o build/tmp/make-icon
rm -rf build/tmp/AppIcon.iconset
build/tmp/make-icon build/tmp/AppIcon.iconset
iconutil -c icns build/tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
lipo -create "$APP"/Contents/MacOS/SidecarSide-{arm64,x86_64} -output "$APP/Contents/MacOS/SidecarSide"
rm "$APP"/Contents/MacOS/SidecarSide-{arm64,x86_64}

VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SidecarSide</string>
    <key>CFBundleDisplayName</key><string>SidecarSide</string>
    <key>CFBundleIdentifier</key><string>com.oliverp.SidecarSide</string>
    <key>CFBundleExecutable</key><string>SidecarSide</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) $(git config user.name)</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
rm -rf build/tmp

# Zip for GitHub releases (ditto keeps the bundle's metadata and signature intact)
ditto -c -k --keepParent "$APP" "build/SidecarSide-$VERSION.zip"
echo "Built $APP (v$VERSION, build $BUILD) and build/SidecarSide-$VERSION.zip"

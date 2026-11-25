#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/WindowShift.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
cp Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
xcrun swiftc -O -warnings-as-errors -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path build/module-cache Sources/*.swift -o "$app/Contents/MacOS/WindowShift"
xattr -cr "$app"
codesign --force --sign - "$app"

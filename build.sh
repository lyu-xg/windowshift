#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/WindowShift.app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/windowshift-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
staged="$stage/WindowShift.app"
mkdir -p "$staged/Contents/MacOS" "$staged/Contents/Resources" build/module-cache
cp Info.plist "$staged/Contents/Info.plist"
cp LICENSE "$staged/Contents/Resources/LICENSE"
xcrun swiftc -O -warnings-as-errors -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path build/module-cache Sources/*.swift -o "$staged/Contents/MacOS/WindowShift"
xattr -cr "$staged"
codesign --force --sign - "$staged"
rm -rf "$app"
mkdir -p build
ditto --norsrc "$staged" "$app"

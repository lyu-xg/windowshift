#!/bin/sh
set -eu
cd "$(dirname "$0")"

universal=0
if [ "${1:-}" = "--universal" ]; then
    universal=1
fi

app="build/WindowShift.app"
stage="$(mktemp -d "${TMPDIR:-/tmp}/windowshift-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
staged="$stage/WindowShift.app"
mkdir -p "$staged/Contents/MacOS" "$staged/Contents/Resources" build/module-cache
cp Info.plist "$staged/Contents/Info.plist"
cp LICENSE "$staged/Contents/Resources/LICENSE"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$staged/Contents/Resources/AppIcon.icns"
fi

compile_arch() {
    arch="$1"
    out="$2"
    xcrun swiftc -O -warnings-as-errors -parse-as-library \
        -target "${arch}-apple-macosx13.0" \
        -module-cache-path build/module-cache \
        Sources/*.swift -o "$out"
}

if [ "$universal" -eq 1 ]; then
    compile_arch arm64 "$stage/WindowShift-arm64"
    compile_arch x86_64 "$stage/WindowShift-x86_64"
    lipo -create -output "$staged/Contents/MacOS/WindowShift" \
        "$stage/WindowShift-arm64" "$stage/WindowShift-x86_64"
else
    compile_arch "$(uname -m)" "$staged/Contents/MacOS/WindowShift"
fi

xattr -cr "$staged"
identity="${SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$staged"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$staged"
fi

rm -rf "$app"
mkdir -p build
ditto --norsrc "$staged" "$app"

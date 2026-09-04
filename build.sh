#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) "Desmos Desktop.app" next to this script,
# then zips it for distribution.  Requires Xcode Command Line Tools (xcode-select --install).
set -e
cd "$(dirname "$0")"

APP="Desmos Desktop.app"
ZIP="DesmosDesktop-mac.zip"
MIN=13.0

rm -rf "$APP" "$ZIP" build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  echo "Compiling $arch…"
  swiftc -O -target "$arch-apple-macos$MIN" \
    -framework Cocoa -framework WebKit -framework Carbon -framework ServiceManagement \
    Sources/main.swift -o "build/DesmosDesktop-$arch"
done
lipo -create build/DesmosDesktop-arm64 build/DesmosDesktop-x86_64 -output "$APP/Contents/MacOS/DesmosDesktop"

cp Info.plist "$APP/Contents/"
cp Resources/calculator.html Resources/AppIcon.icns "$APP/Contents/Resources/"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature: keeps macOS from treating the binary as damaged.  (Not notarized —
# see README for the one-time "Open Anyway" step users need.)
codesign --force --deep --sign - "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
rm -rf build
echo "Built: $PWD/$APP"
echo "Zip:   $PWD/$ZIP  ($(du -h "$ZIP" | cut -f1))"
lipo -info "$APP/Contents/MacOS/DesmosDesktop"

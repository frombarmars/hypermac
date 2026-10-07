#!/bin/bash
# Build HyperMac.app (universal: Apple Silicon + Intel).
#   scripts/build.sh            → build/HyperMac.app
#   scripts/build.sh --install  → also copy to ~/Applications and launch
#   scripts/build.sh --zip      → also create build/HyperMac.zip for a release
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUM="${BUILD_NUM:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/HyperMac.app"
SDK_MIN="14.0"

command -v swiftc >/dev/null || { echo "swiftc not found — run: xcode-select --install"; exit 1; }

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
for arch in arm64 x86_64; do
  echo "→ compiling $arch"
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos$SDK_MIN" \
    Sources/HyperMac/*.swift -o "build/obj/HyperMac-$arch"
done
lipo -create build/obj/HyperMac-arm64 build/obj/HyperMac-x86_64 -output "$APP/Contents/MacOS/HyperMac"

cp Resources/AppIcon.icns Resources/LogoMark.png Resources/MenuIcon.png Resources/MenuIcon@2x.png "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUM/" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null   # ad-hoc signature
echo "✓ built $APP ($VERSION)"

for arg in "$@"; do
  case "$arg" in
    --zip)
      (cd build && rm -f HyperMac.zip && ditto -c -k --keepParent HyperMac.app HyperMac.zip)
      echo "✓ build/HyperMac.zip" ;;
    --install)
      pkill -x HyperMac 2>/dev/null || true
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/HyperMac.app"
      cp -R "$APP" "$HOME/Applications/"
      open "$HOME/Applications/HyperMac.app"
      echo "✓ installed to ~/Applications/HyperMac.app" ;;
  esac
done

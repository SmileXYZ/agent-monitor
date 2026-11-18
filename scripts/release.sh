#!/bin/zsh
# Builds a release DMG: build/release/AgentMonitor-<version>.dmg (ad-hoc signed, not notarized).
# Usage: scripts/release.sh            → version from project.yml
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml)
OUT="build/release"
DERIVED="build/dd-release"
APP="$DERIVED/Build/Products/Release/AgentMonitor.app"
DMG="$OUT/AgentMonitor-$VERSION.dmg"

rm -rf "$OUT" "$DERIVED"
mkdir -p "$OUT/stage"

print -P "%B→ Building $VERSION…%b"
xcodebuild -project AgentMonitor.xcodeproj -scheme AgentMonitor -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="-" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" build -quiet

codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/AgentMonitor"

print -P "%B→ Packing $DMG%b"
cp -R "$APP" "$OUT/stage/"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -volname "Agent Monitor" -srcfolder "$OUT/stage" -ov -format UDZO "$DMG" -quiet
rm -rf "$OUT/stage"

print "✓ $DMG"
shasum -a 256 "$DMG"

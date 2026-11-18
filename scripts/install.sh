#!/bin/zsh
# Builds Agent Monitor from source, installs it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="AgentMonitor.app"
DEST="/Applications/$APP_NAME"
DERIVED="build/dd"

bold() { print -P "%B$1%b"; }

if ! xcodebuild -version >/dev/null 2>&1; then
  print "✗ Xcode is required (WidgetKit extensions can't be built with Command Line Tools alone)."
  print "  Install Xcode from the App Store, open it once, then run:"
  print "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

# Regenerate the project if XcodeGen is available (the committed .xcodeproj works without it).
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
fi

bold "→ Building…"
xcodebuild -project AgentMonitor.xcodeproj -scheme AgentMonitor -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY="-" build -quiet

bold "→ Installing to $DEST"
pkill -x AgentMonitor 2>/dev/null || true
rm -rf "$DEST"
cp -R "$DERIVED/Build/Products/Release/$APP_NAME" "$DEST"

bold "→ Launching"
open "$DEST"

print ""
print "✓ Done. Agent Monitor lives in your menu bar."
print "  Add the widget: right-click the desktop → Edit Widgets → search “Agent Monitor”."
print "  Tip: enable “Launch at Login” in the menu bar icon so the widget keeps updating."

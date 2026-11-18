#!/bin/zsh
# Renders docs/hero.png and docs/waiting.png from the real widget views (Shared + Widget/WidgetViews.swift).
set -e
cd "$(dirname "$0")/.."
mkdir -p build docs
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14 \
  Shared/Model.swift Shared/Sessions.swift Widget/WidgetViews.swift tools/previews/main.swift \
  -o build/render-previews
build/render-previews docs

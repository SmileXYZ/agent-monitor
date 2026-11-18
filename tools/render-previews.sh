#!/bin/zsh
# Renders docs/hero.png, docs/waiting.png and docs/demo.gif from the real widget views (Shared + Widget/WidgetViews.swift).
set -e
cd "$(dirname "$0")/.."
mkdir -p build docs
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14 \
  Shared/Model.swift Shared/Sessions.swift Widget/WidgetViews.swift Widget/RefreshIntent.swift tools/previews/main.swift \
  -o build/render-previews
build/render-previews docs

# demo.gif from the rendered frames (needs ffmpeg: brew install ffmpeg)
ffmpeg -loglevel error -y -framerate 15 -i build/demo-frames/f%04d.png \
  -vf "split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 docs/demo.gif
ls -lh docs/demo.gif

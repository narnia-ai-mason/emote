#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product EmoteApp
./scripts/build-mlx-metallib.sh

app=".build/Emote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/EmoteApp "$app/Contents/MacOS/Emote"
cp .build/mlx.metallib "$app/Contents/MacOS/mlx.metallib"
cp Sources/EmoteApp/Info.plist "$app/Contents/Info.plist"
for bundle in .build/release/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$app/Contents/Resources/"
done
./scripts/install-icon.sh "$app/Contents/Resources/Emote.icns"
open "$app"

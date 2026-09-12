#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product EmoteApp

app=".build/Emote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/EmoteApp "$app/Contents/MacOS/Emote"
cp Sources/EmoteApp/Info.plist "$app/Contents/Info.plist"
if [ -d .build/release/Emote_EmoteCore.bundle ]; then
  cp -R .build/release/Emote_EmoteCore.bundle "$app/Contents/Resources/Emote_EmoteCore.bundle"
fi
./scripts/install-icon.sh "$app/Contents/Resources/Emote.icns"
open "$app"

#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."

dest="${1:?usage: install-icon.sh <App.app/Contents/Resources/Emote.icns>}"
source="Resources/Emote.png"
png=".build/Emote-1024.png"
iconset=".build/Emote.iconset"

mkdir -p "$(dirname "$dest")" .build
if [ -f "$source" ]; then
  sips -s format png "$source" --out "$png" >/dev/null
else
  xcrun --sdk macosx swift scripts/make-icon.swift "$png"
fi

rm -rf "$iconset"
mkdir -p "$iconset"
for spec in \
  16:16x16 \
  32:16x16@2x \
  32:32x32 \
  64:32x32@2x \
  128:128x128 \
  256:128x128@2x \
  256:256x256 \
  512:256x256@2x \
  512:512x512 \
  1024:512x512@2x
do
  pixels="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$pixels" "$pixels" "$png" --out "$iconset/icon_${name}.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$dest"

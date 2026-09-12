#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/EmoteApp/Info.plist)"
root=".build/dmg-root"
app="$root/Emote.app"
rw=".build/Emote-rw.dmg"
dmg="dist/Emote-${version}.dmg"

eject_emote_volumes() {
  for path in /Volumes/Emote /Volumes/Emote\ *; do
    if [ -e "$path" ]; then
      hdiutil detach "$path" -force >/dev/null || true
    fi
  done
}

wait_for_file() {
  file="$1"
  tries=0
  while [ ! -f "$file" ] && [ "$tries" -lt 30 ]; do
    sleep 0.2
    tries=$((tries + 1))
  done
  [ -f "$file" ]
}

swift build -c release --product EmoteApp

rm -rf "$root" "$rw" "$dmg"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist

cp .build/release/EmoteApp "$app/Contents/MacOS/Emote"
cp Sources/EmoteApp/Info.plist "$app/Contents/Info.plist"
printf 'APPLEmot' > "$app/Contents/PkgInfo"
cp -R .build/release/Emote_EmoteCore.bundle "$app/Contents/Resources/Emote_EmoteCore.bundle"

./scripts/install-icon.sh "$app/Contents/Resources/Emote.icns"

ln -s /Applications "$root/Applications"
codesign --force --deep --sign - --timestamp=none "$app"

eject_emote_volumes
hdiutil create \
  -volname "Emote" \
  -srcfolder "$root" \
  -ov \
  -format UDRW \
  "$rw" >/dev/null

ATTACH="$(hdiutil attach -readwrite -noverify -noautoopen "$rw")"
MOUNT="$(printf '%s\n' "$ATTACH" | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)"
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT" ]; then
  echo "failed to mount $rw" >&2
  exit 1
fi
VOLNAME="$(basename "$MOUNT")"

osascript - "$VOLNAME" <<'EOF'
on run argv
  set volName to item 1 of argv
  tell application "Finder"
    tell disk volName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {220, 140, 780, 500}
      set opts to icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to 96
      set text size of opts to 12
      set label position of opts to bottom
      set position of item "Emote.app" of container window to {160, 180}
      set position of item "Applications" of container window to {400, 180}
      close
      open
      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
EOF

if ! wait_for_file "$MOUNT/.DS_Store"; then
  echo "Finder did not write window layout to $MOUNT/.DS_Store" >&2
  hdiutil detach "$MOUNT" -force >/dev/null || true
  exit 1
fi

sync
sleep 1
hdiutil detach "$MOUNT" >/dev/null || hdiutil detach "$MOUNT" -force >/dev/null
sleep 1

hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -f "$rw"
rm -rf "$root"
shasum -a 256 "$dmg" | tee "$dmg.sha256"

echo "$dmg"

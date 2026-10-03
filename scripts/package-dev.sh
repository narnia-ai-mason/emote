#!/bin/sh
set -euo pipefail

cd "$(dirname "$0")/.."

version="1.4.0-dev"
root=".build/dev-root"
app="$root/Emote Dev.app"
dmg="dist/Emote-${version}.dmg"

swift build -c release --product EmoteApp
./scripts/build-mlx-metallib.sh

rm -rf "$root" "$dmg"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist

cp .build/release/EmoteApp "$app/Contents/MacOS/Emote"
cp .build/mlx.metallib "$app/Contents/MacOS/mlx.metallib"
cp Sources/EmoteApp/Info.plist "$app/Contents/Info.plist"
printf 'APPLEmot' > "$app/Contents/PkgInfo"
for bundle in .build/release/*.bundle; do
  [ -d "$bundle" ] || continue
  cp -R "$bundle" "$app/Contents/Resources/"
done

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Emote Dev" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Emote Dev" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.minsikseo.emote.dev" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 7" "$app/Contents/Info.plist"

./scripts/install-icon.sh "$app/Contents/Resources/Emote.icns"
ln -s /Applications "$root/Applications"
codesign --force --deep --sign - --timestamp=none "$app"

hdiutil create \
  -volname "Emote Dev" \
  -srcfolder "$root" \
  -ov \
  -format UDZO \
  "$dmg" >/dev/null

rm -rf /Applications/Emote\ Dev.app
ditto "$app" "/Applications/Emote Dev.app"
codesign --force --deep --sign - --timestamp=none "/Applications/Emote Dev.app"

shasum -a 256 "$dmg" | tee "$dmg.sha256"
echo "$dmg"
echo "/Applications/Emote Dev.app"

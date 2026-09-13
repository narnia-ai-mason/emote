#!/bin/sh
# Records the Emote demo in Apple Notes.
#
#   ./scripts/record-demo.sh ko                  # dist/demo/emote-demo-ko.mp4 and .gif
#   ./scripts/record-demo.sh en
#   ./scripts/record-demo.sh ko path/to/other-scenario.txt
#
# Needs Emote running, and the terminal app allowed in
# System Settings → Privacy & Security → Accessibility and Screen Recording.
#
# Environment:
#   HOTKEY=ctrl+cmd+e   press this instead of fn (must match Emote's Settings)
#   KEEP_NOTE=1         keep the demo note instead of deleting it afterwards
#   WIN_W, WIN_H        note window size in points (default 1000x640)
#   ZOOM                how many times to press View > Zoom In (default 6)
#   MARGIN              points of desktop captured around the window (default 0)
set -eu

cd "$(dirname "$0")/.."

lang="${1:?usage: record-demo.sh ko|en [scenario.txt]}"
scenario="${2:-scripts/demo/scenario-$lang.txt}"
[ -f "$scenario" ] || { echo "no scenario file: $scenario" >&2; exit 1; }

build=".build/demo"
out="dist/demo"
driver="$build/driver"
raw="$build/raw-$lang.mov"
run="$build/run-$lang.txt"
log="$build/driver-$lang.log"
mp4="$out/emote-demo-$lang.mp4"
gif="$out/emote-demo-$lang.gif"
mkdir -p "$build" "$out"

if [ ! -x "$driver" ] || [ scripts/demo/driver.swift -nt "$driver" ]; then
  swiftc -O -o "$driver" scripts/demo/driver.swift
fi
"$driver" --check

# Place the note window in the middle of the main display.
win_w="${WIN_W:-1000}"
win_h="${WIN_H:-640}"
zoom="${ZOOM:-6}"
margin="${MARGIN:-0}"
set -- $("$driver" --screen)
screen_w="$1"
screen_h="$2"
win_x=$(( (screen_w - win_w) / 2 ))
win_y=$(( (screen_h - win_h) / 2 ))

note_info="$(osascript scripts/demo/notes-setup.applescript "$win_x" "$win_y" "$win_w" "$win_h" "$zoom")"
note_id="${note_info%%|*}"
rest="${note_info#*|}"
x="${rest%%|*}"; rest="${rest#*|}"
y="${rest%%|*}"; rest="${rest#*|}"
w="${rest%%|*}"; rest="${rest#*|}"
h="${rest%%|*}"; rest="${rest#*|}"
spell="${rest}"
echo "note: $note_id"
echo "window: ${x},${y} ${w}x${h}"
echo "spelling while typing was on: $spell"

cleanup() {
  if [ -n "${cap_pid:-}" ] && kill -0 "$cap_pid" 2>/dev/null; then
    kill -INT "$cap_pid" 2>/dev/null || true
    wait "$cap_pid" 2>/dev/null || true
  fi
  if [ -n "${previous_input:-}" ]; then
    "$driver" --input-source "$previous_input" >/dev/null 2>&1 || true
    previous_input=""
  fi
  if [ "${KEEP_NOTE:-0}" != "1" ]; then
    osascript scripts/demo/notes-teardown.applescript "$note_id" "$spell" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

# Type with a Latin layout; the Korean input mode would turn "Mason" into jamo.
# The badge macOS shows for the switch must not end up in the video, so switch
# before recording and switch back after.
previous_input="$("$driver" --input-source com.apple.keylayout.ABC)"
sleep 1

# Before recording: click into the note, clear the placeholder text Notes puts
# in a scripted note, make the first line a Title, and park the pointer outside
# the window. The video then opens on an empty note with a blinking caret.
prep="$build/prep-$lang.txt"
{
  echo "click $(( x + w / 2 )) $(( y + 160 ))"
  echo "wait 300"
  echo "key cmd+a"
  echo "key delete"
  echo "key shift+cmd+t"
  echo "mouse $(( x + w + 24 )) $(( y + h / 2 ))"
  echo "wait 300"
} > "$prep"
"$driver" "$prep" > /dev/null
{
  echo "wait 1500"
  cat "$scenario"
} > "$run"

rx=$(( x - margin )); ry=$(( y - margin )); rw=$(( w + margin * 2 )); rh=$(( h + margin * 2 ))
rm -f "$raw"
cap_start=$(date +%s.%N)
screencapture -v -x -R "${rx},${ry},${rw},${rh}" "$raw" &
cap_pid=$!
sleep 2

driver_start=$(date +%s.%N)
set +e
"$driver" "$run" ${HOTKEY:+--hotkey "$HOTKEY"} > "$log" 2>&1
driver_status=$?
set -e
cat "$log"
sleep 1

kill -INT "$cap_pid"
wait "$cap_pid" || true
cap_pid=""
"$driver" --input-source "$previous_input" >/dev/null || true
previous_input=""
[ -s "$raw" ] || { echo "screencapture produced no file" >&2; exit 1; }

# Keep about a second of stillness before the first keystroke.
trim="$(printf '%s %s\n' "$driver_start" "$cap_start" | awk '{t = $1 - $2 - 0.5; if (t < 0) t = 0; printf "%.2f", t}')"
ffmpeg -y -loglevel error -ss "$trim" -i "$raw" \
  -vf "fps=60,scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
  -c:v libx264 -crf 20 -preset slow -movflags +faststart -an "$mp4"
ffmpeg -y -loglevel error -i "$mp4" \
  -vf "fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=5" \
  "$gif"

# Keep every take so the best one can be picked afterwards.
stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$build/takes"
cp "$mp4" "$build/takes/$lang-$stamp.mp4"
cp "$log" "$build/takes/$lang-$stamp.log"
echo "archived: $build/takes/$lang-$stamp.mp4"

echo "driver exit: $driver_status (0 = every pick was a preferred emoji, 4 = some fell back to the first suggestion, 3 = a pick failed)"
echo "$mp4"
echo "$gif"
exit "$driver_status"

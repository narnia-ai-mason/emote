#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mlx="$root/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
kernels="$mlx/mlx/backend/metal/kernels"
cmake="$kernels/CMakeLists.txt"
out="$root/.build/mlx.metallib"
air_dir="$root/.build/mlx-air"

if [ ! -f "$cmake" ]; then
  echo "mlx-swift is not checked out yet. Build the app once, then run this again." >&2
  exit 1
fi

copy_existing() {
  for candidate in \
    "$root/.build/debug/mlx.metallib" \
    "$root/.build/release/mlx.metallib" \
    "$HOME/.local/share/uv/tools/mlx-vlm/lib/python3.11/site-packages/mlx/lib/mlx.metallib" \
    "/tmp/gemma-mlx/lib/python3.14/site-packages/mlx/lib/mlx.metallib"
  do
    if [ -f "$candidate" ]; then
      cp "$candidate" "$out"
      echo "Using $candidate" >&2
      return 0
    fi
  done
  return 1
}

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  echo "Metal toolchain is not installed, so the shaders cannot be compiled here." >&2
  if ! copy_existing; then
    echo "No mlx.metallib was found. Install the Metal toolchain, then run this again." >&2
    exit 1
  fi
  bindir="$(cd "$root" && swift build --show-bin-path)"
  cp "$out" "$bindir/mlx.metallib"
  echo "$out"
  exit 0
fi

mkdir -p "$air_dir"
sources="$(
  python3 - "$cmake" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
names = re.findall(r"^build_kernel\(([^)\s]+)", text, re.M)
print("\n".join(names))
PY
)"

flags="-x metal -Wall -Wextra -fno-fast-math -Wno-c++17-extensions -Wno-c++20-extensions -Wmetal-addr-spaces -mmacosx-version-min=14.0"
needs_link=0
printf '%s\n' "$sources" | while IFS= read -r name; do
  [ -n "$name" ] || continue
  src="$kernels/$name.metal"
  air="$air_dir/$(echo "$name" | tr '/' '_').air"
  if [ ! -f "$src" ]; then
    echo "missing $src" >&2
    exit 1
  fi
  if [ ! -f "$air" ] || [ "$src" -nt "$air" ]; then
    echo "metal $name"
    xcrun -sdk macosx metal $flags -c "$src" -I "$mlx" -o "$air"
  fi
done

if [ ! -f "$out" ] || [ -n "$(find "$air_dir" -name '*.air' -newer "$out" -print -quit)" ]; then
  needs_link=1
fi
if [ "$needs_link" -eq 1 ]; then
  echo "linking mlx.metallib"
  xcrun -sdk macosx metal -mmacosx-version-min=14.0 "$air_dir"/*.air -o "$out"
fi

bindir="$(cd "$root" && swift build --show-bin-path)"
cp "$out" "$bindir/mlx.metallib"
echo "$out"

#!/bin/bash
# Stills of every step of every interactive lesson, from the app's own snapshot mode (no screen-recording permission
# needed; 3D scenes included). For the marketing chapter about learning (docs/marketing/script-learn.md).
#
#   bash scripts/make-lesson-stills.sh <photo> [binary]
#
# Writes dist/lesson-stills/full/<lesson>-<step>.png (the whole lesson window: scene, step text, buttons) and
# dist/lesson-stills/scene/<lesson>-<step>.jpg (only the scene, 1000 px wide). The photo is shown inside the lessons,
# so use one you may publish (a landscape). The binary defaults to the debug build of the workbench (scripts/dev-build.sh
# makes it); it is run with an isolated data folder, so your own library and settings are not touched.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$root"
photo="${1:?a photo to show inside the lessons}"; [ -f "$photo" ] || { echo "找不到文件：$photo" >&2; exit 1; }
bin="${2:-$root/.build/native-debug/arm64-apple-macosx/debug/media-workbench}"
[ -x "$bin" ] || { echo "找不到可执行文件：$bin（先运行 bash scripts/dev-build.sh）" >&2; exit 1; }
out="$root/dist/lesson-stills"; mkdir -p "$out/full" "$out/scene"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp "$photo" "$work/demo.jpg"
# lesson id : number of steps (Sources/MediaCore/Lessons.swift)
lessons="pixels-histogram:5 five-zones:2 clipping:1 exposure-brightness:1 tone-controls:1 curves:2 white-balance:2 hsl:2 aperture:2 exposure-triangle:3 focal-length:2 frame-rate:2 log-lut:2"
for entry in $lessons; do
  id="${entry%%:*}"; n="${entry##*:}"
  steps="size:1470x836;import:$work/demo.jpg;wait:4;open:$work/demo.jpg;wait:3"
  for k in $(seq 0 $((n - 1))); do steps="$steps;lesson:$id@$k;wait:4;shot:$id-$k"; done
  mkdir -p "$work/shots-$id"
  GUANGJI_DATA_DIR="$work/data-$id" GUANGJI_SNAPSHOT_DIR="$work/shots-$id" GUANGJI_SNAPSHOT_STEPS="$steps;quit" \
    "$bin" -AppleLanguages "(zh-Hans)" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 150); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill "$pid" 2>/dev/null || true
  for k in $(seq 0 $((n - 1))); do
    src="$work/shots-$id/$id-$k.png"
    [ -s "$src" ] || { echo "没有拍到：$id 第 $k 步" >&2; continue; }
    cp "$src" "$out/full/$id-$k.png"
    w="$(sips -g pixelWidth "$src" | awk '/pixelWidth/{print $2}')"; h="$(sips -g pixelHeight "$src" | awk '/pixelHeight/{print $2}')"
    # the scene is the left part below the title bar; the step text and buttons are on the right
    ffmpeg -loglevel error -y -i "$src" -vf "crop=iw*0.703:ih-ih*0.086:0:ih*0.086,scale=1000:-1" -q:v 3 "$out/scene/$id-$k.jpg"
  done
  echo "$id ✓"
done
echo "$out"

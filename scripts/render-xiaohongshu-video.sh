#!/bin/bash
# Renders docs/marketing/xiaohongshu/video.html to a silent 1080x1920 MP4 (add your voice and clips in an editor),
# or to still frames for checking a scene:
#
#   bash scripts/render-xiaohongshu-video.sh                 # dist/xiaohongshu.mp4, 30 fps
#   bash scripts/render-xiaohongshu-video.sh still 2 8.5 20  # dist/xhs-stills/t-*.png at those seconds
#   FPS=24 JOBS=4 bash scripts/render-xiaohongshu-video.sh
#
# Needs Google Chrome and ffmpeg (brew install ffmpeg). Chrome runs headless, one process per frame.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
html="$root/docs/marketing/xiaohongshu/video.html"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
fps="${FPS:-30}"; jobs="${JOBS:-6}"
[ -x "$chrome" ] || { echo "找不到 Chrome：$chrome（可用 CHROME=路径 指定）" >&2; exit 1; }
total="$(python3 - "$html" <<'EOF'
import re,sys
print(sum(float(x) for x in re.findall(r'<section class="scene[^>]*data-dur="([\d.]+)"', open(sys.argv[1]).read())))
EOF
)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$root/dist"

# Headless Chrome saves the screenshot but then keeps running, so wait for the file and stop it.
# The window is taller than 1920 because Chrome reserves some height; frames are cropped afterwards.
render_frame() { # <time seconds> <output png>
  local t="$1" out="$2" profile; profile="$(mktemp -d "$work/p.XXXXXX")"
  rm -f "$out"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1080,2007 \
    --user-data-dir="$profile" --virtual-time-budget=3000 --screenshot="$out" "file://$html?render=1&t=$t" >/dev/null 2>&1 &
  local pid=$! size=-1 stable=0
  for _ in $(seq 1 300); do
    sleep 0.1
    if [ -s "$out" ]; then
      local now; now="$(stat -f %z "$out")"
      if [ "$now" = "$size" ]; then stable=$((stable + 1)); else stable=0; size="$now"; fi
      [ "$stable" -ge 2 ] && break
    fi
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -rf "$profile"
  [ -s "$out" ] || { echo "渲染失败：t=$t" >&2; return 1; }
}
export -f render_frame; export chrome html work

if [ "${1:-}" = "still" ]; then
  shift; mkdir -p "$root/dist/xhs-stills"
  for t in "$@"; do
    render_frame "$t" "$work/raw.png"
    ffmpeg -loglevel error -y -i "$work/raw.png" -vf "crop=1080:1920:0:0" "$root/dist/xhs-stills/t-$t.png"
    echo "dist/xhs-stills/t-$t.png"
  done
  exit 0
fi

frames="$(python3 -c "import math;print(math.ceil($total*$fps))")"
mkdir -p "$work/raw"
echo "渲染 $frames 帧（${total}s × ${fps}fps，并行 $jobs）…"
seq 0 $((frames - 1)) | xargs -P "$jobs" -I{} bash -c 'render_frame "$(python3 -c "print(round({}/'"$fps"',4))")" "'"$work"'/raw/$(printf %05d {}).png"'
count="$(ls "$work/raw" | wc -l | tr -d ' ')"
[ "$count" = "$frames" ] || { echo "只渲染了 $count / $frames 帧" >&2; exit 1; }
ffmpeg -loglevel error -y -framerate "$fps" -i "$work/raw/%05d.png" -vf "crop=1080:1920:0:0,format=yuv420p" \
  -c:v libx264 -crf 17 -preset medium -movflags +faststart "$root/dist/xiaohongshu.mp4"
ls -la "$root/dist/xiaohongshu.mp4" | awk '{print $5/1048576 " MB  dist/xiaohongshu.mp4"}'

#!/bin/bash
# Regenerates the website's screenshots from the app's own snapshot mode (no screen-recording
# permission needed).
#
#   bash scripts/make-site-screenshots.sh <folder-of-demo-photos> <hero-photo> [video] [before-after-photo]
#
# The demo photos are shown publicly, so use pictures you have the right to publish (landscapes,
# not portraits). Snapshots draw Liquid Glass with its flat fallback and cannot capture video frames;
# replace website/assets/shot-edit.jpg with a real screen capture if you want the glass look.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
demo="${1:?demo photo folder}"; hero="${2:?hero photo}"; video="${3:-}"; compare_photo="${4:-$hero}"
out="$root/website/assets"; work="$(mktemp -d)"; shots="$work/shots"; crops="$work/crops"
mkdir -p "$out" "$shots" "$crops"
bin="$(bash scripts/dev-build.sh | tail -1)"
imports="$demo${video:+,$video}"

run() { # steps
  GUANGJI_DATA_DIR="$work/data" GUANGJI_SNAPSHOT_DIR="$shots" GUANGJI_SNAPSHOT_STEPS="$1" "$bin" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 120); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill "$pid" 2>/dev/null || true
}

# Browse grid, then the hero photo after 自动, presets, the 构图 tab with a square crop, the 学习 tab.
run "import:$imports;wait:12;shot:browse;open:$hero;tab:color;colormode:simple;wait:4;auto;wait:8;shot:edit;\
panel:presets@700;crop:0.9,30,0,1;tab:geometry;wait:3;shot:crop;tab:learn;wait:2;panel:learn@1150;quit"
[ -n "$video" ] && run "open:$video;tab:info;collapse:文件;wait:6;panel:info@1100;quit"
run "open:$hero;wait:3;sheet:export;wait:2;shot:export;quit"

jpg() { sips -s format jpeg -s formatOptions 90 "$1" --out "$2" >/dev/null 2>&1; }
# Window shots: drop the title bar (its glass controls can't be captured) and the status bar.
for name in browse edit crop; do
  sips -c 1514 2940 --cropOffset 104 0 "$shots/$name.png" --out "$crops/$name.png" >/dev/null
  jpg "$crops/$name.png" "$out/shot-$name.jpg"
done
sips -c 880 660 --cropOffset 0 0 "$shots/presets.png" --out "$crops/presets.png" >/dev/null; jpg "$crops/presets.png" "$out/panel-presets.jpg"
sips -c 1040 574 --cropOffset 0 0 "$shots/learn.png" --out "$crops/learn.png" >/dev/null; jpg "$crops/learn.png" "$out/panel-learn.jpg"
[ -f "$shots/info.png" ] && { sips -c 1330 600 --cropOffset 0 0 "$shots/info.png" --out "$crops/info.png" >/dev/null; jpg "$crops/info.png" "$out/panel-info.jpg"; }
jpg "$shots/export.png" "$out/sheet-export.jpg"

# The before / after pair is the engine's real 自动 result (left = before).
cmp="$work/cmp.jpg"
swift run --quiet media-probe auto "$compare_photo" "$cmp" >/dev/null
w=$(sips -g pixelWidth "$cmp" | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$cmp" | awk '/pixelHeight/{print $2}')
half=$(( (w - 8) / 2 ))
sips -c "$h" "$half" --cropOffset 0 0 "$cmp" --out "$out/before.jpg" >/dev/null
sips -c "$h" "$half" --cropOffset 0 $((half + 8)) "$cmp" --out "$out/after.jpg" >/dev/null
echo "Updated website/assets (working files in $work)"

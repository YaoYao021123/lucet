# Shared by the render-xiaohongshu-*.sh scripts. Source it after setting $chrome and $work.
#
# render_frame <url> <output.png>
# Headless Chrome saves the screenshot but then keeps running, so wait for the file to settle and stop it.
# The window is taller than the picture because Chrome reserves some height; callers crop afterwards.
# CHROME_WIDTH / CHROME_HEIGHT choose the window size (default 1080 x 2007, for a 1080 x 1920 picture).
# A frame that does not appear is retried (up to 3 times, with more patience each time).
# CHROME_TRANSPARENT=1 keeps the page background transparent (the PNG gets an alpha channel).
_render_frame_once() {
  local url="$1" out="$2" waits="$3" profile; profile="$(mktemp -d "$work/p.XXXXXX")"
  rm -f "$out"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    ${CHROME_TRANSPARENT:+--default-background-color=00000000} \
    --window-size="${CHROME_WIDTH:-1080},${CHROME_HEIGHT:-2007}" --user-data-dir="$profile" \
    --virtual-time-budget=3000 --screenshot="$out" "$url" >/dev/null 2>&1 &
  local pid=$! size=-1 stable=0
  for _ in $(seq 1 "$waits"); do
    sleep 0.1
    if [ -s "$out" ]; then
      local now; now="$(stat -f %z "$out")"
      if [ "$now" = "$size" ]; then stable=$((stable + 1)); else stable=0; size="$now"; fi
      [ "$stable" -ge 2 ] && break
    fi
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -rf "$profile"
  [ -s "$out" ]
}
# A busy Mac (another build running) can make Chrome slow, so a frame that does not appear is tried again with more patience.
render_frame() {
  local url="$1" out="$2" try
  for try in 1 2 3; do
    _render_frame_once "$url" "$out" $((300 * try)) && return 0
  done
  echo "渲染失败：$url" >&2; return 1
}
export -f _render_frame_once render_frame

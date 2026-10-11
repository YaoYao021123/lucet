#!/usr/bin/env python3
"""Writes the three whiteboard sketches as .excalidraw files you can open and edit on https://excalidraw.com

    python3 scripts/export-excalidraw.py            # -> docs/marketing/xiaohongshu/excalidraw/{problem,flow,story}.excalidraw

On excalidraw.com: open the menu (top left) -> Open, or just drag the file onto the page. The shapes are the same as
in the video (drawn by docs/marketing/xiaohongshu/sketches.html). Text is placed approximately; nudge anything that looks off.
Real pictures from docs/marketing/xiaohongshu/pics/ are embedded in the file.
Excalidraw's own look differs a little from the video's (its line style and handwriting font), and this is a one-way export:
edits made on excalidraw.com do not flow back into sketches.html.
"""
import base64
import html
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from sketch_pics import find_pics, pics_param
XHS = ROOT / "docs/marketing/xiaohongshu"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out = XHS / "excalidraw"
out.mkdir(exist_ok=True)
pics = find_pics()
for board in ("problem", "flow", "story"):
    with tempfile.TemporaryDirectory() as profile, tempfile.TemporaryFile() as dump:
        chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={profile}", "--dump-dom",
                                   f"file://{XHS}/sketches.html?board={board}&export=1&pics={pics_param(pics)}"], stdout=dump, stderr=subprocess.DEVNULL)
        dom = ""
        for _ in range(300):                       # Chrome prints the page but then keeps running: wait for the drawing, then stop it
            time.sleep(0.1)
            dump.seek(0); dom = dump.read().decode("utf-8", "replace")
            if "</pre>" in dom:
                break
        chrome.kill(); chrome.wait()
    m = re.search(r'<pre id="excalidraw">(.*?)</pre>', dom, re.S)
    if not m:
        raise SystemExit(f"{board}: Chrome did not return the drawing")
    doc = json.loads(html.unescape(m.group(1)))
    for e in doc["elements"]:                      # pictures travel inside the file, so it opens anywhere
        if e["type"] == "image":
            path = Path(pics[e["fileId"][4:]]["path"])
            mime = {"png": "image/png", "webp": "image/webp"}.get(path.suffix[1:], "image/jpeg")
            doc["files"][e["fileId"]] = {"mimeType": mime, "id": e["fileId"], "created": 1, "lastRetrieved": 1,
                                         "dataURL": f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"}
    (out / f"{board}.excalidraw").write_text(json.dumps(doc, ensure_ascii=False, indent=1))
    print(f"{board}.excalidraw  {len(doc['elements'])} shapes")

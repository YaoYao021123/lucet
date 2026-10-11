#!/usr/bin/env python3
"""Writes the three whiteboard sketches as .excalidraw files you can open and edit on https://excalidraw.com

    python3 scripts/export-excalidraw.py            # -> docs/marketing/xiaohongshu/excalidraw/{problem,flow,story}.excalidraw

On excalidraw.com: open the menu (top left) -> Open, or just drag the file onto the page. The shapes are the same as
in the video (drawn by docs/marketing/xiaohongshu/sketches.html). Text is placed approximately; nudge anything that looks off.
Excalidraw's own look differs a little from the video's (its line style and handwriting font), and this is a one-way export:
edits made on excalidraw.com do not flow back into sketches.html.
"""
import html
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XHS = ROOT / "docs/marketing/xiaohongshu"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out = XHS / "excalidraw"
out.mkdir(exist_ok=True)
for board in ("problem", "flow", "story"):
    with tempfile.TemporaryDirectory() as profile, tempfile.TemporaryFile() as dump:
        chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={profile}", "--dump-dom",
                                   f"file://{XHS}/sketches.html?board={board}&export=1"], stdout=dump, stderr=subprocess.DEVNULL)
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
    (out / f"{board}.excalidraw").write_text(json.dumps(doc, ensure_ascii=False, indent=1))
    print(f"{board}.excalidraw  {len(doc['elements'])} shapes")

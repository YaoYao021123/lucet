#!/usr/bin/env python3
"""Writes all the whiteboard pages as ONE .excalidraw file you can open and edit on https://excalidraw.com

    python3 scripts/export-excalidraw.py            # -> docs/marketing/xiaohongshu/excalidraw/lucet-story.excalidraw

The pages sit on one canvas, four to a row, each inside a named frame. The two chapters each start on a new row under a
big title: the story ("1 phone", "2 sliders" ...) and the chapter about learning ("L1 why", "L2 read" ...).

On excalidraw.com: open the menu (top left) -> Open, or just drag the file onto the page. The shapes are the same as
in the video (drawn by docs/marketing/xiaohongshu/sketches.html). Text is placed approximately; nudge anything that looks off.
Real pictures from docs/marketing/xiaohongshu/pics/ are embedded in the file (shrunk to 700 px wide, to keep it light).
Excalidraw's own look differs a little from the video's (its line style and handwriting font), and this is a one-way export:
edits made on excalidraw.com do not flow back into sketches.html.
"""
import base64
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts/lib"))
from sketch_pics import CHAPTERS, find_pics, pics_param
XHS = ROOT / "docs/marketing/xiaohongshu"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TITLES = {"story": ("故事 · The story", ""), "learn": ("边调边学 · Learning while you edit", "L")}
out = XHS / "excalidraw"
out.mkdir(exist_ok=True)
for old in out.glob("*.excalidraw"):
    old.unlink()                                   # pages that no longer exist
pics = find_pics()
COLS, PAGE, GAP, TITLE_H = 4, 1080, 200, 260       # four pages to a row; every page is 1080 x 1080
combined = {"type": "excalidraw", "version": 2, "source": "https://excalidraw.com", "elements": [],
            "appState": {"viewBackgroundColor": "#fbf8ef", "gridSize": None}, "files": {}}
base_style = {"angle": 0, "fillStyle": "solid", "strokeWidth": 2, "strokeStyle": "solid", "roughness": 1, "opacity": 100, "groupIds": [],
              "frameId": None, "roundness": None, "version": 1, "isDeleted": False, "boundElements": None, "updated": 1, "link": None,
              "locked": False}
shrunk = Path(tempfile.mkdtemp())


def data_url(slot):
    """The picture of a slot, shrunk to 700 px wide, as a data: URL."""
    src = Path(pics[slot]["path"])
    small = shrunk / src.name
    subprocess.run(["sips", "-Z", "700", str(src), "--out", str(small)], capture_output=True, check=True)
    mime = {"png": "image/png", "webp": "image/webp"}.get(src.suffix[1:].lower(), "image/jpeg")
    return mime, f"data:{mime};base64,{base64.b64encode(small.read_bytes()).decode()}"


def page(board):
    """The shapes of one page, as Excalidraw elements, straight from sketches.html."""
    profile = tempfile.mkdtemp()
    with tempfile.TemporaryFile() as dump:
        chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", f"--user-data-dir={profile}", "--dump-dom",
                                   f"file://{XHS}/sketches.html?board={board}&export=1&pics={pics_param(pics)}"], stdout=dump, stderr=subprocess.DEVNULL)
        dom = ""
        for _ in range(300):                       # Chrome prints the page but then keeps running: wait for the drawing, then stop it
            time.sleep(0.1)
            dump.seek(0); dom = dump.read().decode("utf-8", "replace")
            if "</pre>" in dom:
                break
        chrome.kill(); chrome.wait()
    shutil.rmtree(profile, ignore_errors=True)     # Chrome may still be writing for a moment; a leftover temp folder does no harm
    m = re.search(r'<pre id="excalidraw">(.*?)</pre>', dom, re.S)
    if not m:
        raise SystemExit(f"{board}: Chrome did not return the drawing")
    return json.loads(html.unescape(m.group(1)))


row = 0
total = 0
for chapter, boards in CHAPTERS.items():
    title, prefix = TITLES[chapter]
    top = row * (PAGE + GAP) + (0 if row == 0 else 0)
    combined["elements"].append({**base_style, "id": f"title-{chapter}", "type": "text", "x": 0, "y": top, "width": 1600, "height": 100,
                                 "strokeColor": "#e8590c", "backgroundColor": "transparent", "seed": 7, "versionNonce": 7, "text": title,
                                 "originalText": title, "fontSize": 80, "fontFamily": 5, "textAlign": "left", "verticalAlign": "top",
                                 "containerId": None, "autoResize": True, "lineHeight": 1.25})
    top += TITLE_H
    for n, (board, anchors) in enumerate(boards):
        doc = page(board)
        if set(doc.pop("anchors")) != {k for k, _ in anchors}:
            raise SystemExit(f"{board}: the anchors in sketches.html and scripts/lib/sketch_pics.py differ")
        for e in doc["elements"]:                  # pictures travel inside the file, so it opens anywhere
            if e["type"] == "image":
                slot = e["fileId"][4:]
                mime, url = data_url(slot)
                combined["files"][e["fileId"]] = {"mimeType": mime, "id": e["fileId"], "created": 1, "lastRetrieved": 1, "dataURL": url}
        ox, oy = n % COLS * (PAGE + GAP), top + n // COLS * (PAGE + GAP)
        frame_id = f"frame-{board}"
        for e in doc["elements"]:                  # move the page to its place on the canvas and put it in its frame
            e["x"] += ox; e["y"] += oy; e["frameId"] = frame_id
        frame = {**base_style, "id": frame_id, "type": "frame", "name": f"{prefix}{n + 1} {board}", "x": ox, "y": oy, "width": PAGE,
                 "height": PAGE, "strokeColor": "#bbbbbb", "backgroundColor": "transparent", "roughness": 0, "seed": 1, "versionNonce": 1}
        combined["elements"] += doc["elements"] + [frame]      # a frame comes after the shapes inside it
        total += 1
        print(f"{prefix}{n + 1:>2} {board:<10} {len(doc['elements'])} shapes")
    row += -(-len(boards) // COLS)                 # rows used by this chapter
    row += 0
    # the next chapter starts a little lower: its title sits in the extra TITLE_H
shutil.rmtree(shrunk, ignore_errors=True)
(out / "lucet-story.excalidraw").write_text(json.dumps(combined, ensure_ascii=False, indent=1))
print(f"{total} pages -> {out / 'lucet-story.excalidraw'}")

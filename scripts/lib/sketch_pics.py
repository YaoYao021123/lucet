"""Finds the pictures that go into the whiteboard sketches (docs/marketing/xiaohongshu/pics/<slot>.png|jpg).

A slot is a place in a sketch where a real picture (usually an app screenshot) can sit: auto, presets, crop, save.
Put your own file with that name in the folder to replace it; remove it to get the hand-drawn icon back.
"""
import json
import subprocess
from pathlib import Path
from urllib.parse import quote

PICS = Path(__file__).resolve().parents[2] / "docs/marketing/xiaohongshu/pics"
SLOTS = ("auto", "presets", "crop", "save")


def find_pics():
    found = {}
    for slot in SLOTS:
        for ext in ("png", "jpg", "jpeg", "webp"):
            path = PICS / f"{slot}.{ext}"
            if path.exists():
                out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], capture_output=True, text=True).stdout
                w, h = (int(line.split()[-1]) for line in out.splitlines() if "pixel" in line)
                found[slot] = {"path": str(path), "src": path.as_uri(), "w": w, "h": h}
                break
    return found


def pics_param(found):
    """The &pics=… part of a sketches.html address."""
    return quote(json.dumps({k: {"src": v["src"], "w": v["w"], "h": v["h"]} for k, v in found.items()}))

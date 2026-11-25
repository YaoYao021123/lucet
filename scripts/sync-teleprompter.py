#!/usr/bin/env python3
"""Copies the talk scripts (docs/marketing/script-long.md and script-learn.md) into the teleprompter page.

    python3 scripts/sync-teleprompter.py

teleprompter.html?v=long-zh / long-en show the main story, ?v=learn-zh / learn-en the chapter about the lessons. The
markdown files are the source: edit the words there and run this. Every text line of the Chinese and English sections
becomes one prompter line. Skipped: headings, rules, quotes, *notes*, and the 〔…〕 / […] picture suggestions. A line that
starts with 【 stays (it is yours to fill in).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = {"long": ROOT / "docs/marketing/script-long.md", "learn": ROOT / "docs/marketing/script-learn.md"}
PAGE = ROOT / "docs/marketing/xiaohongshu/teleprompter.html"


def lines(section):
    out = []
    for line in section.split("\n"):
        line = line.strip()
        if not line or line[0] in "#>*〔[" or line.startswith("---"):
            continue
        out.append(line.replace("*", ""))          # *emphasis* markers are for readers of the markdown, not for the prompter
    return out


parts = []
for name, path in SCRIPTS.items():
    md = path.read_text()
    zh = lines(md.split("## 中文版")[1].split("## English version")[0])
    en = lines(md.split("## English version")[1])
    parts += [f'"{name}-zh": ' + json.dumps(zh, ensure_ascii=False), f'"{name}-en": ' + json.dumps(en, ensure_ascii=False)]
    print(f"{name}: {len(zh)} Chinese lines, {len(en)} English lines")
new = "const LONG = {" + ",\n  ".join(parts) + "};"
page = PAGE.read_text()
page, n = re.subn(r"const LONG = \{.*?\]\};", lambda m: new, page, count=1, flags=re.S)
if n != 1:
    raise SystemExit("could not find the LONG lines in teleprompter.html")
PAGE.write_text(page)

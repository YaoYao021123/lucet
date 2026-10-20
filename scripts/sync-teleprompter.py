#!/usr/bin/env python3
"""Copies the long talk script (docs/marketing/script-long.md) into the teleprompter page.

    python3 scripts/sync-teleprompter.py

teleprompter.html?v=long-zh / ?v=long-en show these lines; the markdown file is the source, so edit the words there and
run this. Every text line of the Chinese and English sections becomes one prompter line. Skipped: headings, rules,
quotes, *notes*, and the 〔…〕 / […] picture suggestions. A line that starts with 【 stays (it is yours to fill in).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MD = ROOT / "docs/marketing/script-long.md"
PAGE = ROOT / "docs/marketing/xiaohongshu/teleprompter.html"


def lines(section):
    out = []
    for line in section.split("\n"):
        line = line.strip()
        if not line or line[0] in "#>*〔[" or line.startswith("---"):
            continue
        out.append(line.replace("*", ""))          # *emphasis* markers are for readers of the markdown, not for the prompter
    return out


md = MD.read_text()
zh = lines(md.split("## 中文版")[1].split("## English version")[0])
en = lines(md.split("## English version")[1])
new = ('const LONG = {"long-zh": ' + json.dumps(zh, ensure_ascii=False) + ',\n  "long-en": ' + json.dumps(en, ensure_ascii=False) + '};')
page = PAGE.read_text()
page, n = re.subn(r'const LONG = \{"long-zh": \[.*?\],\n\s*"long-en": \[.*?\]\};', lambda m: new, page, count=1, flags=re.S)
if n != 1:
    raise SystemExit("could not find the LONG lines in teleprompter.html")
PAGE.write_text(page)
print(f"teleprompter.html: {len(zh)} Chinese lines, {len(en)} English lines")

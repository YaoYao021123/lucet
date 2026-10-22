"""Finds the pictures that go into the whiteboard sketches, and holds the word -> whiteboard table.

Pictures: every file in docs/marketing/xiaohongshu/pics/ (png, jpg, jpeg, webp) is a "slot" named after the file, e.g.
auto.jpg is the slot "auto" and lesson-hsl-1.jpg is "lesson-hsl-1". A page that asks for a slot shows the picture
(an app screenshot, a before/after result, a lesson still); remove the file and the page falls back to a drawing.

Chapters: the story (CHAPTERS["story"]) and the chapter about learning (CHAPTERS["learn"]).
"""
import json
import subprocess
from pathlib import Path
from urllib.parse import quote

PICS = Path(__file__).resolve().parents[2] / "docs/marketing/xiaohongshu/pics"


def find_pics():
    found = {}
    for path in sorted(PICS.iterdir()):
        if path.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp") or path.stem in found:
            continue
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], capture_output=True, text=True).stdout
        w, h = (int(line.split()[-1]) for line in out.splitlines() if line.strip().startswith(("pixelWidth", "pixelHeight")))
        found[path.stem] = {"path": str(path), "src": path.as_uri(), "w": w, "h": h}
    return found


def pics_param(found):
    """The &pics=… part of a sketches.html address."""
    return quote(json.dumps({k: {"src": v["src"], "w": v["w"], "h": v["h"]} for k, v in found.items()}))


# What you say -> when a sketch element appears. One entry per board of sketches.html, in the order the story is told.
# Each board lists its "anchors" (the names used in sketches.html) and a pattern for the words that start them.
# build-talking-video.py searches the recognised speech for the patterns in order; export-excalidraw.py checks that
# these names match the ones in sketches.html. If you change a board, change its anchors here too.
STORY = [
    ("phone", [("mimo", r"Mimo|米莫|咪摩"), ("back", r"传回|回手机"), ("small", r"小小的|小屏")]),
    ("sliders", [("pro", r"专业软件|Lightroom|莱特"), ("many", r"几十个|滑块"), ("names", r"曝光[，、,]|去朦胧"), ("lost", r"先动哪|不知道先")]),
    ("idea", [("simple", r"简单得像|像手机"), ("teach", r"有人在旁边|讲给你听|旁边")]),
    ("origin", [("chatgpt", r"ChatGPT"), ("runs", r"能跑"), ("claude", r"Claude ?Code"), ("hunt", r"挑毛病")]),
    ("audit", [("files", r"两千个|2000|2千"), ("slow", r"7 ?秒|七秒|将近"), ("fast", r"百分之一|0\.01"), ("lut", r"LUT|lut"), ("works", r"正常用|能用了")]),
    ("sentences", [("loop", r"普通的话|一句话"), ("blue", r"蓝色"), ("loose", r"太松|紧凑"), ("info", r"信息不够"), ("boxes", r"方框"), ("rounds", r"一轮一轮|一轮")]),
    ("mistake", [("latte", r"拿铁|白桌子"), ("wrong", r"偏亮"), ("fix", r"降一档|一档半|曝光降"), ("real", r"本来就应该|本来就该"), ("test", r"加上测试|测试")]),
    ("auto", [("auto", r"自动"), ("read", r"读这张|先读"), ("restraint", r"克制|白底"), ("undo", r"撤销"), ("six", r"六个滑块|六个")]),
    ("presets", [("presets", r"预设"), ("thumbs", r"小图|这张照片做成"), ("crop", r"裁剪"), ("drag", r"在照片上拖|直接在照片")]),
    ("save", [("save", r"存进|直接存进"), ("icloud", r"iCloud|icloud"), ("iphone", r"iPhone|手机上"), ("live", r"实况|三秒")]),
    ("grow", [("local", r"只改照片的一部分|渐变|局部"), ("remove", r"去除|涂一笔|电线|路人|去掉"), ("match", r"匹配色调|另一张照片的颜色"),
              ("project", r"项目"), ("ai", r"AI 调色|小型 AI|AI HDR|AI 模型")]),
    ("teach", [("filter", r"一键滤镜"), ("xiaoyang", r"张小样|摄影博主|小样"), ("few", r"几条视频|讲不完"), ("inapp", r"放进了? ?App|放进")]),
    ("name", [("name", r"Lucet|路塞|露塞"), ("lat", r"拉丁|发光"), ("gather", r"收集"), ("photo", r"留住的光|被留住")]),
    ("honest", [("early", r"早期版本"), ("apple", r"Apple 芯片|苹果芯片"), ("notar", r"公证"), ("raw", r"RAW|冲洗"), ("safe", r"不会改动|原片"),
                ("none", r"没有账号|账号"), ("upload", r"上传"), ("lang", r"English|中文，也有")]),
    ("invite", [("try", r"欢迎来试试|来试试|试试"), ("tell", r"都告诉我|告诉我"), ("ai", r"用 ?AI|AI 做"), ("tag", r"自有光彩|每一个瞬间")]),
]
# The chapter about learning: seven pages, in the order of docs/marketing/script-learn.md.
LEARN = [
    ("why", [("filter", r"一键滤镜"), ("xiaoyang", r"张小样|摄影博主"), ("inapp", r"放进了? ?App|放进"), ("own", r"你自己的照片"),
             ("anim", r"看动画"), ("drag", r"拖一拖"), ("quiz", r"小问题")]),
    ("read", [("q1", r"小山"), ("p1", r"小格子|柱子"), ("q2", r"提亮暗部"), ("p2", r"五段|最暗部"), ("q3", r"一片白"), ("p3", r"纯白")]),
    ("light", [("q1", r"爆"), ("p1", r"多进了一倍|曝光，像"), ("q2", r"高光、阴影|高光，阴影"), ("p2", r"亮起来|拖一拖"), ("q3", r"曲线"), ("p3", r"S 形|横着是原来")]),
    ("color", [("q1", r"总是发黄|发黄"), ("p1", r"光本身|烛光"), ("q2", r"中性灰|点一个"), ("p2", r"RGB 立方体|灰色的那根轴"), ("q3", r"更蓝"), ("p3", r"HSL")]),
    ("shoot", [("q1", r"ƒ ?/ ?4|光圈小"), ("p1", r"除数|开口的直径"), ("q2", r"有的糊"), ("p2", r"玻璃板|纵深"), ("q3", r"2 倍|5 倍"), ("p3", r"楔形|焦距越长")]),
    ("video", [("q1", r"快门，不能|越快越好"), ("p1", r"拖影|五十分之一"), ("q2", r"灰蒙蒙"), ("p2", r"转换 LUT|装进了同一个文件")]),
    ("lessons", [("count", r"十三课|13 ?课"), ("three3d", r"3D"), ("levels", r"初级"), ("mine", r"只记在你的|记在你的 Mac"), ("coach", r"读你的这张照片|偏色"), ("offer", r"从来不催|右键")]),
]

CHAPTERS = {"story": STORY, "learn": LEARN}
BOARDS = STORY + LEARN
MAX_SPAN = 90.0           # seconds: an element you only say much later than the board's first word is not drawn then

from pathlib import Path
from html import escape
import base64
import io
import json
from PIL import Image, ImageCms
import numpy as np

ROOT = Path(__file__).resolve().parent


def luminance(rgb):
    a = np.asarray(rgb, dtype=float)
    a = np.where(a <= .04045, a / 12.92, ((a + .055) / 1.055) ** 2.4)
    return float(np.dot(a, [.2126, .7152, .0722]))


def ratio(fg, bg):
    a, b = sorted([luminance(fg), luminance(bg)])
    return (b + .05) / (a + .05)


samples = [
    ('parameter', '03-basic-expanded.png', (2240, 780, 2315, 812)),
    ('project', '01-browse-current.png', (30, 340, 437, 390)),
    ('duration', '04-learn.png', (2796, 396, 2857, 420)),
    ('lesson-help', '05-lesson.png', (1455, 344, 1905, 375)),
    ('metadata', '08-system-light-info.png', (2240, 500, 2340, 532)),
    ('preset', '14-simple.png', (2440, 503, 2517, 529)),
]
measurements = []
for name, filename, box in samples:
    im = Image.open(ROOT / 'screenshots' / filename)
    icc = im.info.get('icc_profile')
    if icc:
        im = ImageCms.profileToProfile(im, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                                      ImageCms.createProfile('sRGB'), outputMode='RGB')
    else:
        im = im.convert('RGB')
    a = np.array(im.crop(box)).reshape(-1, 3) / 255
    levels = a @ np.array([.2126, .7152, .0722])
    bg = np.median(a[levels <= np.quantile(levels, .35)], axis=0)
    fg = np.median(a[levels >= np.quantile(levels, .98)], axis=0)
    measurements.append(dict(id=name, screenshot=filename, bounds_px=box,
                             foreground_srgb=np.round(fg * 255).astype(int).tolist(),
                             background_srgb=np.round(bg * 255).astype(int).tolist(),
                             approximate_ratio=round(ratio(fg, bg), 2),
                             method='ICC to sRGB; median of brightest 2% and darkest 35%; raster estimate only'))
measurements += [
    dict(id='transport', foreground_srgb=[255, 255, 255], background_srgb=[210, 210, 210],
         approximate_ratio=round(ratio(np.ones(3), np.array([210]*3)/255), 2),
         screenshot='12-system-dark-audio.png', bounds_px=[615,1318,673,1377], method='representative solid colors in screenshot'),
    dict(id='export', foreground_srgb=[255,255,255], background_srgb=[106,153,206],
         approximate_ratio=round(ratio(np.ones(3),np.array([106,153,206])/255),2),
         screenshot='15-photo-export.png', bounds_px=[560,474,669,519], method='representative colors; system-drawn control, approximate'),
]
(ROOT / 'contrast-samples.json').write_text(json.dumps(measurements, ensure_ascii=False, indent=2) + '\n')


def figure(name, caption):
    path = ROOT / 'details' / (name + '.png')
    data = base64.b64encode(path.read_bytes()).decode()
    return f'<figure><img src="data:image/png;base64,{data}" alt="{escape(caption)}"><figcaption>{escape(caption)}</figcaption></figure>'


def code(path, line):
    return f'<code>{escape(path)}:{line}</code>'


issues = [
    dict(id='F01', priority='P1', title='播放工具栏：浅灰按钮上的白色图标不够清楚',
         scope='视频 / Live Photo → 播放控制区；上一帧、播放、下一帧、范围缩放、静音按钮',
         evidence='transport', caption='截图 12 局部：多个可用按钮为浅灰底、白色图标，图标边界和按钮底色接近。',
         observation='按钮本身很亮，但图标与按钮颜色接近。当前状态中这些按钮可操作，并非置灰的撤销 / 重做按钮。代表色约为白色 / #D2D2D2，估算对比度约 1.51:1。',
         cause='IconButton 在标签内部显式指定 .primary；深色环境下它会偏白，而 .glassButton(.circle) 实际绘制的按钮底色是浅色。前景与控件表面的配对失效。',
         locations=[('Sources/MediaWorkbenchApp/WorkbenchUI.swift',217),('Sources/MediaWorkbenchApp/WorkbenchUI.swift',283),('Sources/MediaWorkbenchApp/MediaTimeline.swift',65)],
         fix='优先让系统按钮样式决定普通图标的前景色；如果需要自绘，明确区分“浅色按钮上的图标”和“深色面板上的图标”。活动状态也必须重新配对，不能只换 accent。',
         acceptance='正常、悬停、按下、活动状态都能认出每个图标；以图标和实际按钮底色至少 3:1 为设计目标。深色和浅色系统环境均复测。'),
    dict(id='F02', priority='P1', title='调色、构图、声音与信息：关键字段名称被压得过暗',
         scope='简单 / 完整调色、构图的角度与位置、声音的音量、信息面板的拍摄字段',
         evidence='parameters', caption='截图 03 局部：右侧数值清晰，左侧“曝光、亮度、对比度”等名称明显更暗。',
         observation='默认值状态下，参数名接近面板背景；信息面板也出现“字段值很亮、字段名偏暗”的同类现象。参数样本约 3.32:1，信息字段样本约 3.38:1，均属于截图估算。',
         cause='ParameterRow 根据 value == neutral 把字段名称切到 .secondary；这会把“尚未修改”视觉上做得接近“不可用”。InfoPanel.row 同样使用 .secondary；单位使用 .tertiary 后更弱。',
         locations=[('Sources/MediaWorkbenchApp/WorkbenchUI.swift',72),('Sources/MediaWorkbenchApp/WorkbenchUI.swift',88),('Sources/MediaWorkbenchApp/InspectorView.swift',674)],
         fix='关键参数名和拍摄字段名采用可读性有保证的文字颜色，保留层级但提高亮度；修改状态另用标记或字重表达。EV、°、% 也属于有意义信息，不宜只当装饰淡化。',
         acceptance='不必先拖动滑块就能读懂参数名。默认值、修改值及禁用状态分别复测；普通可用文字以至少 4.5:1 为设计目标。'),
    dict(id='F03', priority='P2', title='预设与未选中标签：可点击内容看起来像不可用',
         scope='调色预设名称、“存为预设”“匹配色调”；检查器标签、简单 / 完整及示波器切换项',
         evidence='presets', caption='截图 14 局部：未选中的预设名称和添加、匹配入口偏暗。',
         observation='当前选中的“原图”清楚，其他可用的预设名称普遍偏暗；“AI 调色”样本约 3.34:1。顶部未选中分段标签有相似视觉表现，但未对每个标签单独量测。',
         cause='预设名称 selected ? .primary : .secondary；分段控件的非选中项也落到 Color.secondary。未选中与禁用的层级距离不足。',
         locations=[('Sources/MediaWorkbenchApp/InspectorView.swift',338),('Sources/MediaWorkbenchApp/InspectorView.swift',298),('Sources/MediaWorkbenchApp/GlassSegmentedControl.swift',54)],
         fix='提高可用但未选中内容的文字亮度；用底色、描边和字重区分选中项。禁用项再单独降低对比，避免三种状态混在一起。',
         acceptance='未悬停时即可读出全部可用预设与标签；选中态仍能辨认；对每类普通文字检查 4.5:1 目标。'),
    dict(id='F04', priority='P2', title='学习内容：分组、时长与提示文字过淡',
         scope='学习 → 互动课列表；课程弹窗首步的示例照片提示',
         evidence='lessons', caption='截图 04 局部：分组标题和课程时长比课程主标题弱很多，部分说明也偏暗。',
         observation='“看懂一张照片”“调整明暗”等分组和“1 分钟 / 3 分钟”难读，时长样本约 2.28:1。弹窗中“打开一张自己的照片再上课…”提示约 2.33:1。这类内容仍需用户阅读。',
         cause='列表分组和时长使用 .tertiary；课程示例提示也使用 .tertiary。相同用法还出现在学习建议的原因解释中，后者属于源码排查范围，未展开全部建议逐项复现。',
         locations=[('Sources/MediaWorkbenchApp/LearnViews.swift',397),('Sources/MediaWorkbenchApp/LearnViews.swift',408),('Sources/MediaWorkbenchApp/LessonPlayer.swift',71),('Sources/MediaWorkbenchApp/LearnViews.swift',188)],
         fix='学习说明保持比主标题稍弱，但不低到接近背景；分组标题可通过字重和间距建立层级，时长保持足够亮度。',
         acceptance='课程列表全部可读；课程弹窗提示和展开的建议原因以普通文字 4.5:1 为目标复测。'),
    dict(id='F05', priority='P2', title='项目空状态：解释用途的文字几乎融入侧栏',
         scope='素材库左侧 → 尚无项目时的项目介绍',
         evidence='project-help', caption='截图 01 局部：项目用途说明是本次最暗的一组连续文字之一。',
         observation='“为一次旅行、一篇帖子或一组客片建一个项目…”是解释功能用途的完整句子，却呈现为很暗的小字；截图样本约 2.36:1。',
         cause='ProjectSidebar 将完整说明设为 .caption + .tertiary；半透明侧栏和墙纸色调使实际背景并非固定纯黑。',
         locations=[('Sources/MediaWorkbenchApp/ProjectViews.swift',26)],
         fix='把用途说明提升到可读的辅助正文层级，避免用三级弱化样式承载首次使用说明；必要时加宽行距，而不是继续降低文字亮度。',
         acceptance='首次进入无需放大就能读懂项目用途；侧栏激活、失焦及不同墙纸背景下复测，普通文字目标至少 4.5:1。'),
    dict(id='F06', priority='P2', title='强调色按钮：白字和较亮的底色仍偏接近',
         scope='导出弹窗 JPEG / 保存到选择项、底部主要按钮；课程的下一步等同类控件',
         evidence='export-controls', caption='截图 15 局部：JPEG 为白字配较亮的强调色底。',
         observation='JPEG 选择项代表色约为白色 / #6A99CE，截图估算约 2.97:1。虽然比浅底白图标好，仍不利于小字号文字。系统绘制控件有特殊适用条件，此项列为可读性改进，不据此单独宣告 WCAG 违规。',
         cause='WorkbenchTheme.accent 从系统强调色派生，在启动时固定取值；SheetContent 将它用于各类系统控件，实际可见表面还会受系统样式影响。',
         locations=[('Sources/MediaWorkbenchApp/WorkbenchUI.swift',9),('Sources/MediaWorkbenchApp/WorkbenchUI.swift',263),('Sources/MediaWorkbenchApp/Sheets.swift',10),('Sources/MediaWorkbenchApp/Sheets.swift',152)],
         fix='验证强调色与系统选定的文字色是否配对。对自行控制颜色的按钮定义 onAccent；若保留白字，确保底色足够深。系统管理的控件应优先保持平台自适应，避免直接覆盖其前景。',
         acceptance='在多种系统强调色下检查按钮和选中项；自行控制的普通按钮文字以 4.5:1 为目标，系统控件需单独确认实际状态和平台行为。'),
]

rows = ''.join(f'<tr><td><a href="#{i["id"]}">{i["id"]}</a></td><td><span class="badge {i["priority"].lower()}">{i["priority"]}</span></td><td>{i["title"]}</td></tr>' for i in issues)
sections = ''
for i in issues:
    locations = ' · '.join(code(p, n) for p, n in i['locations'])
    supporting = ''
    if i['id'] == 'F02':
        supporting = '<details><summary>补充截图：信息字段和构图标签</summary>' + figure('metadata', '截图 08 局部：信息字段名称和数值的亮度差异。') + figure('geometry', '截图 09 局部：参数名偏暗，浅底黑字的旋转按钮清楚。') + '</details>'
    if i['id'] == 'F04':
        supporting = '<details><summary>补充截图：课程提示</summary>' + figure('lesson-help', '截图 05 局部：示例照片提示文字偏暗。') + '</details>'
    sections += f'''<article id="{i['id']}" class="finding">
      <div class="finding-head"><span class="badge {i['priority'].lower()}">{i['priority']}</span><span class="eyebrow">{i['id']} · 实际界面已观察</span></div>
      <h2>{i['title']}</h2><p class="scope">{i['scope']}</p>
      <div class="finding-grid"><div>{figure(i['evidence'], i['caption'])}</div><div>
      <h3>看到的现象</h3><p>{i['observation']}</p><h3>对应实现与可能原因</h3><p>{i['cause']}</p>
      <h3>建议调整</h3><p>{i['fix']}</p><h3>修正后验收</h3><p>{i['acceptance']}</p></div></div>
      {supporting}<details><summary>代码定位</summary><p class="locations">{locations}</p></details></article>'''

coverage = [
    ('01','素材库 / 项目空状态','需调整','项目说明偏暗；文件名和缩略图徽标清楚。','01-browse-current.png'),
    ('02','编辑 → 完整调色 / 基础参数','需优先调整','参数名称偏暗，数值基本清楚。','03-basic-expanded.png'),
    ('03','视频 / Live Photo 播放工具栏','需优先调整','浅灰底白图标，多个可用按钮辨认困难。','12-system-dark-audio.png'),
    ('04','普通照片 → 简单调色 / 预设 / 局部调整入口','需调整','预设名称与参数名偏暗；浅底黑字的局部工具按钮清楚。','14-simple.png'),
    ('05','构图面板','需调整','角度、保留范围和位置标签偏暗；旋转按钮清楚。','09-geometry.png'),
    ('06','声音面板','需调整','音量名称与单位偏暗；添加音乐按钮清楚。','10-audio.png'),
    ('07','信息面板','需调整','字段名偏暗，字段值清楚。未在报告展示位置区域。','08-system-light-info.png'),
    ('08','学习面板 / 课程弹窗首步','需调整','分组、时长、辅助提示偏暗；主标题及正文较清楚。','04-learn.png / 05-lesson.png'),
    ('09','导出弹窗（视频 / 照片）','部分需调整','正文基本清楚；强调色选中项的小字对比仍需改善。','06-export.png / 15-photo-export.png'),
    ('10','历史记录浮层','抽查基本清楚','标题和当前行清楚；仅有原图记录，未测试多步及重做行。','17-history.png'),
    ('11','系统浅色 / 深色切换','已验证主界面仍为深色','浅色系统下抽查学习、信息和导出；深色下抽查声音及调色。随后恢复“自动”。','07-system-light-learn.png / 11-system-light-export.png / 12-system-dark-audio.png'),
    ('12','从照片导入','覆盖受限','本轮两次观察均停留在加载指示器；不接受为已完成界面，不推断网格或预览的颜色。','16-photos-import.png（加载态，排除）'),
]
coverage_rows = ''.join(f'<tr><td>{n}</td><td>{title}</td><td>{status}</td><td>{note}<small>{file}</small></td></tr>' for n,title,status,note,file in coverage)

html = '''<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lucet 光集 · 文字与背景对比检查报告</title><style>
:root{--ink:#20211e;--muted:#61635d;--line:#e5e6df;--accent:#49624d;--warm:#8b4d2b;--soft:#f7f8f4}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#fff;color:var(--ink);font:16px/1.85 -apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif}a{color:var(--accent);text-underline-offset:4px}header,main,footer{width:min(1180px,calc(100% - 64px));margin:auto}header{padding:64px 0 40px;border-bottom:1px solid var(--line)}.eyebrow{font-size:12px;letter-spacing:.09em;font-weight:600;color:var(--muted)}h1{font-size:clamp(30px,4vw,48px);line-height:1.3;letter-spacing:-.035em;margin:20px 0}h2{font-size:26px;line-height:1.5;letter-spacing:-.02em;margin:13px 0}h3{font-size:15px;line-height:1.6;margin:24px 0 5px}p{margin:0 0 16px}.intro{font-size:19px;max-width:890px}.meta{font-size:13px;color:var(--muted)}.stats{display:grid;grid-template-columns:repeat(4,1fr);border-top:1px solid var(--line);margin-top:30px;padding-top:24px;gap:25px}.stat b{display:block;font-size:35px;font-weight:550;line-height:1.3}.stat span{font-size:13px;color:var(--muted)}nav{display:flex;gap:25px;flex-wrap:wrap;margin-top:28px;font-size:14px}.section{padding:46px 0;border-bottom:1px solid var(--line)}.callout{border-left:3px solid var(--accent);padding:16px 22px;background:var(--soft);margin:22px 0}.callout p:last-child{margin:0}.badge{display:inline-block;font-size:12px;line-height:1.8;padding:2px 9px;border:1px solid;border-radius:5px;font-weight:650}.p1{color:#8b3c2c;border-color:#e2c3b9;background:#fbf1ec}.p2{color:#765d29;border-color:#ddd0ae;background:#fbf7ec}.risk{color:#52604f;border-color:#cbd6c6;background:#f4f7f1}.finding{padding:48px 0;border-bottom:1px solid var(--line);scroll-margin-top:15px}.finding-head{display:flex;align-items:center;gap:12px}.scope{color:var(--muted);font-size:14px}.finding-grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:40px;align-items:start;margin-top:24px}.finding-grid h3:first-child{margin-top:0}figure{margin:0}figure img{width:100%;height:auto;border-radius:8px;display:block;border:1px solid #deded8}figcaption{font-size:12px;color:var(--muted);line-height:1.7;margin-top:10px}details{margin-top:24px;padding:12px 16px;background:var(--soft);border-radius:6px}summary{cursor:pointer;font-size:14px;font-weight:550}.locations{font-size:12px;line-height:2.1;margin-top:12px;overflow-wrap:anywhere}code{font:12px/1.7 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f3f4ef;padding:2px 4px;border-radius:3px}table{border-collapse:collapse;width:100%;font-size:14px;margin:24px 0}th,td{text-align:left;vertical-align:top;border-bottom:1px solid var(--line);padding:12px 13px}th{font-size:12px;font-weight:650;color:var(--muted);background:var(--soft)}td:first-child{white-space:nowrap}small{display:block;color:var(--muted);font-size:11px;overflow-wrap:anywhere;margin-top:6px}.scroll{overflow-x:auto}ul,ol{padding-left:22px}li{padding:4px 0}.two-col{display:grid;grid-template-columns:1fr 1fr;gap:35px}.good{color:var(--accent)}footer{padding:32px 0 70px;font-size:12px;color:var(--muted)}.print-button{border:1px solid #c9cdc3;border-radius:5px;background:#fff;padding:8px 14px;color:var(--ink);cursor:pointer;font:inherit;font-size:13px}button:focus-visible,a:focus-visible,summary:focus-visible{outline:2px solid #49624d;outline-offset:4px}@media(max-width:800px){header,main,footer{width:calc(100% - 36px)}header{padding-top:35px}.finding-grid,.two-col{grid-template-columns:1fr;gap:25px}.stats{grid-template-columns:repeat(2,1fr)}h2{font-size:22px}td,th{padding:10px 8px}.finding{padding:32px 0}}@media print{header,main,footer{width:100%}header{padding-top:0}.print-button,nav{display:none}body{font-size:11px}.finding{break-before:page}.finding-grid{gap:24px}h2{font-size:20px}figure,table{break-inside:avoid}details{display:block}a{color:inherit}img{max-height:700px;object-fit:contain;object-position:top}}
</style></head><body>
<header><div class="eyebrow">LUCET · APPEARANCE REVIEW · 2026-10-18</div>
<h1>文字与背景对比检查报告</h1><p class="intro">已确认浅底白图标、深底暗灰字等可读性问题。先修复公共控件与文字层级，再回归检查各个页面。</p>
<p class="meta">对象：Lucet 光集 macOS 原生 APP · 运行环境：macOS 27.0.1 · 中文界面 · 本轮只检查和记录</p>
<div class="stats"><div class="stat"><b>6</b><span>已观察的问题类别</span></div><div class="stat"><b>2</b><span>P1 优先调整</span></div><div class="stat"><b>4</b><span>P2 后续调整</span></div><div class="stat"><b>2</b><span>待验证 / 设计前提</span></div></div>
<nav><a href="#overview">结论与范围</a><a href="#findings">调整清单</a><a href="#risks">黑字与主题风险</a><a href="#coverage">检查覆盖</a><a href="#handoff">修正与验收顺序</a><button class="print-button" onclick="window.print()">打印 / 保存为 PDF</button></nav></header>
<main><section id="overview" class="section"><h2>当前结论</h2>
<p>问题主要来自前景色与实际控件背景未配对，以及过度使用 <code>.secondary</code>、<code>.tertiary</code>。数值和主标题多数清楚，但参数名称、预设名称和解释文字明显偏暗；浅灰色播放按钮则反过来出现白色图标不清楚的问题。</p>
<div class="callout"><p><strong>关于你提到的“深色背景里用了黑字”：</strong>本轮实际操作中没有稳定复现纯黑文字落在深底上的完整案例。已确认的是接近背景的暗灰文字。源码中明确的黑字用法主要与浅色表面配对，不能一律改成白字。另有历史截图脚本记录过“检查器文字捕获为近黑”的现象，需与真实显示分开核对，详见下方 R02。</p></div>
<div class="two-col"><div><h3>本轮实际检查</h3><p>素材库、项目空状态、视频 / Live Photo 编辑、普通照片编辑、简单与完整调色、构图、声音、信息、学习、课程首步、照片 / 视频导出和历史浮层。切换系统浅色与深色外观后抽查，再恢复原来的“自动”。</p></div><div><h3>当前主题前提</h3><p>主窗口在 <code>MediaWorkbenchApp.swift:22</code> 固定 <code>.preferredColorScheme(.dark)</code>。系统浅色不等于 APP 有完整浅色主题；本轮仍检查了 APP 中的浅色按钮、选中表面以及浅色系统下的弹窗。</p></div></div>
<h3>评估基准与证据限制</h3><p>以普通文字 4.5:1、必要图标 3:1 为可读性设计目标，参考 <a href="https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html">W3C 文字对比度说明</a>及 <a href="https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html">非文字对比度说明</a>。禁用控件、装饰内容与系统完全管理的控件需考虑适用例外；本报告不代表完整无障碍合规认证。</p>
<p>下方数值来自本轮截图的近似采样，已转换到 sRGB；玻璃材质、系统色调、抗锯齿及截图压缩都会影响像素值。它们用于排优先级，不能代替修正时读取最终解析颜色的正式测量。采样方法、坐标和原始估算保存在 <code>contrast-samples.json</code>。</p></section>
<section id="findings" class="section"><h2>需要调整的清单</h2><p>P1：优先解决影响核心操作辨认的问题。P2：持续改善辅助信息和状态层级。</p><div class="scroll"><table><thead><tr><th>编号</th><th>优先级</th><th>问题</th></tr></thead><tbody>''' + rows + '''</tbody></table></div></section>
''' + sections + '''
<section id="risks" class="section"><h2>黑字与主题：两项需要单独跟进</h2>
<h3><span class="badge risk">R01</span> 尚无完整浅色主题，移除强制深色前必须成套定义颜色</h3>
<p>源码层面已确认：<code>WorkbenchUI.swift:21–30</code> 的 panel、canvas、selection、star 和 hairline 基本为固定深色或白色透明色；主窗口强制深色，因此当前系统浅色下仍保持深色不是配色故障。如果以后支持浅色主题，仅移除强制深色可能使系统黑字落到固定深底。应一起定义面板、画布、主 / 辅助文字、选中表面及其文字、强调色及其文字。</p>
<h3><span class="badge risk">R02</span> “近黑字”还可能发生在捕获路径，需区分真实窗口与生成截图</h3>
<p><code>scripts/make-site-screenshots.sh:84–87</code> 记录：某些构建中，窗口捕获无法正确绘制半透明检查器的辅助文字，会把它们捕获成近黑；现有脚本通过单独渲染检查器替换该列。这个注释是调查线索，不是本轮真实界面已复现黑字的证据，也不能证明你看到的现象仅由截图引起。</p>
<p>建议之后对同一页面同时保留原生窗口截图与 DebugSnapshot 输出，比较系统浅色 / 深色、窗口激活 / 失焦、主窗口 / 独立面板的文字解析颜色。不能以替换官网截图作为 APP 配色问题的最终修复。</p>
<h3 class="good">已排除的误改：这些黑字暂时应保留</h3><p><code>LearnViews.swift:125–126</code> 的已选学习主题是黑字配 85% 白色胶囊；<code>LessonScenes.swift:49</code> 会在更亮的灰度格子上选择黑字。前者为源码核对，未在本轮展开对应学习设置截图；后者未逐帧检查全部课程。旋转、局部调整、“自动”等按钮已在实际截图中看到浅底黑字，当前是清楚的。</p>
</section>
<section id="coverage" class="section"><h2>检查步骤与覆盖结果</h2><p>原始截图保存在本目录 <code>screenshots/</code>；报告内的局部图只做裁切，未重新渲染或改色。完整截图可能包含个人照片和拍摄信息，本报告仅在本地保存，未发布到官网或 GitHub。</p>
<div class="scroll"><table><thead><tr><th>步骤</th><th>界面 / 状态</th><th>健康状况</th><th>观察与证据</th></tr></thead><tbody>''' + coverage_rows + '''</tbody></table></div>
<h3>尚未覆盖</h3><p>macOS 15 / 26 的实际表现、英文界面、不同系统强调色、提高对比度 / 降低透明度设置、所有弹窗及错误态、全部课程步骤、并排选片与拼图、完整照片导入网格，以及每个按钮的按下 / 悬停 / 禁用状态。局部调整只检查了入口，没有创建图层或改动照片；学习建议没有逐条展开。</p>
<h3>版本说明</h3><p>代码基线：<code>improve-workbench · 64c6336178e704c16a8a5ce9762fb96b7a458c25</code>。实际操作对象：<code>.build/MediaWorkbench.app</code> 的运行窗口。该应用可执行文件修改时间为 2026-10-18 00:38（本机显示）；本轮没有重新构建，也未证明二进制与当前提交逐字对应。代码定位用于后续修正，实施前应在新构建中确认。</p></section>
<section id="handoff" class="section"><h2>建议的修正与验收顺序</h2>
<ol><li><strong>先修公共 IconButton。</strong>对照 F01，将按钮表面与图标前景成对处理，回归播放、静音和缩放等复用位置。</li><li><strong>再修可用文字的最低对比度。</strong>对照 F02 / F03，先保证参数名、单位、预设名和可用标签能读，再建立选中 / 修改 / 禁用层级。</li><li><strong>统一辅助正文。</strong>对照 F04 / F05，把说明、分组、时长从过淡的三级样式提升到足够清楚的层级。</li><li><strong>核对强调色组合与真实捕获。</strong>对照 F06 / R02，覆盖系统强调色与系统控件例外；同时比对真实截图和 DebugSnapshot。</li></ol>
<div class="callout"><p><strong>本轮交付状态：</strong>检查报告、原始截图、局部证据图和采样数据已保存；APP 源码未修改。系统外观已恢复为检查前的“自动”。</p></div>
</section></main><footer>Lucet 光集 · 本地检查报告 · 2026-10-18<br>报告中的截图均为本轮原生界面捕获；代码分析与尚未复现的风险已分别标注。</footer></body></html>'''
(ROOT / 'index.html').write_text(html, encoding='utf-8')
print(f'Report generated: {ROOT / "index.html"}')
print(f'{len(issues)} observed issue categories; {len(coverage)} inspection steps; {len(measurements)} approximate samples.')

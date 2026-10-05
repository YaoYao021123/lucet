# Mac 原生素材工作台 · UI 视觉方案

日期：2026-10-02。使用内置 Image Gen 生成，按顺序独立绘制。以下编号对应聊天中三张生成图的展示顺序。图片为设计概念，尚非已运行的应用。

## 方案 1 · 静谧素材桌面

[原图](./option-1.png)

最终绘图提示：

```text
Use case: ui-mockup.
Create one realistic, exceptionally polished production-quality desktop macOS native application UI design for the Chinese user's media browser/editor. Concept name: 静谧素材桌面. This is one independent design direction and one complete app screen, not a presentation, collage, marketing landing page, or multiple options in a single picture.
Target dimensions: 1440 x 1024 pixels, landscape natural desktop viewport. Current date anchor 2026-10-02; if visible dates are needed use 2026年10月2日. Prefer not to show dates.
Product brief: native Mac app browsing media on iPhone, DJI Pocket Micro SD, local SSD; photos, videos and Apple Live Photos together; HDR preview; favorites; one logical asset may have two file locations; non-destructive color grading and .cube LUT; multi-select to apply chosen grading parameters across photos/video/Live; trim video and choose keyframe to create Live Photo; learn photography through small contextual explanations tied to actual edits. Design a focused editing screen, with these other flows available through sparse navigation rather than a feature inventory.
Visual system: pure white base background, warm charcoal text, restrained olive-green accent #65734b, hairline neutral dividers, virtually no shadows, elegant macOS SF Pro / PingFang-like sans-serif typography, readable Chinese product text. No emoji, no electric blue or purple UI, no gradients, no glassmorphism, no huge rounded cards, no nested cards. Crisp thin native outline icons (favorites star, grid, folder, play, sliders); understated native window controls. UI should feel calm like Picview and organized like Lightroom, but its own design.
Layout direction: lightweight contextual editor with very generous photograph space. A narrow left sidebar approximately 185px contains 收藏, 全部素材 and source items iPhone, Micro SD, 本地素材. Main area has understated top toolbar filename 海边散步.mov plus small 视频, HDR and 2个位置 status. Large central photographic canvas showing a REAL photorealistic cinematic coastal scene in soft late-afternoon light, shoreline, a small distant person, natural earthy/sea colors; this is actual media imagery, not vector placeholder art. Tasteful neutral backing only in canvas.
A narrow right inspector about 245px shows a compact real histogram (not a dashboard chart), sections 光线 and 色彩, clear fine sliders 曝光 +0.3, 高光 -25, 阴影 +15, 色温 +8 and 风格 LUT 自然暖调 with 强度 35%. Group by spacing and dividers, no each-parameter card. One subtle contextual note beneath 高光 reads '高光：调整画面中较明亮的区域', not a giant tutorial panel. Keep text minimal and precisely aligned.
Bottom: thin video timeline under canvas with trimmed 3-second selection around 00:12–00:15 and a keyframe marker, then low horizontal filmstrip with 6 beautiful actual photograph/video thumbnails including a still, short video, Live; three checked thumbnails selected, a concise label 已选3项. Primary action olive button 应用到所选, secondary text action 导出 Live Photo. Do not add explanatory arrows or outside annotation. Include unobtrusive A/B comparison toggle near canvas. One clear primary action.
Composition and fidelity: full app interface fills image edge to edge, no monitor/device mockup, no perspective or tilted frame, no external title or option number, no brand watermark. Correct padding, professional hierarchy, readable 14–16px body text at designed viewport, strong image quality, comfortable whitespace, all content fits and no clipping. Make this look like a screenshot of a beautifully engineered real app.
```

## 方案 2 · 专业调色台

[原图](./option-2.png)

最终绘图提示：

```text
Use case: ui-mockup.
Create one independent, realistic high-fidelity native macOS desktop photo/video/Live Photo editor UI concept named 专业调色台. One complete focused app screen ONLY, one design direction, no collage and no external labels or option numbers.
Target dimensions: 1440 x 1024 pixels, natural landscape desktop frame. Current date anchor 2026-10-02; avoid unnecessary visible dates. This is a Chinese-language native Mac product for local iPhone, DJI Pocket/Micro SD and SSD media, with HDR preview, favorites, multi-location media identity, color grading/.cube LUT, batch application across photos/videos/Live, video trimming and keyframe selection to create Live Photo, contextual photography learning. Focus this frame on precise video grading and Live Photo creation; other workflows live off-screen.
Create realistic production-quality UI with clear hierarchy, strong readable typography, intentional REAL photographic imagery and purposeful spacing. Feel as professionally organized as Lightroom, as restrained and elegant as a premium native Mac app. Avoid feature inventory, excessive panels, cards, nested cards, metrics, flashy tabs or badges.
Visual system: pure BLACK main UI background #000000 with sparse charcoal separators and charcoal-black control surfaces. Warm off-white text, muted grey secondary text, subdued warm amber #bfaa79 used sparingly for selection and one primary action. No electric blue/purple UI, no colored gradients, no glow, no glass panels, no 3D render, no emoji. Compact SF Pro/PingFang sans-serif typography, body around 14–16px in intended viewport. Thin native vector-like outline icons. Light native traffic controls only at far top-left; no device/monitor/browser framing.
Distinct layout: reduced left source rail about 165px; very large central canvas; right precision edit inspector about 280px; video timeline stretching central area only; filmstrip at bottom spanning canvas with clear media selection. The app is an editor tool, no marketing banner.
Top native toolbar: app name 光集, navigation 浏览 / 编辑 with 编辑 selected, filename DJI_0142.MOV. Display concise source information 'Micro SD · 2个位置' and '输入 D-Log M' beside filename. Do NOT label this Rec.709 preview as HDR. The app supports HDR in general but this selected source is D-Log M converted to Rec.709. Canvas small status 'Rec.709 预览'.
Canvas content: beautiful photorealistic wide cinematic mountain lake landscape recorded on DJI Pocket in golden late afternoon, distant forest mountain ridges and still water; strong composition and realistic detail. Central image uses most of the main area. Tiny '原片 / 调色' A/B controls, not a big comparison collage. No infographic arrows.
Left rail: source icon/name rows iPhone, Micro SD selected, 本地素材; below short rows 收藏 and 历史, not dozens of categories. Place a concise source state dot next to Micro SD.
Right inspector hierarchy: top a restrained realistic luminance/RGB histogram in 90px height, then labels 色彩管理 with dropdown 'D-Log M → Rec.709', 光线 with exposure +0.2, highlights -18 and shadows +12 sliders, 色彩 with 白平衡 and 饱和度, 风格 with creative LUT '暖调电影' and intensity 30%. Every line feels deliberate, uncluttered and aligned. One small outlined info icon beside each section, and a quiet contextual help link '为什么先做色彩还原？'. Do not place a chat assistant panel or giant lesson card here.
Under image: transport bar with play, time 00:12.0 / 00:38.4; robust video thumbnail timeline with one selected range labeled 12.0—15.0秒, start/end handles, a keyframe marker labeled 封面 13.4秒 and clearly indicated sound toggle. No fake random repeated numbers.
Filmstrip below has 5 actual visual thumbnails of this photo trip: video lake, a still photo of forest, a Live Photo water ripple, and two other related photographs. Three selected thumbnails have quiet amber border/checks, status 已选3项. Secondary action '同步调色…' enables batch application. The single primary amber button '生成 Live Photo' is beside a compact output option '兼容优先 · SDR'. Preserve non-destructive original concept with subtle bottom text 原件保留.
Full app fills output edge to edge. All labels in precise Chinese, real recognizable sliders and controls, readable proportions, no clipped panels, no web landing page hero or sidebar dashboards, no outside shadows or watermark. This is static concept imagery, not proof of actual HDR rendering or live device access.
```

## 方案 3 · 摄影学习工作台

[原图](./option-3.png)

最终绘图提示：

```text
Create one independent realistic production-quality Chinese macOS native media editor UI mockup, concept 摄影学习工作台. One complete screen only, no collage, presentation title or option number. 1440 x 1024 landscape target. Date anchor 2026-10-02; no dates needed. Pure white background, charcoal Chinese sans-serif typography, restrained terracotta accents, olive selections, subtle hairline dividers. Native thin outline icons, no emoji, no blue/purple theme, no gradients, no nested cards, no monitor mockup.
Product: Mac browser/editor for photos, video and Live Photos from iPhone, Micro SD and local storage. Favorites, HDR support, multi-location identity, color grading/LUT, mixed batch editing, video to Live Photo, contextual photography education. Focus this one screen on learning while editing your own photograph, other functions available in sparse navigation.
Top toolbar: macOS window controls, app name 光集, 浏览 / 编辑, selected filename 午后窗边.HEIC, source iPhone · 2个位置, favorite star and quiet 导出 action.
LEFT rail 245px: heading 边修边学, subtle enabled switch. Goal 保留窗外层次，让主体更清楚. Three restrained step rows: 理解高光 (active), 观察阴影, 对比并保留. Short explanation 高光主要影响较明亮的区域。 Then 先调整高光，再观察窗边层次。 Below a separated recorded 拍摄信息 block f/1.8 · 1/250秒 · ISO 100 and link 这些参数意味着什么？ These metadata are read-only, not editing sliders. Keep text short.
CENTER large photorealistic lifestyle photograph of an adult woman seated next to a sunlit cafe window, wood table, leafy courtyard outside. A precise vertical before/after comparison divider: same scene and framing both sides, left subtly darker subject and brighter highlights, right gently balanced natural edit, no new scene elements. Small 原片 / 当前调整 labels. Beautiful real photography, no placeholder art, no arrows. Image dominates screen.
RIGHT 265px: compact realistic histogram, grouped light and color editing sliders. 光线: 曝光 +0.2, 高光 -20, 阴影 +12. Only 高光 row has subtle terracotta marker. 色彩: 色温 +5 (relative HEIC adjustment, not Kelvin), 色偏 0, 饱和度 +4. 风格: LUT 无 with 导入 LUT link. Comfortable spacing and precisely aligned values, Chinese text at readable product sizes.
Below photograph simple edit-history row 原片 → 高光 -20 → 阴影 +12 with undo/redo. BOTTOM filmstrip: 6 beautiful actual mixed media thumbnails (portrait, architecture, coffee video, walking Live Photo, landscape, food), 3 selected with olive checks. Label 已选3项. Small 同步范围：风格与色彩, secondary 应用到所选… action. Single primary terracotta button 保留本次调整. Subtle 原件保留.
Full app fills image edge to edge, native precise proportions, extremely polished hierarchy, generous whitespace, legible short Chinese labels, no clipped content, no marketing hero, no chat transcript, no watermark.
```



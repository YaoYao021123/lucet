# 第 1 版方向 · 界面细化

日期：2026-10-02。用户选择方案 1，要求 i 提示、图标对比，以及苹果“照片”式图库和选择。使用内置 Image Gen，依次生成两张概念图。尚非运行中的应用。

[界面与保存逻辑](selected-direction.html)

## 编辑工作区 v2

输出：selected-editor-v2.png

参考：option-1.png；用户提供的 原片 / 调色 控件截图（归档为 reference-comparison-control.png，仅供识别需要移除的控件）。

精确提示词：

```text
Refine the FIRST reference image as a polished high fidelity native macOS media editor UI screenshot, landscape 16:10. The second reference is ONLY the old text comparison control to replace, NOT a visual style reference. Preserve option 1's calm white and very pale gray interface, muted olive accents, native macOS title bar, source sidebar, large warm coastal sunset photo, right histogram and grading controls, bottom timeline and mixed photo/video/Live filmstrip. No blue or purple accents, no gradients, no emoji. Keep elegant readable Chinese typography, restrained SF Symbols style thin icons.

Required refinements: remove all instructional prose beneath adjustment sliders, and remove any sentence like 为什么要做色彩还原. Put a small unobtrusive circular lowercase i information icon beside the 色彩空间 and 高光 section labels, with no open tooltip. Replace ANY text 原片/调色 segmented toggle and ANY A/B text toggle with ONE compact toolbar comparison icon depicting two offset overlapping thin outline rectangles, no text label on the image, no floating control on the photograph. Place it close to the preview zoom tools. The top toolbar has a clean back-to-grid icon, image name 海岸日落, compact HDR badge, comparison icon, secondary 导出 and primary olive 完成 button. Main edit preview is a SINGLE large coastal sunset photograph, no split-view. Right panel is visually quiet: histogram, small dropdown 色彩空间 自动, LUT 电影暖调 with subtle preset previews, exposure and highlights/shadows/white balance sliders, collapsible curves. Remove inline tutorial cards. Use a clean selection filmstrip with 3 selected photos/video/Live, subtle olive border and small checkmarks; readable lower status 已选 3 项 and compact olive 应用到所选 button. Small LIVE and video duration badges only where needed. The source sidebar contains 图库, 收藏, 最近导入, iPhone, DJI Pocket 3, Micro SD, SSD. Native flat toolbar, subtle separators, plenty of breathing room, no card dashboard. Produce ONE complete full app window screenshot only, no laptop frame, no option captions, no surrounding presentation.
```

## 图库与多选 v1

输出：selected-library-v1.png

参考：本轮 selected-editor-v2.png。

精确提示词：

```text
Create a second screen for the SAME native macOS media application shown in the reference image: its LIBRARY grid and multi-selection view. Preserve the exact white and pale gray surfaces, muted olive accent, thin SF Symbols style monochrome icons, macOS titlebar, Chinese typography, source sidebar, quiet spacing. This is a high fidelity product UI screenshot, landscape 16:10, ONE full application window, no device frame, no presentation title, no extra boards. No blue or purple theme, no gradients, no emoji.

Apple Photos inspired unified library browsing: large clean main grid of photographs and videos and Live Photos, arranged in a coherent 5-column, 3-row grid with small even gutters, no dashboard cards, no drop shadows around thumbnails, no repeated filenames or metadata under every cell. Beautiful varied travel photographs: coastal sunset from reference, Mediterranean streets, olive trees, mountains, cafe portrait, ocean cat, lake, bridge, night city. Organize under one modest heading 旅途精选 and date 2026年10月2日, show believable variety with a coherent Mediterranean travel palette. The left sidebar matches reference: 图库 selected with pale olive highlight, 收藏, 最近导入; devices iPhone, DJI Pocket 3, Micro SD, SSD; media categories 视频, 照片, 实况照片. Native top toolbar shows 图库 on left, subtle grid icon, thumbnail size slider, favorite outline heart, search field 搜索素材, and an overflow icon on right. Media grid is the dominant area, no editing inspector.

Three thumbnails selected: one sunset video, one street photograph, one olive-leaf LIVE photo, each has a fine olive outline and a filled olive circular checkmark at top right. Unselected thumbnails have NO permanent empty checkboxes. Videos show small camera/play glyph and duration bottom right, Live photos show a tiny concentric-circle LIVE badge, ordinary photos have no badge. Keep metadata restrained; no claims that HDR can be demonstrated by this screenshot.

A compact bottom selection action strip with readable 已选 3 项 on left, secondary icon actions 收藏 and 预览, one primary olive 批量调色 button on right. This establishes selecting mixed media and going into the editor. No floating popovers, no how-to prose, no color restoration explanations, no 原片/调色 switch, no grading sliders on the library screen. Crisp visual hierarchy, mostly photographs and generous clean native chrome, plausible production macOS application with restrained controls.
```

## 实现时统一的细节

生成图用于确定视觉方向。编辑图中对比图标出现于两处，原生实现只保留工具栏的一处；媒体类型标识以真实素材资源为准，收藏统一使用同一套符号。i 入口的悬停和点击说明需通过交互实现。


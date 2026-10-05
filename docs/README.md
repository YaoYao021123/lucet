# Mac 原生素材工作台研究

[2026-10-05 最新施工核查](workbench-completion-2026-10-05.html)：16 项基础调色、直方图、构图、草稿 / 快照 / 撤销、多选同步 / 批量另存；46 项测试通过。真实 DJI 4K 的参数、播放、三秒范围移动和快照操作已检查；新增拼图窗口复验时再次锁屏，界面交互尚未验收。

2026-10-03 已确认：当前主线是调色与 Live 制作工作台。AI 打标、选片、口播、完整短片和动画仅记录为后续扩展。

[完整 HTML 方案](mac-media-plan.html) · [来源清单](research-sources.json)

[当前首版范围与技术验证计划](development-readiness.html#current-scope)：核心闭环、真实素材与通过条件。

[画面校正与稳像](development-readiness.html#geometry-stabilization)：首版旋转 / 手动拉直 / 裁切，视频和 Live 稳像独立验证。

[AI 后续扩展记录](ai-tagging-plan.html)：打标 / 选片、完整制作；[资源预算规则](ai-tagging-plan.html#resource-budget)与[动画编排](ai-tagging-plan.html#animation-roadmap)。

[原生控件施工记录](ui-concepts/2026-10-04/native-controls-build-record.json)：已替换系统 Slider、加入独立样板窗口，并修正 SDK 元数据；已完成连续拖动、键盘、输入范围、复位与禁用状态的实机检查，并保存深浅色样板截图；三页概念图已按实机控件参考重绘。真实素材预览帧率尚未测量。

[最新实机控件：深色](ui-concepts/2026-10-04/native-controls-interaction-v3-dark.png) · [浅色](ui-concepts/2026-10-04/native-controls-interaction-v3-light.png)：分段按钮支持点击平滑移动、拖动跟随与松手吸附；普通按钮采用系统 Regular 玻璃样式，操作图标放大为 16 pt。点击及跨段拖动已在样板与主工作台验证。

[主工作台施工效果](ui-concepts/2026-10-04/workbench-controls-v4-color.png) · [窄窗口声音页](ui-concepts/2026-10-04/workbench-controls-v4-narrow-audio.png) · [验证记录](ui-concepts/2026-10-04/workbench-controls-v4-record.json)：统一 LUT / 音乐 / Live 按钮、放大开关、修正标题裁切，时间线工具支持按宽度排成一行或两行；已加载合成视频检查实际操作。

[macOS 原生控件核查](ui-audit/2026-10-04/native-controls-audit.html)：已对照 macOS 27.0.1 实机、Apple HIG 与当前代码；概念图中的滑块头、按钮比例及玻璃使用范围需要修正，组图暂不作为实现规格。

[最新原生控件修订组图](ui-concepts/2026-10-04/mac27-native-workbench-v2.html)：烟灰侧栏、中性参数区与紧凑工具栏；由 Image Gen 参考实机样板逐张重绘调色、Live 制作和素材浏览三页。生成图的文字、控件尺寸仍以实际实现为准。[上一版玻璃材质探索](ui-concepts/2026-10-04/mac27-glass-workbench.html)保留作对比。概念功能与实现现状分开注明。[上一版深色组图](ui-concepts/2026-10-04/mac27-workbench.html)保留作材质对比。此前[UI 概念与保存逻辑](ui-concepts/2026-10-02/selected-direction.html)保留作历史参考。

[研究工作区与核查记录](../_LLM-Wiki/workspaces/2026-10-01-Mac原生素材浏览与编辑方案/首页.md)

以下是截至 2026-10-04 的历史接入摘要（最新状态见上方施工核查）。研究日期：2026-10-01。已接入图片 / 视频 LUT、HDR 浮点图片画布与原生视频预览、片段整体拖动 / 加速 / 封面 / 原声 / BGM、SDR Live 和实验性 SDR 派生 HDR Live；28 项测试、7 个套件通过。获授权的真实 4K 视频已验证官方创意 LUT、6 秒压缩为 3 秒及 SDR / HDR 系统配对，见[真实素材报告与 Pocket 4P LUT](../media-tests/2026-10-04/test-report.html)、[接入结果与使用范围](development-readiness.html#grading-live-implementation)和[运行说明](../README.md)。真实设备读取、相机 Log 转换、原生 HDR 保真编辑、外接 HDR 屏、iPhone 导入、多选与素材管理仍待推进。

[秋日行旅 · 九张混合画面 Live](../media-tests/2026-10-05/nine-live-mixed/index.html)：3 单画面 / 3 双拼 / 3 三拼；18 个镜头，雪景仅 1 张。系统配对与完整解码通过，附成品包和每格配方。

[工作区整理记录](workspace-cleanup-2026-10-05.html)：清理 2.16 GiB 编译缓存，体积从 3.28 降到 1.12 GiB；保留全部媒体、App 与测试记录，附目录用途和后续清理脚本。

[主视觉资产页](../assets/brand/preview.html)：应用图标、转曲字标、深浅色主视觉与海报、空状态插画、SVG 图层及完整资产包，已接入 App 并保存原生窗口截图。

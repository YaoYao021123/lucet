---
title: "output"
kb_topic: "Mac 原生素材管理与编辑"
task_id: "2026-10-01-Mac原生素材浏览与编辑方案"
workspace_path: "/Users/yaoyao/code/project/pic_review_edit/_LLM-Wiki/workspaces/2026-10-01-Mac原生素材浏览与编辑方案"
workspace_home: "/Users/yaoyao/code/project/pic_review_edit/_LLM-Wiki/workspaces/2026-10-01-Mac原生素材浏览与编辑方案/首页.md"
archive_path: "docs/"
template_version: "manual-1"
deliverable_type: "research"
source_path: "docs/research-sources.json"
source_url: ""
source_type: "official-web-and-local-sdk"
workflow_stage: "output"
review_status: "approved"
recommended_folder: "docs/"
recommended_tags: ["macOS", "HDR", "Live Photo"]
source_images: []
published_path: "docs/mac-media-plan.html"
updated_at: "2026-10-01"
---

# 结论

推荐独立原生工程，复用系统框架及授权明确的组件；若接受 GPL 路线，可另评估扩展 FlowVision。

- UI：SwiftUI/AppKit；媒体：AVFoundation、ImageIO/Core Image、Metal/EDR；目录：SQLite/GRDB。
- 多源：Asset → Resource → Location；精确重复关联多个位置；转码/裁剪保留独立版本。
- 首先验证 HDR、SDR Live Photo 导出与 iPhone 按需读取，再做浏览/收藏/比较、LUT 编辑及多源关联。
- AI 提供开发支持、结构化编辑建议和素材理解；确定性处理继续由原生引擎完成。

正式交付：[完整 HTML 方案](../../../docs/mac-media-plan.html) · [来源清单](../../../docs/research-sources.json)。当前交付为方案，非应用。


## 第二轮更新

用户提出 Lightroom 式 UI 与摄影学习，且上一轮已确认混合多选调色。方案更新为浏览/编辑两种状态；新增“目标 → 参数理解 → 试调对比 → 历史复盘 → 批量复用”流程，区分拍摄元数据、后期参数、测量信号和风格建议。仍为研究方案，不是已实现的媒体编辑器。

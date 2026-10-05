---
title: "draft"
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
workflow_stage: "draft"
review_status: "pending"
recommended_folder: "docs/"
recommended_tags: ["macOS", "HDR", "Live Photo"]
source_images: []
published_path: ""
updated_at: "2026-10-01"
---

推荐独立原生工程：SwiftUI/AppKit + AVFoundation + ImageIO/Core Image/Metal + SQLite/GRDB。FlowVision 作为接近需求的验证对象；SimpView 作为 MIT 的交互/PTP 参考。

建立 Asset → Resource → Location 模型；完整哈希用于相同文件；转码副本使用 RelatedGroup。MVP 分成原生浏览、LUT+SDR Live Photo、设备和逻辑合并；AI 辅助排在媒体闭环之后。


## 第二轮草案

浏览保持简洁；编辑使用 Lightroom 式画布、右侧参数、底部素材条与历史。学习围绕当前参数提供简短解释、基于当前素材的可选练习、逐步对比及过程复盘。区分拍摄元数据与后期参数，风格偏好与可测质量信号；保留混合多选、选择性同步和统一风格。静态知识先实现，AI 分析后加入。

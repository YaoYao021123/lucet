---
title: "review"
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
workflow_stage: "review"
review_status: "approved"
recommended_folder: "docs/"
recommended_tags: ["macOS", "HDR", "Live Photo"]
source_images: []
published_path: "docs/mac-media-plan.html"
updated_at: "2026-10-01"
---

# 核查结果

发布决定：approved，仅适用于研究文档自检通过；不代表应用或全部兼容性已通过测试，也不表示用户已经批准实施。

- [来源清单](资料清单.md) 已登记关键官方文档与仓库。FlowVision / SimpView 的功能声明均标注 README 核查与待实测。
- [FlowVision](https://github.com/netdcy/FlowVision) GPL 与旧 ffmpeg-kit 依赖；[FFmpegKit](https://github.com/arthenica/ffmpeg-kit) 新 README 指向官方后续 FFmpegKitNext。未把旧项目当成唯一当前路径。
- [MetalPetal](https://github.com/MetalPetal/MetalPetal) 核心与 Examples 许可证已区分。
- [LimitPoint LivePhoto](https://github.com/LimitPoint/LivePhoto) 未发现明确开源许可证，源码为 UIKit / 8-bit BGRA / H.264；仅作格式研究参考。
- [Apple Live API](https://developer.apple.com/documentation/photos/phlivephoto/request(withresourcefileurls:placeholderimage:targetsize:contentmode:resulthandler:)) 与本机 SDK 头文件已核查。Apple PHLivePhotoView 页面旧概述与现代 SDK 能力有差异，已要求运行验证。
- [DJI LUT](https://www.dji.com/downloads/softwares/osmo-pocket-3-dlog-to-rec709) 技术还原与风格区分，Rec.709 输出未描述为 HDR 输出；未假定 LUT 再分发许可。
- AI 作为开发助手与可选参数/标签/片段建议；未验证或宣称用户所提具体模型版本拥有可嵌入 APP 的视频编辑 API。
- 本地 HTML：8 节、内部锚点存在、无重复 ID、无外部 JS/CSS 依赖。
- 浏览器：默认 1280px 页面无横向溢出；桌面首屏视觉检查通过；路线切换通过；模拟手机与卡全部离线时收藏保留；恢复来源状态通过；浏览器错误日志为空。

仍未解决：实际手机系统、Pocket 型号、Mac/显示器、分发方式、素材规模；候选编译、真实设备读取、HDR 和 Live Photo 输出兼容性。方案中保留 P0 验证门槛，不阻塞研究交付。未进行手机/存储卡或照片库操作。

成果：[HTML 方案](../../../docs/mac-media-plan.html)，来源：[JSON](../../../docs/research-sources.json)。


## 第二轮核查：通过研究文档自检

- 新增三份 Adobe 官方资料已登记。桌面端学习机制的参考与本项目自己的教学流程明确区分。
- 延续原浏览布局，提出编辑状态与学习卡的结构建议；没有将静态区域描述成已工作的编辑器，也没有声称精确复刻 Lightroom。
- 拍摄元数据与可修改参数分开；缺失元数据不由模型伪造；参数解释、技术测量与风格判断分开。
- 混合多选、选择性同步、配方模式、Live 双资源处理、批次回退冲突及视频时序检查已进入方案。
- 9 个章节、9 个导航锚点、唯一 ID 与来源 JSON 静态检查通过；没有新增 JavaScript 行为。本轮不重新声称浏览器视觉检查通过：当前 file URL 被浏览器协议策略阻止访问，仅完成文件层检查。
- 仍待真实素材、原生实现及少量用户试用验证，未分析用户照片或访问相册。

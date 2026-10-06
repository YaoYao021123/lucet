# 光集 · 照片 / 视频 / Live Photo 浏览与调色

Mac 原生应用（Swift 6 · SwiftUI · Core Image · AVFoundation），最低 macOS 15；在 macOS 26 上使用 Liquid Glass 界面。无第三方依赖，原片从不修改：所有编辑以配方（JSON）自动保存，导出总是另存副本。

## 运行

```sh
bash scripts/run-workbench.sh            # 构建 Release 并打开 .build/MediaWorkbench.app
bash scripts/run-workbench.sh --build-only
bash scripts/test-workbench.sh           # 81 项测试
bash scripts/dev-build.sh                # 快速 Debug 构建，输出可执行文件路径
```

## 功能

**浏览（G）**：导入文件夹或拖入文件；缩略图网格可调大小，侧栏带缩略图列表。显示的缩略图已套用保存的调色与裁切。同名 HEIC/JPG + MOV 自动合并为一个 Live 项。评级 0–5、选用 P / 排除 X、按类型 / 评级 / 标记筛选、文件名搜索，⌘ / ⇧ 多选。

**编辑（E）**：按 DaVinci 式固定顺序处理，每一步都可单独开关比较：

1. 基础：按摄影概念分组，每组可单独复位。曝光（曝光、亮度）、影调（对比度、高光、阴影、白色、黑点、鲜明度）、白平衡（色温、色调）、色彩（自然饱和度、饱和度）
2. 色轮：暗部 / 中间调 / 亮部 / 整体（Lift / Gamma / Gain / Offset），方向与矢量示波器一致
3. 曲线：RGB 主曲线 + 红绿蓝单通道
4. HSL 色彩混合：8 个色系的色相 / 饱和度 / 明亮度
5. 风格 LUT：.cube（2–128 阶，兼容 GBK 标题、CRLF、DOMAIN / INPUT_RANGE），sRGB 或 Rec.709，强度可调，导入后长期保留
6. 细节与效果：降噪（最先）、清晰度、锐度，以及暗角（最后）

此外还有：

- 示波器：直方图、波形、RGB 分量、矢量，带溢出指示。
- 对比与检查：原片对比（\）、左右分屏（Y）、溢出显示（J）。
- 缩放：适合窗口 ↔ 100%（Z、双击、捏合），放大时自动载入原尺寸。
- 预设：4 个内置，可自建。
- 设置的复用：拷贝 / 粘贴调色（⇧⌘C / ⇧⌘V）；同步到所选时可按曝光、影调、白平衡、色彩、细节、效果分别选择（可撤回）。
- 撤销 / 重做、命名快照，以及拉直、旋转、镜像、裁剪画幅。

**学习（检查器「学习」页）**：教练会分析当前这张照片，用它的实际数据讲解问题和技巧，讲解随你的水平和兴趣调整：

- 照片提示：根据画面给出带具体数字的提示，包括溢出、偏暗 / 偏亮、发灰、色偏、过饱和、天空、人脸肤色（先用 Vision 识别人脸）、地平线倾斜，以及疑似 Log 素材。
- 显示与试一试：「显示区域」高亮问题所在的位置；「试一试」作为一步应用建议，并自动左右对比，可撤销。修好的问题会列入「已改善 ✓」。
- 影响范围：悬停在参数名、HSL 色系或色轮上，画面只保留它影响的区域为彩色，其余变灰（类似 DaVinci 的高亮显示）。
- 示波器解读：每个示波器下方有一句这张照片的读图说明。
- 随用户调整：水平（入门 / 进阶 / 专业）决定讲解的深浅和建议的工具，比如发灰的照片对入门用户建议对比度、对进阶用户建议 S 曲线。「想学」的方向决定学习路径和提示的排序。反馈（有帮助 / 已了解 / 不再提示）和实际使用记录会持续调整推荐；已掌握的技巧会打勾。
- 以上数据只在本机保存（`learning.json`），不联网。
- 问问这张照片（可选，默认关闭）：用自然语言提问，例如「天空为什么发灰？」「怎么调出胶片感？」。
  - 回答：由 Claude 结合这张照片的预览、统计、当前参数和你的水平与兴趣作答。回答附带可一键「试一试」的调整和追问建议；问题涉及的概念会计入兴趣，影响之后的推荐。
  - 发送的内容：只有点「提问」时才发送，内容是最长边 1024 px、不含拍摄与位置信息的 JPEG（可在设置中关闭），加上统计与参数。原片不会上传。
  - 密钥与模型：使用你自己的 Anthropic API 密钥，保存在钥匙串中。默认模型 Claude Opus 5.5，可改为 Sonnet 5.5 或 Haiku 4.5；按你的账户计费。
  - 对话：追问保持同一段对话，按 Anthropic 要求只追加、不改写历史；已发送的部分会被缓存，追问更便宜。中国大陆网络可能无法直接访问。
  - 后端：通过 `PhotoTutor` 协议可替换为其他服务商。

**视频与 Live**：时间线裁切、整体移动、逐帧、入点 / 出点（I / O）、封面（C）、0.5–4× 变速（原声同步，背景音乐保持原节奏）、「适配 3 秒」；制作 Live Photo（系统配对校验）与 1–3 画面拼图 Live；实验性 HDR 高光扩展（HLG）。

**导出**（后台队列，不阻塞编辑）：照片可选 JPEG / HEIC / PNG、质量和长边尺寸，默认保留拍摄时间、相机与镜头信息并移除 GPS；视频可选 H.264 / HEVC；也可批量导出所选，并写入导出记录。

按 ⌘/ 查看全部快捷键。单键快捷键在文本框中输入时不会触发。

## 与 ChatGPT 原型相比（2026-10-06）

| 项目 | 原型 | 现在 |
|---|---|---|
| 导入 2000 个文件的文件夹 | 主线程卡顿 6.9 s（O(n²)） | 4.5 ms |
| 解析 64³ LUT（DJI Winter Pro） | 609 ms，且每次打开文件都在主线程重复解析 | 20 ms，并全局缓存 |
| DJI Pocket 3 Spring / Winter Pro LUT | 无法导入（GBK 标题） | 正常导入 |
| 拖动一个滑块时重绘 | 侧栏、全部 16 个滑块、工具栏和菜单栏 | 只重绘该滑块与画面（已测量） |
| 预览分辨率 | 上限 1600 px，Retina 下发虚，不能缩放 | 按屏幕（≤3200 px），100% 时载入原尺寸 |
| 全部调色阶段渲染（2560 px） | — | 中位数 7.8 ms / P95 9.5 ms |
| 视频对比原片 / 首次调色 | 每次重建播放器 | 只更新滤镜参数（HDR 素材首次调色时切换一次 SDR 预览） |
| 播放头 | 10 Hz，并重绘整条时间线 | 30 Hz，独立小视图 |
| 照片导出 | 仅 PNG，丢失全部 EXIF | JPEG / HEIC / PNG，保留拍摄信息 |
| 导出时 | 整个应用锁定 | 后台队列 |
| 素材浏览 | 只有文件名列表 | 缩略图网格、评级、标记、筛选、键盘浏览 |

基准：`swift run --configuration release media-benchmark`（合成 12MP 图片；仅测渲染，不含显示）。

## 代码结构

- `Sources/MediaCore`：引擎，可单独测试。包括调色管线（`ColorPipeline`、`GradeStages`、`BasicAdjustments`）、`CubeLUT`、`Scopes`、`ImageExport`、视频与 Live（`VideoPipeline`、`LivePhotoPipeline`、`LiveCollagePipeline`）、配方 / 预设 / LUT 缓存（`EditRecipe`）。
- `Sources/MediaWorkbenchApp`：界面。
  - 模型：`AppModel` 负责协调（导入、导出、同步、快捷键），`LibraryModel` 管理素材库，`EditorModel` 管理当前文档，`ExportQueue` 是导出队列，`ThumbnailStore` 生成缩略图。
  - 视图：`WorkbenchView`、`LibraryViews`、`InspectorView`、`GradeControls`、`MediaCanvas`、`MediaTimeline`、`Sheets`。
- 数据位置：`~/Library/Application Support/Guangji`（素材库 `library.json`、配方、快照、预设、LUT）。

### 开发：无屏幕录制权限的界面截图

```sh
GUANGJI_DATA_DIR=/tmp/guangji-dev GUANGJI_SNAPSHOT_DIR=/tmp/shots \
GUANGJI_SNAPSHOT_STEPS="import:/path/to/folder;wait:3;shot:browse;open:/path/a.jpg;wait:2;shot:edit;quit" \
"$(bash scripts/dev-build.sh)"
```

脚本命令见 `DebugSnapshot.swift`。`GUANGJI_DATA_DIR` 使开发运行与正式素材库隔离；Metal、视频和 Liquid Glass 材质无法被视图缓存截取，截图只用于检查布局。

## 已知限制

- 调色后的照片以 SDR 输出；HDR 原片编辑后不保留增益图。
- 裁剪通过滑块设置，画面上暂无拖拽裁剪框。
- 尚未配置签名、沙盒与分发；设备直连导入、相机 Log 自动识别、AI 打标仍在规划中（见 `docs/`）。
- 原型阶段的文档与验证记录保留在 `docs/` 与 `docs/archive/`。

# 开发说明

面向想构建、修改或贡献光集的人。用户文档见 [README](../README.md)。

## 构建与测试

```sh
bash scripts/run-workbench.sh              # 构建 Release 并打开 .build/MediaWorkbench.app
bash scripts/run-workbench.sh --build-only
bash scripts/test-workbench.sh             # 94 项测试
bash scripts/dev-build.sh                  # 快速 Debug 构建，输出可执行文件路径
bash scripts/package-release.sh            # 生成 dist/Guangji-<版本>-arm64.zip（临时签名，未公证）
```

要求：macOS 15+、Apple 芯片、Xcode 命令行工具（不需要完整 Xcode）。最低系统 macOS 15；在 macOS 26 上使用 Liquid Glass。无第三方依赖。

命令行工具：

```sh
swift run media-probe details <素材>        # 打印「信息」页的全部内容
swift run media-probe analyze <图片>        # 画面统计与教练提示
swift run media-probe auto <图片> [对比.jpg] # 「自动」的取值，可输出前后对比图
swift run --configuration release media-benchmark
```

## 发布

1. `bash scripts/package-release.sh`，得到 `dist/Guangji-<版本>-arm64.zip` 与 SHA-256。
2. 在 GitHub 新建 Release，上传 zip，把 SHA-256 写进说明。
3. 当前只有临时签名，系统会要求用户手动放行一次（网站「常见问题」已写明步骤）。要让用户直接双击打开，需要 Apple Developer ID 签名并公证。

## 网站

`website/` 是纯静态页面（无构建步骤、无外部依赖）。本地预览：`python3 -m http.server --directory website`。推送到 `main` 后由 `.github/workflows/pages.yml` 发布到 GitHub Pages（需在仓库 Settings › Pages 把来源设为 GitHub Actions）。

页面里的截图由应用自带的快照模式生成：`bash scripts/make-site-screenshots.sh <示例照片文件夹> [示例视频]`。快照无法呈现 Liquid Glass 材质，想要真实玻璃效果，可以自己截一张图替换 `website/assets/shot-edit.jpg`（文件名不变即可）。示例照片会公开展示，请只用你有权公开的照片。

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

脚本命令见 `DebugSnapshot.swift`；`panel:名称@高度` 在单独的离屏窗口中渲染检查器（在部分系统版本上，辅助模式运行时窗口内的检查器不会显示），`dump` 打印窗口的视图层级。`GUANGJI_DATA_DIR` 使开发运行与正式素材库隔离；Metal、视频和 Liquid Glass 材质无法被视图缓存截取，截图只用于检查布局。


## 品牌资产

`assets/brand/`（见其中的 README 与 `preview.html`）。`bash scripts/generate-brand.sh` 重建矢量、PNG 与 ICNS。

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


原型阶段的文档与验证记录保留在 `docs/` 与 `docs/archive/`。

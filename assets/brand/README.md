# 光集主视觉资产

打开 `preview.html` 查看实际导出、用法与接入截图。`manifest.json` 是资产清单，`verification.json` 是验证记录。SVG 中字标和文案全部转曲，无字体依赖。

当前 App 已接入 `icons/AppIcon.icns`、工具栏矢量标志、`runtime/EmptyLibrary-dark.png`。浅色图标为备用导出；Icon Composer 分层源位于 `layers`，尚未构建 `.icon`。功能按钮继续使用系统 SF Symbols。

在项目根目录运行 `bash scripts/generate-brand.sh` 重建矢量/PNG/iconset/ICNS，再运行 `bash scripts/run-workbench.sh --build-only` 构建 App。此脚本生成了实际文件，无图片生成服务依赖。资产 ZIP 不含用户素材。

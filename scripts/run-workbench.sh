#!/bin/bash
set -euo pipefail
workbench_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workbench_root"
export CLANG_MODULE_CACHE_PATH="$workbench_root/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$workbench_root/.build/swift-module-cache"
workbench_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
# The host already provides a sandbox; SwiftPM's nested sandbox cannot start here.
# Record the SDK actually used, independently of the macOS 15 deployment target.
# The current Swift Build engine on this CLT host records SDK 15.0 even with
# --sdk. Its native engine correctly records the selected SDK in the executable.
swift build --disable-sandbox --build-system native --sdk "$workbench_sdk_path" --configuration release -debug-info-format none --product media-workbench --scratch-path .build/native-workbench --cache-path .build/cache --config-path .build/config --security-path .build/security
workbench_bin_dir="$(swift build --disable-sandbox --build-system native --sdk "$workbench_sdk_path" --configuration release --show-bin-path --scratch-path .build/native-workbench --cache-path .build/cache --config-path .build/config --security-path .build/security)"
workbench_app="$workbench_root/.build/MediaWorkbench.app"
mkdir -p "$workbench_app/Contents/MacOS" "$workbench_app/Contents/Resources"
# Pre-generated brand assets are durable source assets, never generated during a build.
cp "$workbench_root/assets/brand/icons/AppIcon.icns" "$workbench_app/Contents/Resources/AppIcon.icns"
cp "$workbench_root/assets/brand/runtime/EmptyLibrary-dark.png" "$workbench_app/Contents/Resources/EmptyLibrary-dark.png"
cp "$workbench_bin_dir/media-workbench" "$workbench_app/Contents/MacOS/media-workbench.new"
mv -f "$workbench_app/Contents/MacOS/media-workbench.new" "$workbench_app/Contents/MacOS/media-workbench"
cat > "$workbench_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>media-workbench</string>
<key>CFBundleIdentifier</key><string>local.mediaworkbench.prototype</string>
<key>CFBundleName</key><string>Lucet 光集</string>
<key>CFBundleDisplayName</key><string>Lucet 光集</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPhotoLibraryAddUsageDescription</key><string>光集把你导出的照片、视频和 Live Photo 存入「照片」，不会读取或修改你已有的照片。</string>
</dict></plist>
PLIST
if [[ "${1:-}" != "--build-only" ]]; then
    open -n "$workbench_app"
fi

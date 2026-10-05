#!/bin/bash
set -euo pipefail
brand_project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$brand_project_root"
mkdir -p .build/brand-module-cache
xcrun swift -module-cache-path .build/brand-module-cache scripts/generate-brand.swift "$brand_project_root/assets/brand"
/usr/bin/iconutil -c icns assets/brand/icons/AppIcon.iconset -o assets/brand/icons/AppIcon.icns

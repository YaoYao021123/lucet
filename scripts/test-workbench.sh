#!/bin/bash
set -euo pipefail
workbench_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workbench_root"
export CLANG_MODULE_CACHE_PATH="$workbench_root/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$workbench_root/.build/swift-module-cache"
workbench_swiftc="$(xcrun --find swiftc)"
workbench_testing_plugins="$(dirname "$workbench_swiftc")/../lib/swift/host/plugins/testing"
workbench_test_flags=()
if [[ -f "$workbench_testing_plugins/libTestingMacros.dylib" ]]; then
    workbench_test_flags=(-Xswiftc -plugin-path -Xswiftc "$workbench_testing_plugins")
fi
swift test --disable-sandbox --disable-xctest --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security "${workbench_test_flags[@]}"

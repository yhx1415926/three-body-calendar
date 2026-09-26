#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build/module-cache .build/swiftpm-cache
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$TASK_ROOT/.build/module-cache"
exec /usr/bin/xcrun swift run --build-system native --disable-sandbox --scratch-path .build --cache-path .build/swiftpm-cache -c release ScienceCheck "$@"

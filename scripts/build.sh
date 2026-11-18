#!/bin/bash
# 统一构建入口：自动使用完整 Xcode 工具链（CommandLineTools 缺少 SwiftUI 宏插件）。
#
# 用法：
#   ./scripts/build.sh              # 调试构建
#   ./scripts/build.sh run          # 构建并运行
#   ./scripts/build.sh test         # 运行全部测试
#   ./scripts/build.sh test --filter TobarsCoreTests.CommandCodeProviderTests
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

if [ $# -eq 0 ]; then
    exec swift build
fi

exec swift "$@"

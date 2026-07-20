#!/bin/bash

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "=== EnvMatrix 启动脚本 ==="
echo ""

if [ ! -d ".build" ]; then
    echo "正在构建项目..."
    swift build
else
    echo "检测到已存在构建目录，跳过构建..."
fi

echo ""
echo "启动 EnvMatrix..."
echo ""

.build/debug/EnvMatrix
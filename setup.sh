#!/bin/bash
set -e

cd "$(dirname "$0")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  健康档案 iOS App 安装配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "请先安装 Xcode（从 App Store 下载）"
    open "https://apps.apple.com/app/xcode/id497799835"
    exit 1
fi

# Install Homebrew if needed
if ! command -v brew &>/dev/null; then
    echo "安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install XcodeGen if needed
if ! command -v xcodegen &>/dev/null; then
    echo "安装 XcodeGen..."
    brew install xcodegen
fi

echo "生成 Xcode 项目..."
xcodegen generate

echo ""
echo "✅ 完成！"
echo ""
echo "接下来："
echo "1. Xcode 会自动打开"
echo "2. 选择你的 iPhone 作为运行目标"
echo "3. 点击左上角 ▶ 运行"
echo ""
open HealthRecords.xcodeproj

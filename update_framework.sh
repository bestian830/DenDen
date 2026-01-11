#!/bin/bash

echo "🚀 开始一键更新 DenDen Framework..."

# 定义路径变量
CORE_DIR="/Users/ryan/Documents/Ryan/DenDen/denden-core"
APP_DIR="/Users/ryan/Documents/Ryan/DenDen/denden_app"
FRAMEWORK_DEST="$APP_DIR/ios/Frameworks"  # 注意：这是我们要去的正确位置！

# 1. 编译 Go 核心
echo "⚙️  正在编译 Go Mobile Framework..."
cd "$CORE_DIR"
./build_ios.sh
if [ $? -ne 0 ]; then
    echo "❌ 编译失败！请检查 Go 代码。"
    exit 1
fi

# 2. 彻底删除 App 里的旧文件 (精确打击 Frameworks 目录)
echo "🧹 清理旧的 Framework..."
rm -rf "$FRAMEWORK_DEST/DenDen.xcframework"
# 确保目录存在
mkdir -p "$FRAMEWORK_DEST"

# 3. 搬运新文件
echo "🚚 正在部署新 Framework..."
cp -R "$CORE_DIR/ios/DenDen.xcframework" "$FRAMEWORK_DEST/"

# 4. 核弹级清理 Xcode 缓存 (这是防止幽灵缓存的关键！)
echo "💣 清理 Xcode 缓存 (DerivedData)..."
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# 5. 清理 Flutter 并运行
echo "✨ 清理 Flutter 并启动..."
cd "$APP_DIR"
flutter clean
flutter run

echo "✅ 所有流程执行完毕！"

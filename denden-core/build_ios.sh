#!/bin/bash

# Build script for iOS framework using gomobile
# This generates DenDen.framework that can be imported into Xcode

set -e  # Exit on error

echo "🍎 Building Den Den iOS Framework..."
echo "================================================"

# Check if gomobile is installed
if ! command -v gomobile &> /dev/null; then
    echo "❌ gomobile not found. Installing..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
fi

# Clean previous build
echo "🧹 Cleaning previous builds..."
rm -rf ios/DenDen.xcframework
rm -rf ios/DenDen.framework

# Build for iOS (both arm64 for devices and amd64 for simulator)
echo "⚙️  Building framework..."
gomobile bind -target=ios -o ios/DenDen.xcframework ./mobile

if [ $? -eq 0 ]; then
    echo ""
    echo "================================================"
    echo "✅ iOS Framework built successfully!"
    echo "================================================"
    echo ""
    echo "📦 Output: ios/DenDen.xcframework"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open your Xcode project"
    echo "2. Drag DenDen.xcframework into your project"
    echo "3. Go to Target -> General -> Frameworks, Libraries, and Embedded Content"
    echo "4. Make sure DenDen.xcframework is set to 'Embed & Sign'"
    echo ""
    echo "💡 Example usage in Swift:"
    echo "   import DenDen"
    echo "   let client = MobileNewDenDenClient(storageDir)"
    echo ""
else
    echo "❌ Build failed!"
    exit 1
fi

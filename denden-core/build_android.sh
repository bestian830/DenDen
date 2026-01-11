#!/bin/bash

# Build script for Android AAR using gomobile
# This generates DenDen.aar that can be imported into Android Studio

set -e  # Exit on error

echo "🤖 Building Den Den Android AAR..."
echo "================================================"

# Check if gomobile is installed
if ! command -v gomobile &> /dev/null; then
    echo "❌ gomobile not found. Installing..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    gomobile init
fi

# Check if ANDROID_HOME is set
if [ -z "$ANDROID_HOME" ]; then
    echo "⚠️  ANDROID_HOME not set. Trying common locations..."
    if [ -d "$HOME/Library/Android/sdk" ]; then
        export ANDROID_HOME="$HOME/Library/Android/sdk"
        echo "✅ Found Android SDK at $ANDROID_HOME"
    elif [ -d "$HOME/Android/Sdk" ]; then
        export ANDROID_HOME="$HOME/Android/Sdk"
        echo "✅ Found Android SDK at $ANDROID_HOME"
    else
        echo "❌ Could not find Android SDK"
        echo "   Please set ANDROID_HOME environment variable"
        exit 1
    fi
fi

# Clean previous build
echo "🧹 Cleaning previous builds..."
rm -rf android/DenDen.aar
rm -rf android/DenDen-sources.jar

# Create output directory
mkdir -p android

# Build for Android
echo "⚙️  Building AAR..."
gomobile bind -target=android -o android/DenDen.aar ./mobile

if [ $? -eq 0 ]; then
    echo ""
    echo "================================================"
    echo "✅ Android AAR built successfully!"
    echo "================================================"
    echo ""
    echo "📦 Output: android/DenDen.aar"
    echo ""
    echo "📋 Next steps:"
    echo "1. Open your Android Studio project"
    echo "2. Copy DenDen.aar to app/libs/"
    echo "3. Add to app/build.gradle:"
    echo "   dependencies {"
    echo "       implementation files('libs/DenDen.aar')"
    echo "   }"
    echo ""
    echo "💡 Example usage in Kotlin:"
    echo "   import mobile.Mobile"
    echo "   val client = Mobile.newDenDenClient(storageDir)"
    echo ""
else
    echo "❌ Build failed!"
    exit 1
fi

#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../ClaudeTrafficLight.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

SDK=""
for d in /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; do
    if [ -d "$d" ]; then SDK="$d"; break; fi
done
if [ -z "$SDK" ]; then echo "macOS SDK not found"; exit 1; fi
echo "Using SDK: $SDK"

# Compile
clang -o "$APP_DIR/Contents/MacOS/ClaudeTrafficLight" \
    "$SCRIPT_DIR/Sources/main.m" \
    -isysroot "$SDK" \
    -framework Cocoa \
    -framework UserNotifications \
    -fobjc-arc \
    -O2

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy icon
cp "$SCRIPT_DIR/ClaudeTrafficLight.icns" "$APP_DIR/Contents/Resources/ClaudeTrafficLight.icns"

codesign -s - "$APP_DIR/Contents/MacOS/ClaudeTrafficLight"
echo "Build success: $APP_DIR"
echo ""
echo "Next steps:"
echo "  1. Run: bash $SCRIPT_DIR/install_hooks.sh"
echo "  2. echo 'idle' > /tmp/claude_traffic_light_state"
echo "  3. open $APP_DIR"

#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Pi Session Monitor Installer${NC}"
echo "=============================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This installer is for macOS only.${NC}"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install extension
echo -e "${YELLOW}Installing pi extension...${NC}"

PI_EXTENSIONS_DIR="$HOME/.pi/agent/extensions"
mkdir -p "$PI_EXTENSIONS_DIR"

# Remove existing installation if present
if [ -d "$PI_EXTENSIONS_DIR/pi-session-monitor" ]; then
    echo "Removing existing extension..."
    rm -rf "$PI_EXTENSIONS_DIR/pi-session-monitor"
fi

# Copy extension files
cp -r "$SCRIPT_DIR/extension" "$PI_EXTENSIONS_DIR/pi-session-monitor"

# Install dependencies
echo "Installing extension dependencies..."
cd "$PI_EXTENSIONS_DIR/pi-session-monitor"

# Check if npm or pnpm is available
if command -v pnpm &> /dev/null; then
    pnpm install
elif command -v npm &> /dev/null; then
    npm install
else
    echo -e "${RED}Error: Neither npm nor pnpm found. Please install Node.js.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Extension installed${NC}"
echo ""

# Check for Xcode for macOS app
echo -e "${YELLOW}Checking for Xcode...${NC}"
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${YELLOW}Warning: Xcode not found. The macOS app will not be built.${NC}"
    echo "Please install Xcode from the App Store to build the menu bar app."
    echo ""
    echo -e "${GREEN}Extension installation complete!${NC}"
    echo "The extension will be active the next time you start pi."
    exit 0
fi

# Build macOS app
echo -e "${YELLOW}Building macOS app...${NC}"

# Create build directory
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

# Create a temporary Xcode project
PROJECT_DIR="$BUILD_DIR/PiSessionMonitor"
mkdir -p "$PROJECT_DIR"

# Copy source files
cp -r "$SCRIPT_DIR/macos-app/PiSessionMonitor" "$PROJECT_DIR/"

# Create a simple Package.swift for Swift Package Manager
cat > "$PROJECT_DIR/Package.swift" << 'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PiSessionMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PiSessionMonitor", targets: ["PiSessionMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "PiSessionMonitor",
            path: "PiSessionMonitor",
            exclude: ["PiSessionMonitor.xcodeproj"]
        )
    ]
)
EOF

# Try to build with swift package manager
echo "Building with Swift Package Manager..."
cd "$PROJECT_DIR"

if swift build 2>/dev/null; then
    echo -e "${GREEN}✓ macOS app built successfully${NC}"
    
    # Create app bundle
    APP_BUNDLE="$BUILD_DIR/PiSessionMonitor.app"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    
    # Copy binary
    cp ".build/debug/PiSessionMonitor" "$APP_BUNDLE/Contents/MacOS/"
    
    # Create Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PiSessionMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourusername.PiSessionMonitor</string>
    <key>CFBundleName</key>
    <string>Pi Session Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
    
    echo ""
    echo -e "${GREEN}Installation complete!${NC}"
    echo ""
    echo "Extension installed to: $PI_EXTENSIONS_DIR/pi-session-monitor"
    echo "App bundle created at: $APP_BUNDLE"
    echo ""
    echo "To start using:"
    echo "1. The extension will be active the next time you start pi"
    echo "2. Launch the app: open '$APP_BUNDLE'"
    echo ""
    
    # Offer to copy to Applications
    read -p "Would you like to copy the app to /Applications? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp -r "$APP_BUNDLE" "/Applications/"
        echo -e "${GREEN}App copied to /Applications${NC}"
    fi
else
    echo -e "${YELLOW}Swift Package Manager build failed.${NC}"
    echo "The extension is installed and ready to use."
    echo "To build the macOS app manually:"
    echo "1. Open Xcode"
    echo "2. Create a new macOS App project"
    echo "3. Copy the files from $SCRIPT_DIR/macos-app/PiSessionMonitor/"
    echo ""
fi

echo -e "${GREEN}Done!${NC}"

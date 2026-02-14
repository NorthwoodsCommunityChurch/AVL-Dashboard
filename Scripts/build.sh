#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
RESOURCES_DIR="$PROJECT_DIR/Resources"

echo "==> Building AVL Dashboard project..."
cd "$PROJECT_DIR"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build universal release binaries (arm64 + x86_64)
# SPM multi-arch builds fail when multiple targets share a framework (Sparkle),
# so build each arch separately and combine with lipo.
echo "==> Compiling arm64..."
swift build -c release --triple arm64-apple-macosx 2>&1
ARM64_DIR="$(swift build -c release --triple arm64-apple-macosx --show-bin-path)"

echo "==> Compiling x86_64..."
swift build -c release --triple x86_64-apple-macosx 2>&1
X86_DIR="$(swift build -c release --triple x86_64-apple-macosx --show-bin-path)"

echo "==> Creating universal binaries with lipo..."
PRODUCTS_DIR="$BUILD_DIR/universal-bin"
mkdir -p "$PRODUCTS_DIR"
lipo -create "$ARM64_DIR/Dashboard" "$X86_DIR/Dashboard" -output "$PRODUCTS_DIR/Dashboard"
lipo -create "$ARM64_DIR/Agent" "$X86_DIR/Agent" -output "$PRODUCTS_DIR/Agent"
echo "    Dashboard: $(lipo -archs "$PRODUCTS_DIR/Dashboard")"
echo "    Agent:     $(lipo -archs "$PRODUCTS_DIR/Agent")"

# Extract version from Version.swift
APP_VERSION=$(grep 'public static let current' "$PROJECT_DIR/Sources/Shared/Version.swift" | sed 's/.*"\(.*\)".*/\1/')
echo "==> Version: $APP_VERSION"

# Locate Sparkle.framework from SPM artifacts
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "ERROR: Sparkle.framework not found at $SPARKLE_FRAMEWORK"
    echo "       Run 'swift build' first to download Sparkle package"
    exit 1
fi

# Clear extended attributes from source framework (OneDrive adds these)
xattr -cr "$SPARKLE_FRAMEWORK"

# --- Create Dashboard.app bundle ---
echo "==> Bundling Dashboard.app..."
DASH_APP="$BUILD_DIR/Dashboard.app"
DASH_CONTENTS="$DASH_APP/Contents"
mkdir -p "$DASH_CONTENTS/MacOS"
mkdir -p "$DASH_CONTENTS/Resources"
mkdir -p "$DASH_CONTENTS/Frameworks"

cp "$PRODUCTS_DIR/Dashboard" "$DASH_CONTENTS/MacOS/Dashboard"
cp "$RESOURCES_DIR/Dashboard-Info.plist" "$DASH_CONTENTS/Info.plist"
cp "$RESOURCES_DIR/AppIcon.icns" "$DASH_CONTENTS/Resources/AppIcon.icns"

# Copy Sparkle.framework
cp -R "$SPARKLE_FRAMEWORK" "$DASH_CONTENTS/Frameworks/"

# Add rpath so binary can find framework in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$DASH_CONTENTS/MacOS/Dashboard"

# Inject version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$DASH_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$DASH_CONTENTS/Info.plist"

# Clear extended attributes (OneDrive adds these, breaks codesigning)
xattr -cr "$DASH_APP"

# Ad-hoc code sign (sign Sparkle nested components inside-out, then app)
codesign --force --sign - "$DASH_CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign - "$DASH_CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign - "$DASH_CONTENTS/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --sign - "$DASH_CONTENTS/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --sign - "$DASH_CONTENTS/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$DASH_APP"
echo "    Dashboard.app created at $DASH_APP"

# --- Create DashboardAgent.app bundle ---
echo "==> Bundling DashboardAgent.app..."
AGENT_APP="$BUILD_DIR/DashboardAgent.app"
AGENT_CONTENTS="$AGENT_APP/Contents"
mkdir -p "$AGENT_CONTENTS/MacOS"
mkdir -p "$AGENT_CONTENTS/Resources"
mkdir -p "$AGENT_CONTENTS/Frameworks"

cp "$PRODUCTS_DIR/Agent" "$AGENT_CONTENTS/MacOS/Agent"
cp "$RESOURCES_DIR/Agent-Info.plist" "$AGENT_CONTENTS/Info.plist"
cp "$RESOURCES_DIR/AppIcon.icns" "$AGENT_CONTENTS/Resources/AppIcon.icns"

# Copy Sparkle.framework
cp -R "$SPARKLE_FRAMEWORK" "$AGENT_CONTENTS/Frameworks/"

# Add rpath so binary can find framework in Contents/Frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" "$AGENT_CONTENTS/MacOS/Agent"

# Inject version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$AGENT_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$AGENT_CONTENTS/Info.plist"

# Clear extended attributes (OneDrive adds these, breaks codesigning)
xattr -cr "$AGENT_APP"

# Ad-hoc code sign (sign Sparkle nested components inside-out, then app)
codesign --force --sign - "$AGENT_CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign - "$AGENT_CONTENTS/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign - "$AGENT_CONTENTS/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --sign - "$AGENT_CONTENTS/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --sign - "$AGENT_CONTENTS/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$AGENT_APP"
echo "    DashboardAgent.app created at $AGENT_APP"

# --- Build Windows Agent ---
echo "==> Building Windows Agent..."
WINDOWS_EXE="$BUILD_DIR/DashboardAgent.exe"

(
    cd "$PROJECT_DIR/agent-windows"
    GOOS=windows GOARCH=amd64 go build \
        -ldflags="-H windowsgui -X main.version=$APP_VERSION" \
        -o "$WINDOWS_EXE" \
        .
)
echo "    DashboardAgent.exe created at $WINDOWS_EXE"

# --- Create release archives ---
echo "==> Creating release archives..."
# Use ditto (not zip -r) to preserve symlinks inside Sparkle.framework.
# zip -r follows symlinks and turns them into real files, which breaks
# codesigning ("bundle format is ambiguous") when installed on other machines.
(cd "$BUILD_DIR" && ditto -c -k --keepParent Dashboard.app "Dashboard-v${APP_VERSION}-universal.zip")
(cd "$BUILD_DIR" && ditto -c -k --keepParent DashboardAgent.app "DashboardAgent-v${APP_VERSION}-universal.zip")
(cd "$BUILD_DIR" && zip -j "DashboardAgent-v${APP_VERSION}-windows-amd64.zip" DashboardAgent.exe)

echo ""
echo "==> Build complete!"
echo "    Dashboard:       $DASH_APP"
echo "    macOS Agent:     $AGENT_APP"
echo "    Windows Agent:   $WINDOWS_EXE"
echo ""
echo "    Release archives in $BUILD_DIR/"
echo ""
echo "Note: On first launch (macOS), right-click > Open to bypass Gatekeeper."

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

# Build release binaries
echo "==> Compiling with Swift Package Manager..."
swift build -c release 2>&1

PRODUCTS_DIR="$(swift build -c release --show-bin-path)"

# Extract version from Version.swift
APP_VERSION=$(grep 'public static let current' "$PROJECT_DIR/Sources/Shared/Version.swift" | sed 's/.*"\(.*\)".*/\1/')
echo "==> Version: $APP_VERSION"

# --- Create Dashboard.app bundle ---
echo "==> Bundling Dashboard.app..."
DASH_APP="$BUILD_DIR/Dashboard.app"
DASH_CONTENTS="$DASH_APP/Contents"
mkdir -p "$DASH_CONTENTS/MacOS"
mkdir -p "$DASH_CONTENTS/Resources"

cp "$PRODUCTS_DIR/Dashboard" "$DASH_CONTENTS/MacOS/Dashboard"
cp "$RESOURCES_DIR/Dashboard-Info.plist" "$DASH_CONTENTS/Info.plist"
cp "$RESOURCES_DIR/AppIcon.icns" "$DASH_CONTENTS/Resources/AppIcon.icns"

# Inject version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$DASH_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$DASH_CONTENTS/Info.plist"

# Ad-hoc code sign
codesign --force --deep --sign - "$DASH_APP"
echo "    Dashboard.app created at $DASH_APP"

# --- Create DashboardAgent.app bundle ---
echo "==> Bundling DashboardAgent.app..."
AGENT_APP="$BUILD_DIR/DashboardAgent.app"
AGENT_CONTENTS="$AGENT_APP/Contents"
mkdir -p "$AGENT_CONTENTS/MacOS"
mkdir -p "$AGENT_CONTENTS/Resources"

cp "$PRODUCTS_DIR/Agent" "$AGENT_CONTENTS/MacOS/Agent"
cp "$RESOURCES_DIR/Agent-Info.plist" "$AGENT_CONTENTS/Info.plist"
cp "$RESOURCES_DIR/AppIcon.icns" "$AGENT_CONTENTS/Resources/AppIcon.icns"

# Inject version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$AGENT_CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$AGENT_CONTENTS/Info.plist"

# Ad-hoc code sign
codesign --force --deep --sign - "$AGENT_APP"
echo "    DashboardAgent.app created at $AGENT_APP"

echo ""
echo "==> Build complete!"
echo "    Dashboard:  $DASH_APP"
echo "    Agent:      $AGENT_APP"
echo ""
echo "Note: On first launch, right-click > Open to bypass Gatekeeper."

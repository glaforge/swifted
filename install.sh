#!/bin/bash

# Exit on error
set -e

APP_NAME="Swifted"
EXECUTABLE_NAME="swifted"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"
BIN_PATH="${BUILD_DIR}/${EXECUTABLE_NAME}"
DESTINATION="/Applications/${APP_BUNDLE}"

echo "🔨 Building ${APP_NAME} in release mode..."
swift build -c release

echo "📦 Creating App Bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "📄 Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourdomain.${EXECUTABLE_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.data</string>
                <string>public.folder</string>
                <string>public.directory</string>
                <string>public.item</string>
                <string>public.content</string>
                <string>public.source-code</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

if [ -f "AppIcon.icns" ]; then
    echo "🖼️ Copying AppIcon..."
    cp "AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
fi

echo "🚚 Copying executable..."
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/"

echo "🔏 Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "🚀 Installing to Applications folder..."
if [ -d "${DESTINATION}" ]; then
    echo "Removing existing installation..."
    rm -rf "${DESTINATION}"
fi

cp -R "${APP_BUNDLE}" /Applications/
rm -rf "${APP_BUNDLE}"

echo "✅ Installed successfully at ${DESTINATION}"
echo "You can now open it via Spotlight or Launchpad!"

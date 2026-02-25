#!/bin/bash
#
# Monitor App Build Script
# 将 Swift 源码编译为 macOS .app 应用包
#
set -euo pipefail

APP_NAME="Monitor"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"
SRC_DIR="Monitor"

echo "🔨 构建 ${APP_NAME}..."

# 清理并创建目录结构
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 检测架构
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macosx13.0"
else
    TARGET="x86_64-apple-macosx13.0"
fi

SDK=$(xcrun --show-sdk-path)

echo "   架构: ${ARCH}"
echo "   SDK:  ${SDK}"

# 编译所有 Swift 源文件
xcrun swiftc \
    -parse-as-library \
    -target "${TARGET}" \
    -sdk "${SDK}" \
    -O \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework Vision \
    -framework AppKit \
    -framework CoreMedia \
    "${SRC_DIR}/MonitorApp.swift" \
    "${SRC_DIR}/ContentView.swift" \
    "${SRC_DIR}/CameraPreviewView.swift" \
    "${SRC_DIR}/ScreenGuardController.swift" \
    "${SRC_DIR}/StatusBarController.swift" \
    "${SRC_DIR}/AppInfo.swift"

echo "   ✅ 编译完成"

# 复制 Info.plist
cp "${SRC_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# 复制应用图标
if [ -f "${SRC_DIR}/AppIcon.icns" ]; then
    cp "${SRC_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    echo "   ✅ 图标已复制"
fi

# 代码签名（ad-hoc + camera entitlement）
codesign --force --sign - \
    --entitlements "${SRC_DIR}/Monitor.entitlements" \
    "${APP_BUNDLE}"

echo "   ✅ 签名完成"
echo ""
echo "======================================="
echo "  构建成功！"
echo "  应用路径: ${APP_BUNDLE}"
echo "  运行命令: open ${APP_BUNDLE}"
echo "======================================="

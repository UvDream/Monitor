#!/bin/bash
#
# Monitor App Build Script
# 将 Swift 源码编译为 macOS .app 应用包
# 支持 Universal Binary（同时包含 arm64 和 x86_64），可在所有 Mac 上运行。
#
set -euo pipefail

APP_NAME="Monitor"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
BUNDLE_RES_DIR="${CONTENTS}/Resources"

# 源文件目录
SWIFT_DIR="Sources"     # Swift 源文件
RES_DIR="Resources"     # plist、图标、entitlements

# 临时目录存放单架构二进制
STAGING_DIR="${BUILD_DIR}/.staging"

echo "🔨 构建 ${APP_NAME} (Universal Binary)..."

# 清理并创建目录结构
rm -rf "${APP_BUNDLE}" "${STAGING_DIR}"
mkdir -p "${MACOS_DIR}" "${BUNDLE_RES_DIR}" "${STAGING_DIR}"

SDK=$(xcrun --show-sdk-path)
echo "   SDK: ${SDK}"

# 公共的 Swift 编译参数
SWIFT_SOURCES=(
    "${SWIFT_DIR}/MonitorApp.swift"
    "${SWIFT_DIR}/ContentView.swift"
    "${SWIFT_DIR}/CameraPreviewView.swift"
    "${SWIFT_DIR}/ScreenGuardController.swift"
    "${SWIFT_DIR}/StatusBarController.swift"
    "${SWIFT_DIR}/AppInfo.swift"
)
SWIFT_FLAGS=(
    -parse-as-library
    -sdk "${SDK}"
    -O
    -framework SwiftUI
    -framework AVFoundation
    -framework Vision
    -framework AppKit
    -framework CoreMedia
)

# 检测当前运行架构，决定构建策略
HOST_ARCH=$(uname -m)

if [ "${HOST_ARCH}" = "arm64" ]; then
    echo "   主机架构: arm64 → 构建 Universal Binary"

    echo "   [1/2] 编译 arm64…"
    xcrun swiftc \
        "${SWIFT_FLAGS[@]}" \
        -target "arm64-apple-macosx13.0" \
        -o "${STAGING_DIR}/${APP_NAME}_arm64" \
        "${SWIFT_SOURCES[@]}"

    echo "   [2/2] 编译 x86_64…"
    xcrun swiftc \
        "${SWIFT_FLAGS[@]}" \
        -target "x86_64-apple-macosx13.0" \
        -o "${STAGING_DIR}/${APP_NAME}_x86_64" \
        "${SWIFT_SOURCES[@]}"

    echo "   合并为 Universal Binary…"
    lipo -create \
        "${STAGING_DIR}/${APP_NAME}_arm64" \
        "${STAGING_DIR}/${APP_NAME}_x86_64" \
        -output "${MACOS_DIR}/${APP_NAME}"

elif [ "${HOST_ARCH}" = "x86_64" ]; then
    echo "   主机架构: x86_64 → 单架构构建 (x86_64)"

    xcrun swiftc \
        "${SWIFT_FLAGS[@]}" \
        -target "x86_64-apple-macosx13.0" \
        -o "${MACOS_DIR}/${APP_NAME}" \
        "${SWIFT_SOURCES[@]}"
else
    echo "   未知架构 ${HOST_ARCH}，退化为当前架构构建"
    xcrun swiftc \
        "${SWIFT_FLAGS[@]}" \
        -target "${HOST_ARCH}-apple-macosx13.0" \
        -o "${MACOS_DIR}/${APP_NAME}" \
        "${SWIFT_SOURCES[@]}"
fi

echo "   ✅ 编译完成"
echo "   二进制架构: $(lipo -archs "${MACOS_DIR}/${APP_NAME}")"

# 复制 Info.plist
cp "${RES_DIR}/Info.plist" "${CONTENTS}/Info.plist"

# 复制应用图标
if [ -f "${RES_DIR}/AppIcon.icns" ]; then
    cp "${RES_DIR}/AppIcon.icns" "${BUNDLE_RES_DIR}/AppIcon.icns"
    echo "   ✅ 图标已复制"
fi

# 代码签名（ad-hoc + camera entitlement）
codesign --force --sign - \
    --entitlements "${RES_DIR}/Monitor.entitlements" \
    "${APP_BUNDLE}"

echo "   ✅ 签名完成"

# 清理临时文件
rm -rf "${STAGING_DIR}"

echo ""
echo "======================================="
echo "  构建成功！"
echo "  应用路径: ${APP_BUNDLE}"
echo "  运行命令: open ${APP_BUNDLE}"
echo "======================================="

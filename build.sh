#!/bin/bash
# ============================================================
# DeepSeek Desktop — 构建 .app → 签名 → .dmg
# 用法: ./build.sh [--install]      --install 额外装到 /Applications
#
# 可覆盖变量：
#   RUNTIME_NODE      Node 可执行文件路径（默认本机 nvm node v24）
#   DSH_BUNDLE_DIR    dsh 安装目录（含 node_modules 的 npx 目录）
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeek"
EXEC_NAME="DeepSeek"
VERSION="1.0.0"
BUNDLE_ID="com.deepseek.desktop"
TARGET="arm64-apple-macosx15.0"

RUNTIME_NODE="${RUNTIME_NODE:-/Users/xiexin/.nvm/versions/node/v24.19.0/bin/node}"
DSH_BUNDLE_DIR="${DSH_BUNDLE_DIR:-/Users/xiexin/.npm/_npx/1e7f6d9597241db0}"

BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"

DO_INSTALL=0
for arg in "$@"; do [ "$arg" = "--install" ] && DO_INSTALL=1; done

echo "==> 清理旧产物"
rm -rf "$BUILD_DIR" "$DMG_NAME"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "==> 生成防篡改校验常量 (Integrity.generated.swift)"
GEN="Sources/Integrity.generated.swift"
hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
cat > "$GEN" <<EOF
import Foundation

/// 由 build.sh 自动生成 —— 关键文件构建时的 SHA256，App 启动时自校验防篡改。
enum IntegrityChecks {
    static let list: [(path: String, sha256: String)] = [
        ("Contents/Info.plist", "$(hash_file Resources/Info.plist)"),
        ("Contents/Resources/AppIcon.icns", "$(hash_file Resources/AppIcon.icns)"),
        ("Contents/Resources/whale.png", "$(hash_file Resources/whale.png)"),
        ("Contents/Resources/runtime/bundle/node_modules/@deepseek-ai/dsh/lib/bin.js", "$(hash_file "$DSH_BUNDLE_DIR/node_modules/@deepseek-ai/dsh/lib/bin.js")"),
    ]
}
EOF
echo "    已生成 $(wc -l < "$GEN") 行"

echo "==> 编译 Swift 源码"
swiftc \
    -swift-version 5 -parse-as-library -O \
    -target "$TARGET" \
    -framework SwiftUI -framework AppKit -framework WebKit \
    Sources/*.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

echo "==> 组装 .app"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f Resources/whale.png ]; then
    cp Resources/whale.png "$APP_BUNDLE/Contents/Resources/whale.png"
fi

echo "==> 捆绑 Node 运行时 + dsh 包（约 460MB，首次稍慢）"
mkdir -p "$APP_BUNDLE/Contents/Resources/runtime"
cp "$RUNTIME_NODE" "$APP_BUNDLE/Contents/Resources/runtime/node"
mkdir -p "$APP_BUNDLE/Contents/Resources/runtime/bundle"
cp -R "$DSH_BUNDLE_DIR/node_modules" "$APP_BUNDLE/Contents/Resources/runtime/bundle/"
cp "$DSH_BUNDLE_DIR/package.json" "$DSH_BUNDLE_DIR/package-lock.json" \
   "$APP_BUNDLE/Contents/Resources/runtime/bundle/" 2>/dev/null || true

echo "==> 本地签名 (ad-hoc)"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | sed 's/^/    /' || true

echo "==> 制作 DMG"
DMG_STAGE="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGE"; mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
if [ -f README.md ]; then cp README.md "$DMG_STAGE/使用说明.md"; fi
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO -quiet "$DMG_NAME"
rm -rf "$DMG_STAGE"

if [ "$DO_INSTALL" = "1" ]; then
    echo "==> 安装到 /Applications"
    rm -rf "/Applications/$APP_NAME.app" || true
    cp -R "$APP_BUNDLE" "/Applications/" && echo "    已安装: /Applications/$APP_NAME.app"
fi

echo ""
echo "构建完成 ✅"
echo "  App : $(pwd)/$APP_BUNDLE"
echo "  DMG : $(pwd)/$DMG_NAME  ($(du -h "$DMG_NAME" | cut -f1))"
echo "安装: 双击 DMG，把「${APP_NAME}」拖进 Applications（首次打开若提示无法验证开发者，右键→打开即可）"

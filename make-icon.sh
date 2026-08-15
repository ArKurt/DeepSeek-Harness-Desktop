#!/bin/bash
# ============================================================
# 生成 App 图标 AppIcon.icns（SVG → PNG → iconset → icns）
# 优先用 Chrome headless 渲染（支持透明背景，squircle 轮廓正确）；
# 没有 Chrome 时回退 qlmanage。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

OUT="Resources/AppIcon.icns"
SRC="Resources/AppIcon.svg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$SRC" ]; then
    echo "缺少 $SRC，跳过图标生成"
    exit 0
fi

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BASE=""

if [ -x "$CHROME" ]; then
    echo "==> Chrome headless 渲染 SVG → PNG (1024, 透明背景)"
    "$CHROME" --headless --disable-gpu --force-device-scale-factor=1 \
        --default-background-color=00000000 \
        --screenshot="$WORK/icon.png" --window-size=1024,1024 \
        "file://$PWD/$SRC" >/dev/null 2>&1 || true
    sleep 1
    [ -f "$WORK/icon.png" ] && BASE="$WORK/icon.png"
fi

if [ -z "$BASE" ] || [ ! -f "$BASE" ]; then
    echo "==> Chrome 不可用，回退 qlmanage"
    qlmanage -t -s 1024 -o "$WORK" "$SRC" >/dev/null 2>&1
    [ -f "$WORK/AppIcon.svg.png" ] && BASE="$WORK/AppIcon.svg.png"
fi

if [ ! -f "$BASE" ]; then
    echo "图标渲染失败（Chrome 与 qlmanage 均不可用）"
    exit 1
fi

# 统一到 1024x1024
sips -z 1024 1024 "$BASE" --out "$WORK/icon1024.png" >/dev/null

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon1024.png" --out "$ICONSET/icon_${size}x${size}.png"      >/dev/null
    sips -z $((size*2)) $((size*2)) "$WORK/icon1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "图标已生成: $OUT"

#!/bin/bash
# 构建 DeepSeek Harness Web Launcher
# 用法: ./build.sh [install]
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DeepSeek Harness"
CMD="${1:-}"
OUT="dist/${APP_NAME}.app"
ARCH="arm64-apple-macosx13.0"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp Info.plist "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

# 1) AppIcon.icns: assets/AppIcon.svg → png → iconset → icns
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sips -s format png assets/AppIcon.svg --out "$TMP/master.png" >/dev/null
mkdir -p "$TMP/AppIcon.iconset"
for spec in "icon_16x16.png 16" "icon_16x16@2x.png 32" "icon_32x32.png 32" "icon_32x32@2x.png 64" "icon_128x128.png 128" "icon_128x128@2x.png 256" "icon_256x256.png 256" "icon_256x256@2x.png 512" "icon_512x512.png 512" "icon_512x512@2x.png 1024"; do
  set -- $spec
  sips -z "$2" "$2" "$TMP/master.png" --out "$TMP/AppIcon.iconset/$1" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT/Contents/Resources/AppIcon.icns"

# 2) 托盘鲸鱼模板图
sips -s format png assets/WhaleTemplate.svg --out "$OUT/Contents/Resources/WhaleTemplate.png" >/dev/null

# 3) 编译主程序
swiftc -O -target "$ARCH" sources/main.swift -o "$OUT/Contents/MacOS/DeepSeekHarnessApp" -framework AppKit -framework Foundation
chmod 755 "$OUT/Contents/MacOS/DeepSeekHarnessApp"

# 4) ad-hoc 签名(改善系统自动化授权归属)
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1

echo "构建完成: $OUT"
"$OUT/Contents/MacOS/DeepSeekHarnessApp" --check

if [ "$CMD" = "install" ]; then
  DEST="$HOME/Applications/${APP_NAME}.app"
  rm -rf "$DEST"
  cp -R "$OUT" "$DEST"
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$DEST"
  echo "已安装: $DEST"
fi

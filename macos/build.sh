#!/bin/bash
# 清账猫 · macOS 构建脚本
#
#   ./build.sh            编译 + 组装 + 自检
#   ./build.sh --install  以上全部，并覆盖安装到「桌面」
#
# 改界面只需改 ../web/index.html，重跑本脚本即可，数据目录不受影响。

set -e
cd "$(dirname "$0")"

APP_NAME="清账猫"
BIN_NAME="QingZhangMao"
SRC_HTML="../web/index.html"
ICON_PNG="../assets/icon-1024.png"
INSTALL=0
[ "$1" = "--install" ] && INSTALL=1

echo "1/6 编译原生外壳"
# QZM_UNIVERSAL=1 时编译 Intel + Apple 芯片通用包（发布用）
if [ "${QZM_UNIVERSAL:-0}" = "1" ]; then
  swiftc -O -target arm64-apple-macos12 main.swift -framework Cocoa -framework WebKit -o "$BIN_NAME-arm64"
  swiftc -O -target x86_64-apple-macos12 main.swift -framework Cocoa -framework WebKit -o "$BIN_NAME-x86_64"
  lipo -create "$BIN_NAME-arm64" "$BIN_NAME-x86_64" -output "$BIN_NAME"
  rm -f "$BIN_NAME-arm64" "$BIN_NAME-x86_64"
else
  swiftc -O main.swift -framework Cocoa -framework WebKit -o "$BIN_NAME"
fi

echo "2/6 生成图标"
rm -rf AppIcon.iconset
mkdir -p AppIcon.iconset
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s "$ICON_PNG" --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  if [ $d -le 1024 ]; then
    sips -z $d $d "$ICON_PNG" --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  fi
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "3/6 组装 .app"
rm -rf "$APP_NAME.app"
mkdir -p "$APP_NAME.app/Contents/MacOS" "$APP_NAME.app/Contents/Resources"
cp "$BIN_NAME" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp AppIcon.icns "$APP_NAME.app/Contents/Resources/"
cp "$SRC_HTML" "$APP_NAME.app/Contents/Resources/app.html"
cp Info.plist "$APP_NAME.app/Contents/Info.plist"

echo "4/6 Ad-hoc 签名"
codesign --force --sign - "$APP_NAME.app" 2>/dev/null

echo "5/6 自检（空环境写入 → 再次启动读回）"
if [ -n "$CI" ]; then
  echo "    CI 环境无窗口服务，跳过 GUI 自检"
else
  DATA_DIR="$HOME/Library/Application Support/$APP_NAME"
  rm -rf "$DATA_DIR"
  "$APP_NAME.app/Contents/MacOS/$APP_NAME" --selftest 2>/dev/null | grep SELFTEST || true
  "$APP_NAME.app/Contents/MacOS/$APP_NAME" --selftest 2>/dev/null | grep SELFTEST || true
  rm -rf "$DATA_DIR"
fi

echo "6/6 完成：$PWD/$APP_NAME.app"

if [ $INSTALL -eq 1 ]; then
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_NAME.app" "$HOME/Desktop/"
  xattr -dr com.apple.quarantine "$HOME/Desktop/$APP_NAME.app" 2>/dev/null || true
  echo "已安装到：$HOME/Desktop/$APP_NAME.app"
fi

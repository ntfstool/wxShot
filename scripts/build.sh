#!/bin/bash
# 构建 wxShot.app（可选通用二进制 / Developer ID 签名 / DMG / 公证）。
# 用法: scripts/build.sh [--universal] [--sign "Developer ID Application: …"] [--dmg] [--notarize] [--mas]
# 默认：当前架构、ad-hoc 签名（本机可运行，不能分发）。
# --mas：构建 Mac App Store 版（沙盒、编译标志 MAS、去掉自更新入口），签名用 "3rd Party Mac Developer Application"，另见 scripts/mas.sh。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

UNIVERSAL=0; SIGN="-"; DMG=0; NOTARIZE=0; MAS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --universal) UNIVERSAL=1;;
    --sign) SIGN="$2"; shift;;
    --dmg) DMG=1;;
    --notarize) NOTARIZE=1;;
    --mas) MAS=1;;
    *) echo "未知参数: $1"; exit 2;;
  esac; shift
done

NAME="wxShot"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/wxShot/App/Info.plist)"
BUILD_ARGS=(-c release --product "$NAME")
[ "$UNIVERSAL" = 1 ] && BUILD_ARGS+=(--arch arm64 --arch x86_64)
[ "$MAS" = 1 ] && BUILD_ARGS+=(-Xswiftc -DMAS)

echo "▶ swift build (${BUILD_ARGS[*]})"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

OUT="dist"; [ "$MAS" = 1 ] && OUT="dist/mas"
APP="$OUT/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
cp Sources/wxShot/App/Info.plist "$APP/Contents/Info.plist"
[ -n "${BUILD_NUMBER:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# 本地化与 SwiftPM 资源包（PermissionFlow 的授权面板需要 Bundle.module，缺了会在首次弹面板时崩溃）
for lproj in Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
FOUND=0
for b in "$BIN"/*_PermissionFlow.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/" && FOUND=1; done
[ "$FOUND" = 1 ] || { echo "error: 找不到 PermissionFlow 资源包，授权面板会崩溃" >&2; exit 1; }

echo "▶ 图标"
[ -f dist/AppIcon.icns ] || swift scripts/make_icon.swift "viewfinder" "messages" dist/AppIcon.icns
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ 签名 ($SIGN)"
if [ "$SIGN" = "-" ]; then
  codesign --force --deep -s - "$APP"
elif [ "$MAS" = 1 ]; then
  codesign --force --deep --options runtime --entitlements scripts/mas.entitlements -s "$SIGN" "$APP"
else
  codesign --force --deep --options runtime --timestamp --entitlements scripts/entitlements.plist -s "$SIGN" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "   架构: $(lipo -archs "$APP/Contents/MacOS/$NAME")"

[ "$NOTARIZE" = 1 ] && { echo "▶ 公证并盖章 App"; scripts/notarize.sh "$APP"; }

if [ "$DMG" = 1 ]; then
  STAGE="$OUT/.dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  DMG_PATH="$OUT/$NAME.dmg"; rm -f "$DMG_PATH"
  hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGE"
  [ "$SIGN" != "-" ] && codesign --force --sign "$SIGN" --timestamp "$DMG_PATH"
  [ "$NOTARIZE" = 1 ] && { echo "▶ 公证并盖章 DMG"; scripts/notarize.sh "$DMG_PATH"; }
  echo "▶ DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))   版本 $VERSION"
fi
echo "✅ $APP ($(du -sh "$APP" | cut -f1))"

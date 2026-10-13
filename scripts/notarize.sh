#!/bin/bash
# 公证并盖章。用法: tools/notarize.sh <path-to.app|.dmg> [keychain-profile]
# 前提：已用 Developer ID 签名（build.sh --sign）。keychain-profile 默认沿用 NTFSTool 的 MY_NTFSTOOL。
set -euo pipefail
TARGET="${1:?用法: tools/notarize.sh <.app|.dmg> [keychain-profile]}"; PROFILE="${2:-MY_NTFSTOOL}"
case "$TARGET" in
  *.app) ZIP="$(mktemp -d)/notarize.zip"; ditto -c -k --keepParent "$TARGET" "$ZIP"; SUBMIT="$ZIP";;
  *.dmg) SUBMIT="$TARGET";;
  *) echo "只支持 .app 或 .dmg"; exit 2;;
esac
xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
spctl -a -vvv -t exec "$TARGET" 2>&1 || true

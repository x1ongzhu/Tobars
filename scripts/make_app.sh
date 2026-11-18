#!/bin/bash
# 打包成可双击的菜单栏 app：build/Tobars.app
# 使用 ad-hoc 签名；没有 Developer ID 也能在本机运行。
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

CONFIG="${1:-release}"
APP="build/Tobars.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Tobars" "$APP/Contents/MacOS/Tobars"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -d ".build/$CONFIG/Tobars_Tobars.bundle" ]; then
    cp -R ".build/$CONFIG/Tobars_Tobars.bundle" "$APP/Contents/Resources/"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null

# 优先用开发者的 Apple Development 身份签名。用证书的 SHA-1 而不是名字，
# 避免中文用户名在不同 locale 下被重新编码导致 "no identity found"。
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" --identifier ai.tobars.app "$APP" >/dev/null
    echo "签名身份：$IDENTITY"
else
    codesign --force --deep --sign - --identifier ai.tobars.app "$APP" >/dev/null
    echo "签名身份：ad-hoc（未找到 Apple Development 证书）"
fi

echo "已生成 ${APP}，配置：${CONFIG}"
echo "打开：open $APP"

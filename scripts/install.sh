#!/bin/zsh
# 构建 Release 版并安装到“应用程序”文件夹。
# 用法：scripts/install.sh
set -euo pipefail

ROOT=${0:A:h:h}
cd $ROOT
xcodegen generate --quiet

# 有 Apple Development 证书就用它签，重新构建后钥匙串不会再次询问是否允许读取证书密码；
# 没有就用临时签名。
IDENTITY=$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')
IDENTITY=${IDENTITY:--}

xcodebuild -project IPAInstaller.xcodeproj -scheme IPAInstaller -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="$IDENTITY" build -quiet

APP="/Applications/IPA 安装器.app"
osascript -e 'tell application id "com.elsterlee.IPAInstaller" to quit' 2>/dev/null || true
rm -rf "$APP"
ditto build/Build/Products/Release/IPAInstaller.app "$APP"
echo "已安装到 $APP"
open "$APP"

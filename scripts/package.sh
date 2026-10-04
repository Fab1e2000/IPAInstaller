#!/bin/zsh
# 构建通用（Apple 芯片 + Intel）Release 版，临时签名后打包为 dmg，输出到 dist/。
# 用法：scripts/package.sh
set -euo pipefail

ROOT=${0:A:h:h}
cd $ROOT
xcodegen generate --quiet
rm -rf build/Build/Products/Release
xcodebuild -project IPAInstaller.xcodeproj -scheme IPAInstaller -configuration Release \
  -derivedDataPath build ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" CODE_SIGN_IDENTITY=- build -quiet

APP=build/Build/Products/Release/IPAInstaller.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $APP/Contents/Info.plist)
STAGE=$(mktemp -d -t ipainstaller-dmg)
trap 'rm -rf "$STAGE"' EXIT
ditto $APP "$STAGE/IPA 安装器.app"
ln -s /Applications "$STAGE/应用程序"

mkdir -p dist
OUTPUT=$ROOT/dist/IPAInstaller-macOS-v$VERSION.dmg
hdiutil create -volname "IPA 安装器 $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUTPUT" -quiet
hdiutil verify "$OUTPUT" -quiet
(cd dist && shasum -a 256 *.dmg > SHA256SUMS.txt)
echo "已生成 $OUTPUT"
lipo -archs "$APP/Contents/MacOS/IPAInstaller"

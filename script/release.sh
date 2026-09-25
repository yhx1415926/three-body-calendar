#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.0.0"
APP_NAME="三体人的万年历"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_NAME="TrisolarisCalendar-v$VERSION-macos-arm64.dmg"
SOURCE_ROOT_NAME="TrisolarisCalendar-v$VERSION-source"
SOURCE_NAME="$SOURCE_ROOT_NAME.zip"
CHECKSUM_NAME="TrisolarisCalendar-v$VERSION-SHA256SUMS.txt"

cd "$ROOT_DIR"
/bin/mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/module-cache"
BUILD_ARGS=(--build-system native --disable-sandbox --scratch-path "$ROOT_DIR/.build" --cache-path "$ROOT_DIR/.build/swiftpm-cache")
/usr/bin/xcrun swift test "${BUILD_ARGS[@]}"
/usr/bin/xcrun swift run "${BUILD_ARGS[@]}" -c release ScienceCheck 100

# Keep build_and_run.sh's default debug workflow intact.
TRISOLARIS_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build-only

actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$actual_version" != "$VERSION" ]]; then
  echo "App 版本 $actual_version 与发布版本 $VERSION 不一致。" >&2
  exit 1
fi

architectures="$(/usr/bin/lipo -archs "$APP_BUNDLE/Contents/MacOS/TrisolarisApp")"
if [[ "$architectures" != "arm64" ]]; then
  echo "预期仅有 arm64 架构，实际为: $architectures" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/private/tmp}/trisolaris-release.XXXXXX")"
mount_dir="$work_dir/mount"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    /usr/bin/hdiutil detach "$mount_dir" >/dev/null || true
  fi
  /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

dmg_contents="$work_dir/dmg-contents"
/bin/mkdir -p "$dmg_contents/.background" "$mount_dir"
/usr/bin/ditto "$APP_BUNDLE" "$dmg_contents/$APP_NAME.app"
/bin/ln -s /Applications "$dmg_contents/Applications"
/bin/cp "$ROOT_DIR/Resources/DmgBackground.png" "$dmg_contents/.background/background.png"
/usr/bin/hdiutil create -volname "$APP_NAME v$VERSION" -srcfolder "$dmg_contents" \
  -format UDRW -ov "$work_dir/layout.dmg" >/dev/null
/usr/bin/hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$mount_dir" \
  "$work_dir/layout.dmg" >/dev/null
mounted=true
/usr/bin/osascript "$ROOT_DIR/script/set_dmg_layout.applescript" "$mount_dir" "$APP_NAME"
/usr/bin/hdiutil detach "$mount_dir" >/dev/null
mounted=false
/usr/bin/hdiutil convert "$work_dir/layout.dmg" -format UDZO -o "$work_dir/$DMG_NAME" >/dev/null
/usr/bin/hdiutil verify "$work_dir/$DMG_NAME" >/dev/null

source_root="$work_dir/$SOURCE_ROOT_NAME"
/bin/mkdir -p "$source_root"
for entry in Package.swift README.md LICENSE THIRD_PARTY_NOTICES.md .gitignore Resources Sources Tests Vendor script; do
  /usr/bin/rsync -a --exclude '.DS_Store' "$ROOT_DIR/$entry" "$source_root/"
done
/usr/bin/ditto --norsrc -c -k --keepParent "$source_root" "$work_dir/$SOURCE_NAME"
/usr/bin/unzip -tq "$work_dir/$SOURCE_NAME" >/dev/null
if /usr/bin/unzip -Z1 "$work_dir/$SOURCE_NAME" | /usr/bin/grep -Eq '(^|/)(\._[^/]*|__MACOSX|\.DS_Store|\.build|\.swiftpm|dist|\.git)(/|$)'; then
  echo "源码压缩包包含本地构建文件或 macOS 元数据。" >&2
  exit 1
fi

/bin/mv -f "$work_dir/$DMG_NAME" "$ROOT_DIR/dist/$DMG_NAME"
/bin/mv -f "$work_dir/$SOURCE_NAME" "$ROOT_DIR/dist/$SOURCE_NAME"
(
  cd "$ROOT_DIR/dist"
  /usr/bin/shasum -a 256 "$DMG_NAME" "$SOURCE_NAME" > "$CHECKSUM_NAME"
)
/bin/rm -f "$ROOT_DIR/dist/TrisolarisCalendar-v$VERSION-macos-arm64.zip" \
  "$ROOT_DIR/dist/TrisolarisCalendar-v$VERSION-macos-arm64.zip.sha256"

echo "App 附件: $ROOT_DIR/dist/$DMG_NAME"
echo "源码附件: $ROOT_DIR/dist/$SOURCE_NAME"
echo "SHA-256: $ROOT_DIR/dist/$CHECKSUM_NAME"
echo "此 App 与 DMG 尚未经过 Developer ID 签名或 Apple 公证。"

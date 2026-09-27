#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="三体人的万年历"
PROCESS_NAME="TrisolarisApp"
BUNDLE_ID="org.trisolaris.calendar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$PROCESS_NAME"
BUILD_CONFIGURATION="${TRISOLARIS_BUILD_CONFIGURATION:-release}"
if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  BUILD_CONFIGURATION="${TRISOLARIS_BUILD_CONFIGURATION:-debug}"
fi

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build-only) ;;
  *)
    echo "用法: $0 [--verify|--debug|--logs|--telemetry|--build-only]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/module-cache"

if [[ "$MODE" != "--build-only" ]]; then
  /usr/bin/pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
fi
BUILD_ARGS=(--build-system native --disable-sandbox --scratch-path "$ROOT_DIR/.build" --cache-path "$ROOT_DIR/.build/swiftpm-cache" -c "$BUILD_CONFIGURATION")
/usr/bin/xcrun swift build "${BUILD_ARGS[@]}" --product "$PROCESS_NAME"
BUILD_DIRECTORY="$(/usr/bin/xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"

# Stage only the bundle owned by this project; never replace other dist files.
if [[ -d "$APP_BUNDLE" ]]; then
  /bin/rm -rf "$APP_BUNDLE"
fi
/bin/mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"
/bin/cp "$BUILD_DIRECTORY/$PROCESS_NAME" "$APP_BINARY"
/bin/chmod +x "$APP_BINARY"
if [[ -d "$ROOT_DIR/Resources" ]]; then
  /bin/cp -R "$ROOT_DIR/Resources/." "$APP_CONTENTS/Resources/"
fi
for resource_bundle in "$BUILD_DIRECTORY"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  /bin/cp -R "$resource_bundle" "$APP_CONTENTS/Resources/"
done
/bin/cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$ROOT_DIR/README.md" "$APP_CONTENTS/Resources/"

cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$PROCESS_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 三体人的万年历 contributors. GPL-3.0-or-later.</string>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>三体万年历项目</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>org.trisolaris.calendar.project</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key>
  <array><dict>
    <key>UTTypeIdentifier</key><string>org.trisolaris.calendar.project</string>
    <key>UTTypeDescription</key><string>三体万年历项目</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>trisolaris</string></array>
      <key>public.mime-type</key><string>application/vnd.trisolaris.calendar</string>
    </dict>
  </dict></array>
</dict>
</plist>
PLIST
/usr/bin/plutil -lint "$APP_CONTENTS/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run) open_app ;;
  --build-only) echo "已生成: $APP_BUNDLE" ;;
  --debug|debug) /usr/bin/xcrun lldb -- "$APP_BINARY" ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for attempt in {1..30}; do
      if /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null; then
        echo "已启动并确认进程: $APP_NAME"
        exit 0
      fi
      sleep 0.2
    done
    echo "应用构建成功，但未检测到运行进程。可使用 --debug 进一步检查。" >&2
    exit 1
    ;;
esac

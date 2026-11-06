#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MODE="${1:-run}"
if [[ $# -gt 0 ]]; then shift; fi
APP_NAME=PaperReview
CONFIGURATION=debug
DEFAULT_BUILD_DIR="$HOME/Library/Developer/PaperReview/Build"
APP_LINK="$ROOT/dist/$APP_NAME.app"
if [[ "$MODE" == "--release" ]]; then
  CONFIGURATION=release
  DEFAULT_BUILD_DIR="$HOME/Library/Developer/PaperReview/Release"
  APP_LINK="$ROOT/dist/$APP_NAME-Release.app"
fi
if [[ "$MODE" == "--ui-preview" ]]; then
  DEFAULT_BUILD_DIR="$HOME/Library/Developer/PaperReview/UIPreview"
  APP_LINK="$ROOT/dist/$APP_NAME-UI-Preview.app"
fi
# File Provider rewrites FinderInfo on .app folders under Documents, invalidating
# their resource seals. Keep the runnable build in macOS's local developer area;
# the project's established dist entrypoint remains a link to that same app.
BUILD_DIR="${PAPERREVIEW_APP_BUILD_DIR:-$DEFAULT_BUILD_DIR}"
APP="$BUILD_DIR/$APP_NAME.app"
case "$MODE" in
  run|--build-only|--verify|--release|--ui-preview|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [run|--build-only|--verify|--release|--ui-preview|--debug|--logs|--telemetry] [app arguments]" >&2; exit 2;;
esac
check_owner() {
  local project
  project="$(/usr/libexec/PlistBuddy -c 'Print :PaperReviewProjectRoot' "$1/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -z "$project" && -f "$(dirname "$1")/.paperreview-project-root" ]]; then
    project="$(cat "$(dirname "$1")/.paperreview-project-root")"
  fi
  [[ "$project" == "$ROOT" ]] || { echo "构建目录已有其他项目的应用，未覆盖：$1。请设置 PAPERREVIEW_APP_BUILD_DIR。" >&2; exit 1; }
}
if [[ -e "$APP" ]]; then check_owner "$APP"; fi
if [[ -L "$APP_LINK" ]]; then
  [[ "$(readlink "$APP_LINK")" == "$APP" ]] || { echo "dist应用链接指向其他构建位置，未更改：$APP_LINK" >&2; exit 1; }
elif [[ -e "$APP_LINK" ]]; then check_owner "$APP_LINK"; fi
# Swift Build currently links a 14.0 deployment target with an SDK stamp of
# 14.0 even when compiling against the current SDK. AppKit then selects its
# legacy appearance. Pass the real SDK to the linker; keep deployment at 14.0.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
BUILD_FLAGS=(--sdk "$SDK_PATH" -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
if [[ "$CONFIGURATION" == release ]]; then
  swift build "${BUILD_FLAGS[@]}" -c release -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
else
  swift build "${BUILD_FLAGS[@]}"
fi
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
BUILT_SDK="$(xcrun vtool -show-build "$BINARY" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$BUILT_SDK" != "$SDK_VERSION" ]]; then
  echo "构建 SDK 记录异常（$BUILT_SDK，预期 $SDK_VERSION），未替换现有应用。" >&2; exit 1
fi
source "$ROOT/script/development_signing.sh"
CURRENT_SIGNER=""
CURRENT_REQUIREMENT=""
if [[ -e "$APP" ]]; then
  if SIGNATURE="$(/usr/bin/codesign --display --verbose=2 "$APP" 2>&1)"; then
    CURRENT_SIGNER="$(printf '%s\n' "$SIGNATURE" | awk '/^Authority=/ { sub(/^Authority=/, ""); print; exit }')"
    CURRENT_REQUIREMENT="$(/usr/bin/codesign --display --requirements - "$APP" 2>&1 | sed -n '/^designated => /p')"
  fi
fi
SIGNING_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
SIGNING_IDENTITY="$(select_signing_identity "$SIGNING_IDENTITIES" "$CURRENT_SIGNER")"
if [[ "$MODE" == "--ui-preview" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo '界面验证构建需要稳定的开发证书；未回退临时签名，避免更新后反复请求文稿权限。' >&2
  exit 1
fi
mkdir -p "$BUILD_DIR"
STAGE="$(mktemp -d "$BUILD_DIR/.PaperReview.XXXXXX")"
STAGED_APP="$STAGE/$APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BINARY" "$STAGED_APP/Contents/MacOS/$APP_NAME"
if [[ "$CONFIGURATION" == release ]]; then /usr/bin/strip -S "$STAGED_APP/Contents/MacOS/$APP_NAME"; fi
chmod 755 "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp script/start_models.sh script/stop_models.sh script/setup_models_modelscope.sh script/install_runtime.sh script/download_file.sh script/download_supervisor.sh script/model_downloads.tsv "$STAGED_APP/Contents/Resources/"
cp docs/THIRD_PARTY.md "$STAGED_APP/Contents/Resources/"
# Compile the layered artwork rather than flattening it: macOS selects its
# Aqua, Dark Aqua and tintable renditions. actool also emits the legacy ICNS.
xcrun actool "$ROOT/Assets/PaperReview.icon" \
  --compile "$STAGED_APP/Contents/Resources" \
  --output-partial-info-plist "$STAGE/icon-info.plist" \
  --app-icon PaperReview --platform macosx --minimum-deployment-target 14.0 \
  --target-device mac --errors --warnings --output-format human-readable-text
/usr/bin/python3 - "$STAGED_APP/Contents/Info.plist" "$ROOT" "$CONFIGURATION" "$STAGE/icon-info.plist" "$MODE" <<'PY'
import os,plistlib,sys
with open(sys.argv[1], 'wb') as f:
    info=dict(CFBundleExecutable='PaperReview', CFBundleIdentifier='local.paperreview.mac',
        CFBundleName='作文批阅', CFBundleDisplayName='作文批阅', CFBundlePackageType='APPL',
        CFBundleShortVersionString='0.1.4', CFBundleVersion='5', LSMinimumSystemVersion='14.0',
        NSPrincipalClass='NSApplication', NSHighResolutionCapable=True,
        NSAppTransportSecurity=dict(NSAllowsLocalNetworking=True))
    if sys.argv[5]=='--ui-preview':
        info.update(CFBundleIdentifier='local.paperreview.ui-v12-qa',
            CFBundleName='作文批阅·界面验证',CFBundleDisplayName='作文批阅·界面验证')
    elif sys.argv[3]=='debug': info['PaperReviewProjectRoot']=sys.argv[2]
    with open(sys.argv[4], 'rb') as icons: info.update(plistlib.load(icons))
    plistlib.dump(info, f)
os.unlink(sys.argv[4])
PY
# Validate a fresh bundle before stopping/replacing the usable application.
# A development signer keeps a stable designated requirement across rebuilds.
# Without a certificate the established ad-hoc development route still works.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo '使用 ad-hoc 签名；重新构建后系统权限可能需要重新确认。可通过 PAPERREVIEW_SIGNING_IDENTITY 指定开发证书。' >&2
fi
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"
NEXT_REQUIREMENT="$(/usr/bin/codesign --display --requirements - "$STAGED_APP" 2>&1 | sed -n '/^designated => /p')"
if ! signing_continuity_is_valid "$CURRENT_SIGNER" "$CURRENT_REQUIREMENT" "$NEXT_REQUIREMENT"; then
  echo '开发签名身份发生变化，已停止替换以保留原有权限。请恢复原证书，或明确指定 PAPERREVIEW_SIGNING_IDENTITY。' >&2
  exit 1
fi
for pid in $(pgrep -x "$APP_NAME" || true); do
  command="$(ps -p "$pid" -o command= || true)"
  if [[ "$command" == "$APP/Contents/MacOS/$APP_NAME"* || "$command" == "$APP_LINK/Contents/MacOS/$APP_NAME"* ]]; then
    kill -TERM "$pid"
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo '应用仍在退出，未替换。请稍后重试。' >&2; exit 1
    fi
  fi
done
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
if [[ -e "$APP" ]]; then
  mkdir -p "$BUILD_DIR/Previous"
  mv "$APP" "$BUILD_DIR/Previous/$APP_NAME-$STAMP.app"
fi
mv "$STAGED_APP" "$APP"
printf '%s\n' "$ROOT" > "$BUILD_DIR/.paperreview-project-root"
rmdir "$STAGE"
mkdir -p "$ROOT/dist"
if [[ ! -L "$APP_LINK" ]]; then
  if [[ -e "$APP_LINK" ]]; then
    mkdir -p "$ROOT/dist/Previous"
    mv "$APP_LINK" "$ROOT/dist/Previous/$APP_NAME-$STAMP.app"
  fi
  ln -s "$APP" "$APP_LINK"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
case "$MODE" in
  --build-only|--release) echo "$APP";;
  run) /usr/bin/open -n "$APP" --args "$@";;
  --ui-preview)
    PREVIEW_HOME="$HOME/Library/Application Support/PaperReview-UIPreview"
    /usr/bin/open -n "$APP" --args --data-root "$PREVIEW_HOME/Assignments" -modelHome "$PREVIEW_HOME/Models" "$@";;
  --verify)
    /usr/bin/open -n "$APP" --args "$@"
    for _ in 1 2 3 4 5; do
      if ps -axo command= | grep -F -- "$APP/Contents/MacOS/$APP_NAME" | grep -Fvq -- 'grep -F'; then exit 0; fi
      sleep 1
    done
    echo '应用未保持运行，请检查系统崩溃记录。' >&2; exit 1;;
  --debug) lldb -- "$APP/Contents/MacOS/$APP_NAME" "$@";;
  --logs) /usr/bin/open -n "$APP" --args "$@"; /usr/bin/log stream --info --style compact --predicate 'process == "PaperReview"';;
  --telemetry) /usr/bin/open -n "$APP" --args "$@"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.paperreview.mac"';;
esac

#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
./script/build_and_run.sh --release
APP="${PAPERREVIEW_APP_BUILD_DIR:-$HOME/Library/Developer/PaperReview/Release}/PaperReview.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp/}PaperReview-release.XXXXXX")"
PAYLOAD="$STAGE/PaperReview-$VERSION"
mkdir "$PAYLOAD"
/usr/bin/ditto "$APP" "$PAYLOAD/PaperReview.app"
cp docs/RELEASE_USAGE.txt "$PAYLOAD/使用说明.txt"
/usr/bin/codesign --verify --deep --strict "$PAYLOAD/PaperReview.app"
mkdir -p "$ROOT/dist/release"
ARCHIVE="$ROOT/dist/release/PaperReview-$VERSION-macOS-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PAYLOAD" "$ARCHIVE"
echo "$ARCHIVE"

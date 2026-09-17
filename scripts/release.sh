#!/usr/bin/env bash
#
# 릴리스 빌드 → JinMac.app → zip + SHA-256. 요구사항 10.2. 사람이 실행한다.
#
#   ./scripts/release.sh
#
# 개발자 등록을 하지 않으므로 서명은 영구히 ad-hoc이고 공증 단계가 없다 (요구사항 2장, 10.1).
# 받는 사람은 "확인되지 않은 개발자" 경고를 스스로 넘겨야 한다 (README 설치 안내).
# 서명이 없으면 변조 여부를 확인할 수 없으므로, 체크섬을 릴리스 노트에 함께 게시한다.
#
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE="build/JinMac.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/JinMac.app"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen이 없습니다. 'brew install xcodegen' 후 다시 실행하세요." >&2
    exit 1
fi

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "error: project.yml에서 버전을 읽지 못했습니다." >&2; exit 1; }

echo "==> JinMac $VERSION / ad-hoc 서명"

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT_DIR"

echo "==> 아카이브"
xcodebuild archive \
    -project JinMac.xcodeproj \
    -scheme JinMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath build \
    -quiet

mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE/Products/Applications/JinMac.app" "$APP"

# 아카이브 산출물을 그대로 믿지 않고 다시 서명한다.
# Xcode는 ad-hoc 서명 시 Hardened Runtime을 꺼 버리는 경우가 있어, 여기서 확실히 켠다.
# 미서명 바이너리는 Apple Silicon에서 실행 자체가 거부된다 (요구사항 10.1).
echo "==> 서명"
codesign --force --options runtime \
    --entitlements App/Resources/JinMac.entitlements \
    --timestamp=none \
    --sign - \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> 확인"
lipo -archs "$APP/Contents/MacOS/JinMac"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature)'
# macOS 14~15에서도 실행되려면 Foundation Models가 약한 링크여야 한다 (요구사항 8장 호환성)
if otool -l "$APP/Contents/MacOS/JinMac" | grep -A2 LC_LOAD_DYLIB | grep -q FoundationModels; then
    echo "error: FoundationModels가 강한 링크입니다. macOS 26 미만에서 실행이 거부됩니다." >&2
    exit 1
fi
du -sh "$APP" | awk '{print "  크기: " $1}'

ZIP="build/JinMac-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "JinMac-$VERSION.zip" > "JinMac-$VERSION.zip.sha256")

echo
echo "==> 완료: $ZIP"
echo "    SHA-256: $(cut -d' ' -f1 "$ZIP.sha256")"
echo "    릴리스 노트에 체크섬과 README 설치 안내 링크를 함께 올리세요."

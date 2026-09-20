#!/usr/bin/env bash
#
# 릴리스 빌드 → JinMac.app → zip + SHA-256. 요구사항 10.2. 사람이 실행한다.
#
#   ./scripts/release.sh
#       키체인에 "JinMac Self-Signed" 인증서가 있으면 그것으로 서명한다. 없으면 ad-hoc으로
#       떨어지면서 경고를 남긴다.
#
#   SIGN_IDENTITY="Developer ID Application: 이름 (TEAMID)" ./scripts/release.sh
#       유료 등록 이후를 위한 통로다. 공증(notarytool)과 타임스탬프는 아직 붙이지 않는다
#       (요구사항 14.1).
#
# 개발자 등록을 하지 않으므로 공증 단계가 없고, 받는 사람은 "확인되지 않은 개발자" 경고를 스스로
# 넘겨야 한다 (README 설치 안내). 자체 서명 인증서도 이 경고를 없애 주지 않는다.
# 체크섬을 릴리스 노트에 함께 게시해 변조 여부를 확인할 수 있게 한다.
#
# 그런데도 인증서로 서명하는 이유는 **지정 요구사항을 버전 사이에 고정하기 위해서**다
# (요구사항 14.5a). ad-hoc 서명에는 Team ID가 없어 macOS가 권한을 바이너리의 cdhash에 묶는데,
# 이 값은 코드가 바뀌면 함께 바뀐다. 그러면 릴리스를 올릴 때마다 SMAppService 로그인 항목 등록이
# 풀린다 (F-11). JinMac은 1~2주를 이어 기록해야 판정이 나오므로, 등록이 풀리면 사용자는 앱이
# 멈춘 줄도 모른 채 구멍 난 데이터로 검진을 마치게 된다.
#
set -euo pipefail

cd "$(dirname "$0")/.."

SELF_SIGNED_CN="JinMac Self-Signed"
ARCHIVE="build/JinMac.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/JinMac.app"

# 서명 주체를 정한다. 명시적으로 넘긴 값이 가장 우선한다.
#
# `-v`(유효한 신원만)를 쓰지 않는 이유가 있다. 자체 서명 인증서는 루트가 신뢰되지 않아서
# `find-identity -v`가 0건으로 보고한다(CSSMERR_TP_NOT_TRUSTED). 그런데 codesign은 그 상태로도
# 정상적으로 서명하고 `--verify --strict`도 통과한다. 신뢰 설정은 필요하지 않다.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -qF "$SELF_SIGNED_CN"; then
        SIGN_IDENTITY="$SELF_SIGNED_CN"
    else
        SIGN_IDENTITY="-"
        echo "warning: 키체인에 \"$SELF_SIGNED_CN\" 인증서가 없어 ad-hoc으로 서명합니다." >&2
        echo "         이 배포본을 설치한 사용자는 다음 릴리스에서 로그인 항목을 다시" >&2
        echo "         허용해야 하고, 그 전까지 재부팅 뒤 수집이 재개되지 않습니다." >&2
        echo "         docs/development.md의 \"배포 서명 인증서\" 절을 보십시오." >&2
    fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen이 없습니다. 'brew install xcodegen' 후 다시 실행하세요." >&2
    exit 1
fi

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "error: project.yml에서 버전을 읽지 못했습니다." >&2; exit 1; }

echo "==> JinMac $VERSION / 서명 ID: $SIGN_IDENTITY"

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

# 아카이브 산출물을 그대로 믿지 않고 다시 서명한다. 아카이브는 project.yml의
# `CODE_SIGN_IDENTITY: "-"` 때문에 항상 ad-hoc으로 나오고, 진짜 서명은 여기서 한다.
# Xcode는 ad-hoc 서명 시 Hardened Runtime을 꺼 버리는 경우가 있어, 여기서 확실히 켠다.
# 미서명 바이너리는 Apple Silicon에서 실행 자체가 거부된다 (요구사항 10.1).
#
# 타임스탬프를 붙이지 않는 이유는, 애플의 타임스탬프 서버가 애플이 발급한 인증서만 스탬프하기
# 때문이다. ad-hoc과 자체 서명에 붙이려고 하면 서명 자체가 실패한다.
echo "==> 서명"
codesign --force --options runtime \
    --entitlements App/Resources/JinMac.entitlements \
    --timestamp=none \
    --sign "$SIGN_IDENTITY" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> 확인"
lipo -archs "$APP/Contents/MacOS/JinMac"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Identifier|CodeDirectory|Signature)'
# 지정 요구사항. 이 줄이 지난 릴리스와 같아야 사용자의 로그인 항목 등록이 유지된다.
# cdhash로 나오면 인증서가 적용되지 않은 것이고, 이대로 배포하면 사용자 설정이 초기화된다.
echo "  지정 요구사항:"
# ad-hoc은 "# designated => ", 인증서 서명은 "designated => "로 출력된다. 둘 다 받는다.
codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => /    /p'
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
if [ "$SIGN_IDENTITY" != "-" ]; then
    echo
    echo "    위의 지정 요구사항이 지난 릴리스와 같은지 확인하세요."
    echo "    달라졌다면 배포를 멈춰야 합니다. 사용자의 로그인 항목 등록이 초기화됩니다."
fi

# JinMac 개발 문서

사용자용 안내는 [README.md](../README.md)에 있습니다.

```sh
brew install xcodegen          # 빌드 도구. 앱 자체의 서드파티 의존성은 0개

./scripts/build.sh             # 빌드 → build/Build/Products/Debug/JinMac.app
./scripts/test.sh              # CoreKit 테스트 + 지식 베이스 자체 검사
./scripts/test.sh VerdictTests # 스위트 하나만
./scripts/release.sh           # 릴리스 빌드 → 자체 서명 인증서 → zip + SHA-256
open JinMac.xcodeproj          # Xcode에서 열기 (build.sh가 먼저 만들어 둡니다)
```

`JinMac.xcodeproj`는 **자동으로 생성되는 파일**입니다. 빌드 설정은
[project.yml](../project.yml)에서만 바꿉니다.

## 구조

```
App/       메뉴바 UI, 메인 창                SwiftUI + 필요한 곳만 AppKit
CoreKit/   로직 패키지 (모듈 7개)            UI 의존 없음. 앱 없이 swift test로 검증
scripts/   빌드·테스트·릴리스·지식 베이스 도구
kb/wiki/   요구사항, 결정, 검토 의견         지식 그래프가 관계를 잇는다
kb/raw/    외부 원자료 (요구사항 원문 등)    쓴 뒤 고치지 않는다
docs/      개발 문서(이 파일)
```

### CoreKit 모듈

의존 방향이 곧 설계 제약입니다. 화살표를 거스르는 import는 넣지 않습니다.

```
Model ← Collector            수집: IOKit·sysctl·비공개 API는 여기서만
Model ← Store                저장: 시스템 SQLite3
Model ← Workload ← Verdict   판정: 결정론. Collector·Store를 모른다
Verdict ← Report ← Narrator  문장: Narrator는 판정 결과만 받는다
```

| 모듈 | 요구사항 | 지금 들어 있는 것 |
|---|---|---|
| `Model` | 공용 | `Sample`(읽지 못한 값은 `nil`), `ResourceKind`, `Grade`, `Judgement` |
| `Collector` | F-01\~F-11 | `Sampler` 프로토콜, `MemorySampler`, `CPUSampler`(`CoreTopology`로 P·E 구분) |
| `Store` | 7장 | `SampleStore`: WAL 모드로 열기, `user_version` |
| `Workload` | F-20, F-21 | `WorkloadCategory` 10종, 빈 `app-categories.json` |
| `Verdict` | F-30\~F-34, 5장 | `rules.json`(5장 초기값), 경계값 판정과 보류 |
| `Report` | F-40\~F-44, F-50\~F-53 | `CheckupReport`, 키를 정렬한 JSON 인코더 |
| `Narrator` | 6장 | `NarratorAvailability`: Foundation Models 가용성과 불가 사유 |

## 데이터 경로

검진 데이터는 `~/Library/Application Support/JinMac/jinmac.sqlite`에 저장합니다.
테스트나 실험에서 이 경로를 건드리지 않으려면 `JINMAC_DATA_DIR`로 다른 디렉터리를 넘깁니다.

```sh
JINMAC_DATA_DIR=~/tmp/jinmac-dev open build/Build/Products/Debug/JinMac.app
```

## Foundation Models 약한 링크

최소 지원 OS는 macOS 14이고 Foundation Models는 macOS 26부터 있습니다. 프레임워크가 강하게
링크되면 macOS 14와 15에서는 앱이 아예 실행되지 않습니다. `Narrator` 모듈 밖에서
`FoundationModels`를 import하지 않고, 모든 사용을 `@available(macOS 26, *)` 안에 두면 링커가
약한 링크(`LC_LOAD_WEAK_DYLIB`)로 연결합니다. `scripts/release.sh`가 배포 전에 이것을 확인하고,
강한 링크면 실패합니다.

```sh
otool -l build/Build/Products/Debug/JinMac.app/Contents/MacOS/JinMac.debug.dylib | grep -B1 -A2 FoundationModels
```

## 고친 것을 설치본에 반영하기

`./scripts/build.sh`가 만드는 것은 `build/Build/Products/Debug/JinMac.app`이고,
`/Applications/JinMac.app`은 손대지 않습니다. 설치본을 바꾸려면 릴리스 빌드를 만들어 교체합니다.

```sh
osascript -e 'quit app "JinMac"'
./scripts/release.sh
ditto build/export/JinMac.app /Applications/JinMac.app
```

> **로그인 항목을 확인하세요**: `SMAppService` 등록은 앱의 코드 서명, 정확히는 지정
> 요구사항(designated requirement)에 묶입니다. ad-hoc 서명에는 Team ID가 없어서 이 값이
> 바이너리의 cdhash로 잡히고, cdhash는 코드가 바뀌면 함께 바뀝니다. 따라서 ad-hoc 빌드로
> 교체하면 자동 실행이 꺼지고, 재부팅한 뒤 수집이 재개되지 않습니다. 교체한 뒤 메뉴에서 한 번
> 확인하시기 바랍니다. 아래 "배포 서명 인증서"를 설정해 두면 배포본에서는 이 문제가 생기지
> 않습니다 ([요구사항 14.5a](../kb/wiki/spec/requirements.md)).

## 배포 서명 인증서

`scripts/release.sh`는 키체인에 `JinMac Self-Signed` 인증서가 있으면 그것으로 서명하고, 없으면
ad-hoc으로 떨어지면서 경고를 남깁니다. **ad-hoc으로 배포하면 그 배포본을 설치한 사용자는 다음
릴리스에서 로그인 항목을 다시 허용해야 합니다.** JinMac은 1\~2주를 이어서 기록해야 판정이 나오는
앱이라, 등록이 풀린 것을 모르면 구멍 난 데이터로 검진을 마치게 됩니다. 그러므로 배포 전에
인증서를 한 번만 만들어 두어야 합니다.

이 인증서는 Gatekeeper를 통과시켜 주지 않습니다. "확인되지 않은 개발자" 안내는 그대로 필요합니다.
목적은 오로지 지정 요구사항을 버전 사이에 고정하는 것입니다.

```sh
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout jinmac-signing.key -out jinmac-signing.crt \
  -subj "/CN=JinMac Self-Signed" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning"

openssl pkcs12 -export -legacy -in jinmac-signing.crt -inkey jinmac-signing.key \
  -name "JinMac Self-Signed" -out jinmac-signing.p12

security import jinmac-signing.p12 -k ~/Library/Keychains/login.keychain-db \
  -T /usr/bin/codesign
```

여기까지가 전부입니다. 키체인 접근에서 "항상 신뢰"로 바꿀 필요는 없습니다. 자체 서명 인증서는
루트가 신뢰되지 않아 `security find-identity -v -p codesigning`이 0건으로 보고하지만
(`CSSMERR_TP_NOT_TRUSTED`), `codesign`은 그 상태로도 정상적으로 서명하고
`codesign --verify --strict`도 통과합니다. 2026-09-20에 이 기기에서 확인했습니다. 그래서
`release.sh`의 인증서 탐지도 `-v`를 쓰지 않습니다.

`.p12`를 만든 뒤에는 평문 개인 키(`jinmac-signing.key`)를 지우십시오. 암호 없는 키를 디스크에
남겨 둘 이유가 없습니다.

> **개인 키를 잃어버리면 모든 사용자의 로그인 항목이 한 번 더 초기화됩니다.**
> `jinmac-signing.p12`를 암호 관리자나 오프라인 매체에 백업하십시오.

관리자의 맥에서는 사본을 `signing/`에 두고 있습니다. `.gitignore`가 이 폴더와 `*.p12`, `*.key`,
`*.crt`를 막고 있어 깃에 올라가지 않습니다. 다만 **`git clean -xdf`는 무시된 파일까지 지우므로 이
폴더도 함께 사라집니다.** 그러니 `signing/`은 사본으로만 취급하고, 정본은 저장소 바깥에 따로
두어야 합니다.

### 릴리스마다 확인할 것

`release.sh`가 출력하는 지정 요구사항 줄이 지난 릴리스와 같은지 확인하십시오.
`cdhash`로 나오면 인증서가 적용되지 않은 것입니다.

```text
  지정 요구사항:
    identifier "dev.liampark.jinmac" and certificate leaf = H"c5555fcd..."
```

## 0단계 프로브

비공개 API와 권한이 이 기기에서 실제로 되는지 확인하는 스크립트입니다. 앱에 들어가는 코드가
아니라 검증용이고, 출력이 그대로 원자료가 됩니다.

```
swift scripts/probes/probe-smc.swift       # SMC·IOHID 온도와 팬 키
swift scripts/probes/probe-ioreport.swift  # IOReport CPU 주파수 채널과 DVFS 표
swift scripts/probes/probe-rusage.swift    # 다른 계정 소유 프로세스의 사용량
```

세 스크립트 모두 관리자 권한이 필요 없습니다. 결과를 원자료로 남길 때는 출력을
`kb/raw/probes/YYYY-MM-DD-이름.md`로 그대로 보냅니다. 출처 헤더는 스크립트가 직접 찍습니다.

프로브는 이 기기에서 도는 프로세스 이름을 찍지 않습니다. 이름을 밝히는 대상은
`probe-rusage.swift`의 `NAMED_TARGETS`에 적은 시스템 데몬뿐입니다. 대상을 늘릴 때는 그 이름이
사용자가 무엇을 쓰는지 드러내지 않는지 먼저 따져야 합니다.

## 문서

- [kb/wiki/research/probe-results.md](../kb/wiki/research/probe-results.md): 0단계 프로브 결과, 센서와 권한
- [kb/wiki/spec/requirements.md](../kb/wiki/spec/requirements.md): 개발 요구사항, 결정과 검토 의견
- [kb/raw/references/2026-09-17-requirements-draft.md](../kb/raw/references/2026-09-17-requirements-draft.md): 요구사항 초안 원문
- [kb/wiki/index.md](../kb/wiki/index.md): 지식 베이스 전체 색인

## 릴리스까지 남은 일

v0.1.0은 요구사항 13장 1단계(MVP)의 완료 기준을 채워야 합니다. 본인 기기에서 7일 검진을 마친 뒤
리포트가 나오고, 커뮤니티에 리포트 카드를 올릴 수 있어야 합니다. 그 전에 0단계 검증 세 가지를
먼저 끝냅니다.

<!-- roadmap:release-checklist:start -->
- [x] 자체 서명 인증서로 서명한 설치본에서 Foundation Models 호출이 되는지 실기기에서 확인
- [x] SMC 온도와 IOReport 주파수를 일반 권한으로 읽을 수 있는지 확인
- [x] 메모리·CPU 수집과 SQLite 저장
- [ ] 메모리 판정과 템플릿 한국어 리포트
- [ ] 리포트 카드 PNG 내보내기
- [ ] README 설치 안내와 수집 항목 전체 목록
- [ ] GitHub Release 수동 배포 (zip + SHA-256)
<!-- roadmap:release-checklist:end -->

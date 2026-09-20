# 지식 베이스 색인

JinMac이 아는 것을 모아 둔 곳이다. 질문이 있으면 여기서 문서를 고르기 전에
`swift scripts/kb.swift query "질문"`을 먼저 돌린다. 문서 전체가 아니라 필요한 절만 돌려준다.

첫 열의 한국어 문서가 정본이다. 사람은 그것을 읽고 고친다. `EN` 열은 클로드가 읽는 영어
번역본이고 지식 그래프가 색인하는 쪽이다. 정본을 고치면 번역본이 같은 턴에 따라온다.

## spec

JinMac이 무엇을 해야 하는지, 그리고 그것을 만들면서 내린 결정과 검토 의견.

| 문서 | 요약 | EN | 갱신 |
|---|---|---|---|
| [개발 요구사항](spec/requirements.md) | F-01\~F-64, A-01\~A-09, 5장 판정 기준, 13장 개발 단계. 14장에 뼈대를 만들며 내린 결정과 macOS API 대조 검토 의견(결정 대기) | [en](spec/requirements.en.md) | 2026-09-17 |

## research

실기기에서 재 보고 알아낸 것.

| 문서 | 요약 | EN | 갱신 |
|---|---|---|---|
| [0단계 프로브 결과](research/probe-results.md) | SMC·IOHID 온도와 팬, IOReport CPU 주파수는 일반 권한으로 읽힌다. 다른 계정 소유 프로세스의 사용량은 예외 없이 막힌다 | [en](research/probe-results.en.md) | 2026-09-20 |

---

원자료는 [kb/raw/](../raw/README.md)에 있다. 문서 사이의 관계는 [graph.json](graph.json)이,
변경 이력은 [log.md](log.md)가 담는다. 이 색인과 로그는 한국어 단일본이라 번역본을 두지 않는다.

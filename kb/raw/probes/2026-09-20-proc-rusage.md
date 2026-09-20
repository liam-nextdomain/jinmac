# Mac17,2에서 다른 계정이 소유한 프로세스의 사용량 읽기

**Source:** swift scripts/probes/probe-rusage.swift
**Collected:** 2026-09-20
**Published:** N/A (직접 측정)
**Machine:** Mac17,2, Apple M5, macOS 27.2

## 1. 요약

- 프로세스 863개를 훑었다. 관리자 권한 없이 실행했다.
- `proc_pidinfo(PROC_PIDTBSDINFO)` 성공: 527개
- 전체 정보가 막혀 `PROC_PIDT_SHORTBSDINFO`로 내려간 경우: 336개 (이름과 소유 계정은 읽힌다)
- 두 경로 모두 실패: 0개
- `proc_pid_rusage(RUSAGE_INFO_V4)` 실패: 336개

## 2. 소유 계정별 결과

계정 이름은 root와 `_`로 시작하는 시스템 계정만 밝힌다. 나머지는 uid 숫자로만 센다.

| 소유 계정 | 프로세스 수 | rusage 성공 | 실패 |
|---|---|---|---|
| _accessoryupdater(uid 278) | 14 | 0 | 14(EPERM(권한 없음)) |
| _analyticsd(uid 263) | 1 | 0 | 1(EPERM(권한 없음)) |
| _appinstalld(uid 273) | 2 | 0 | 2(EPERM(권한 없음)) |
| _appleevents(uid 55) | 2 | 0 | 2(EPERM(권한 없음)) |
| _applepay(uid 260) | 5 | 0 | 5(EPERM(권한 없음)) |
| _appstore(uid 33) | 1 | 0 | 1(EPERM(권한 없음)) |
| _assetcache(uid 235) | 2 | 0 | 2(EPERM(권한 없음)) |
| _audiomxd(uid 294) | 3 | 0 | 3(EPERM(권한 없음)) |
| _biome(uid 289) | 1 | 0 | 1(EPERM(권한 없음)) |
| _captiveagent(uid 258) | 1 | 0 | 1(EPERM(권한 없음)) |
| _cmiodalassistants(uid 262) | 10 | 0 | 10(EPERM(권한 없음)) |
| _coreaudiod(uid 202) | 6 | 0 | 6(EPERM(권한 없음)) |
| _corespeechd(uid 306) | 3 | 0 | 3(EPERM(권한 없음)) |
| _ctkd(uid 259) | 1 | 0 | 1(EPERM(권한 없음)) |
| _datadetectors(uid 257) | 1 | 0 | 1(EPERM(권한 없음)) |
| _diagnosticservicesd(uid 307) | 1 | 0 | 1(EPERM(권한 없음)) |
| _distnote(uid 241) | 1 | 0 | 1(EPERM(권한 없음)) |
| _driverkit(uid 270) | 4 | 0 | 4(EPERM(권한 없음)) |
| _fpsd(uid 265) | 5 | 0 | 5(EPERM(권한 없음)) |
| _gamecontrollerd(uid 247) | 3 | 0 | 3(EPERM(권한 없음)) |
| _hidd(uid 261) | 1 | 0 | 1(EPERM(권한 없음)) |
| _iconservices(uid 240) | 1 | 0 | 1(EPERM(권한 없음)) |
| _installcoordinationd(uid 274) | 4 | 0 | 4(EPERM(권한 없음)) |
| _locationd(uid 205) | 7 | 0 | 7(EPERM(권한 없음)) |
| _mdnsresponder(uid 65) | 1 | 0 | 1(EPERM(권한 없음)) |
| _mds_stores(uid 308) | 1 | 0 | 1(EPERM(권한 없음)) |
| _modelmanagerd(uid 301) | 8 | 0 | 8(EPERM(권한 없음)) |
| _nearbyd(uid 268) | 1 | 0 | 1(EPERM(권한 없음)) |
| _netbios(uid 222) | 1 | 0 | 1(EPERM(권한 없음)) |
| _networkd(uid 24) | 1 | 0 | 1(EPERM(권한 없음)) |
| _neuralengine(uid 296) | 4 | 0 | 4(EPERM(권한 없음)) |
| _nsurlsessiond(uid 242) | 5 | 0 | 5(EPERM(권한 없음)) |
| _oahd(uid 441) | 1 | 0 | 1(EPERM(권한 없음)) |
| _reportmemoryexception(uid 269) | 2 | 0 | 2(EPERM(권한 없음)) |
| _reportsystemmemory(uid 302) | 1 | 0 | 1(EPERM(권한 없음)) |
| _rmd(uid 277) | 19 | 0 | 19(EPERM(권한 없음)) |
| _securityagent(uid 92) | 2 | 0 | 2(EPERM(권한 없음)) |
| _softwareupdate(uid 200) | 4 | 0 | 4(EPERM(권한 없음)) |
| _spotlight(uid 89) | 3 | 0 | 3(EPERM(권한 없음)) |
| _timed(uid 266) | 1 | 0 | 1(EPERM(권한 없음)) |
| _trustd(uid 282) | 2 | 0 | 2(EPERM(권한 없음)) |
| _usbmuxd(uid 213) | 2 | 0 | 2(EPERM(권한 없음)) |
| _windowserver(uid 88) | 2 | 0 | 2(EPERM(권한 없음)) |
| root(uid 0) | 195 | 0 | 195(EPERM(권한 없음)) |
| 내 계정(uid 501) | 527 | 527 | 0 |

## 3. 요구사항 14.2d가 지목한 프로세스

축약 정보의 이름은 15자에서 잘리므로, 잘린 이름은 앞부분만 맞으면 같은 것으로 본다.

| 프로세스 | 소유 계정 | 정보 경로 | `proc_pid_rusage` | 누적 CPU 시간(초) |
|---|---|---|---|---|
| `mds` | root(uid 0) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |
| `mds_stores` | _mds_stores(uid 308) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |
| `backupd` | root(uid 0) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |
| `kernel_task` | root(uid 0) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |
| `launchd` | root(uid 0) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |
| `WindowServer` | _windowserver(uid 88) | `PROC_PIDT_SHORTBSDINFO` | 실패 EPERM(권한 없음) | - |

## 4. 개별 측정이 되지 않는 CPU 시간의 몫

`host_statistics`가 주는 전체 CPU 바쁜 시간에서, 읽을 수 있는 프로세스의 CPU 시간 합을 뺀 것이다.
그 잔여분이 요구사항 14.2d가 `시스템 프로세스(개별 측정 불가)`로 묶자고 한 몫이다.
유휴 상태와 부하 상태를 따로 쟀다. 부하는 이 프로브가 코어 5개를 직접 돌려 만든 것이라,
내 계정 소유이고 따라서 읽을 수 있는 부하다.

| 구간 | 평균 CPU 사용률 | 전체 바쁜 시간 | 읽은 합 | 잔여분 | 잔여 비율 |
|---|---|---|---|---|---|
| 유휴 | 5.1% | 0.510초 | 0.217초 | 0.293초 | 57.4% |
| 부하 | 46.3% | 4.630초 | 4.568초 | 0.062초 | 1.3% |

구간은 각각 1.0초이고, 논리 코어는 10개다. 코어가 여러 개라 CPU 시간의 합은 경과 시간보다 클 수 있다.

## 5. `ps`와 `top`의 권한 비트

요구사항 14.2d는 두 도구가 setuid root라서 모든 프로세스를 보여 준다고 적었다.
프로세스를 띄우지 않고 파일 권한만 확인한 것이다.

| 파일 | 권한 | 소유자 | setuid |
|---|---|---|---|
| `/bin/ps` | 4755 | root | 예 |
| `/usr/bin/top` | 4555 | root | 예 |


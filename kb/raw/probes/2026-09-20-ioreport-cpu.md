# Mac17,2의 IOReport CPU 주파수 채널

**Source:** swift scripts/probes/probe-ioreport.swift
**Collected:** 2026-09-20
**Published:** N/A (직접 측정)
**Machine:** Mac17,2, Apple M5, macOS 27.2

## 1. IOReport 라이브러리

- `/System/Library/PrivateFrameworks/IOReport.framework/IOReport`: 없음
- `/usr/lib/libIOReport.dylib`: **열림**
- 심볼 11개 모두 찾음 (관리자 권한 없이)

## 2. 읽을 수 있는 채널 그룹

`IOReportCopyAllChannels`가 채널 10985개, 그룹 191개를 돌려주었다.
그중 이 앱이 쓸 그룹만 하위 그룹까지 펼친다.

| 그룹 / 하위 그룹 | 채널 수 |
|---|---|
| CPU Stats / CPU Complex Performance States | 6 |
| CPU Stats / CPU Complex Voltage State Time | 54 |
| CPU Stats / CPU Complex Voltage States | 2 |
| CPU Stats / CPU Core Performance States | 10 |
| Energy Model / - | 169 |
| GPU Stats / 8e9b50cd04211f53196f | 1 |
| GPU Stats / AFR Performance States | 1 |
| GPU Stats / AFR Power Controller States | 1 |
| GPU Stats / Active Time Histogram | 1 |
| GPU Stats / CDM vChannel Usage | 5 |
| GPU Stats / CLTM-induced GPU Performance States | 1 |
| GPU Stats / Context Switch Latencies | 36 |
| GPU Stats / DVD Request States | 1 |
| GPU Stats / FRG vChannel Usage | 5 |
| GPU Stats / Fender Active Time Histogram | 1 |
| GPU Stats / Fender Idle Time Histogram | 1 |
| GPU Stats / Fender State | 1 |
| GPU Stats / GPU Boost Controller Performance States | 1 |
| GPU Stats / GPU Discrete Power Zone Residency | 1 |
| GPU Stats / GPU Performance States | 1 |
| GPU Stats / GPU Power Controller States | 1 |
| GPU Stats / GPU Throttler Counters | 10 |
| GPU Stats / GTP vChannel Usage | 5 |
| GPU Stats / Idle Time Histogram | 1 |
| GPU Stats / Issue Counts | 11 |
| GPU Stats / PMU Loop Lost Performance Reason Code States | 1 |
| GPU Stats / PPM Target as % of Max GPU Power | 1 |
| GPU Stats / Power Zone Filters | 6 |
| GPU Stats / Spill Buffer Metadata Unused Blocks Per Task Histogram | 1 |
| GPU Stats / Spill Buffer Metadata Usage Histogram | 1 |
| GPU Stats / Spill Buffer Usage Histogram | 1 |
| GPU Stats / THM Counters | 2 |
| GPU Stats / UMA Allocation Size Stats | 7 |
| GPU Stats / UMA Metric Mapped Pages Histogram | 1 |
| GPU Stats / UMA Metric Reserved Pages Histogram | 1 |
| GPU Stats / UMA Pool Memory Usage | 7 |
| GPU Stats / UT Engagement centi-% Histogram | 1 |
| GPU Stats / UV Warn State | 2 |
| GPU Stats / vChannel Selection | 15 |


## 3. CPU 성능 상태 채널 구독

- `IOReportCreateSubscription`: **성공** (관리자 권한 없이)
- 1.0초 간격으로 표본 두 개를 뜨고 차이를 구했다.

`CPU Stats` 그룹에서 성능 상태(DVFS) 채널 16개를 찾았다.

### CPU Core Performance States / ECPU0

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 19815201 |
| `V0P7` | 2265861 |
| `V1P6` | 586623 |
| `V2P5` | 366048 |
| `V3P4` | 272861 |
| `V4P3` | 339011 |
| `V5P2` | 379323 |
| `V6P1` | 0 |
| `V7P0` | 154737 |

합계 24179665이고, 1.0초로 나누면 초당 24.18×10⁶이다.

### CPU Core Performance States / PCPU0

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 22786033 |
| `V0P18` | 54123 |
| `V1P17` | 58390 |
| `V2P16` | 139139 |
| `V3P15` | 1144221 |
| `V4P14` | 0 |
| `V5P13` | 0 |
| `V6P12` | 0 |
| `V7P11` | 0 |
| `V8P10` | 0 |
| `V9P9` | 0 |
| `V10P8` | 0 |
| `V11P7` | 0 |
| `V12P6` | 0 |
| `V13P5` | 0 |
| `V14P4` | 0 |
| `V15P3` | 0 |
| `V16P2` | 0 |
| `V17P1` | 0 |
| `V18P0` | 0 |

합계 24181906이고, 1.0초로 나누면 초당 24.18×10⁶이다.

### CPU Complex Performance States / ECPU

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 16941952 |
| `V0P7` | 3521898 |
| `V1P6` | 860982 |
| `V2P5` | 800485 |
| `V3P4` | 505927 |
| `V4P3` | 535270 |
| `V5P2` | 577640 |
| `V6P1` | 0 |
| `V7P0` | 435012 |

합계 24179166이고, 1.0초로 나누면 초당 24.18×10⁶이다.

### CPU Complex Performance States / ECPM

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 15796567 |
| `V0P7` | 4407090 |
| `V1P6` | 923300 |
| `V2P5` | 860159 |
| `V3P4` | 508155 |
| `V4P3` | 538845 |
| `V5P2` | 582950 |
| `V6P1` | 10222 |
| `V7P0` | 578076 |

합계 24205364이고, 1.0초로 나누면 초당 24.21×10⁶이다.

### CPU Complex Performance States / ECPM_IDLE

| 상태 | 체류 증가량 |
|---|---|
| `NON_IDLE` | 8408797 |
| `V0P7` | 13112261 |
| `V1P6` | 519922 |
| `V2P5` | 627881 |
| `V3P4` | 142695 |
| `V4P3` | 380756 |
| `V5P2` | 601113 |
| `V6P1` | 0 |
| `V7P0` | 411939 |

합계 24205364이고, 1.0초로 나누면 초당 24.21×10⁶이다.

### CPU Complex Performance States / PCPU

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 21357111 |
| `V0P18` | 131894 |
| `V1P17` | 69229 |
| `V2P16` | 260871 |
| `V3P15` | 2360920 |
| `V4P14` | 0 |
| `V5P13` | 0 |
| `V6P12` | 0 |
| `V7P11` | 0 |
| `V8P10` | 0 |
| `V9P9` | 0 |
| `V10P8` | 0 |
| `V11P7` | 0 |
| `V12P6` | 0 |
| `V13P5` | 0 |
| `V14P4` | 0 |
| `V15P3` | 0 |
| `V16P2` | 0 |
| `V17P1` | 0 |
| `V18P0` | 0 |

합계 24180025이고, 1.0초로 나누면 초당 24.18×10⁶이다.

### CPU Complex Performance States / PCPM

| 상태 | 체류 증가량 |
|---|---|
| `IDLE` | 18894858 |
| `V0P18` | 2394781 |
| `V1P17` | 72124 |
| `V2P16` | 294705 |
| `V3P15` | 2555637 |
| `V4P14` | 0 |
| `V5P13` | 0 |
| `V6P12` | 0 |
| `V7P11` | 0 |
| `V8P10` | 0 |
| `V9P9` | 0 |
| `V10P8` | 0 |
| `V11P7` | 0 |
| `V12P6` | 0 |
| `V13P5` | 0 |
| `V14P4` | 0 |
| `V15P3` | 0 |
| `V16P2` | 0 |
| `V17P1` | 0 |
| `V18P0` | 0 |

합계 24212105이고, 1.0초로 나누면 초당 24.21×10⁶이다.

### CPU Complex Performance States / PCPM_IDLE

| 상태 | 체류 증가량 |
|---|---|
| `NON_IDLE` | 5317247 |
| `V0P18` | 16009092 |
| `V1P17` | 72885 |
| `V2P16` | 485900 |
| `V3P15` | 2326981 |
| `V4P14` | 0 |
| `V5P13` | 0 |
| `V6P12` | 0 |
| `V7P11` | 0 |
| `V8P10` | 0 |
| `V9P9` | 0 |
| `V10P8` | 0 |
| `V11P7` | 0 |
| `V12P6` | 0 |
| `V13P5` | 0 |
| `V14P4` | 0 |
| `V15P3` | 0 |
| `V16P2` | 0 |
| `V17P1` | 0 |
| `V18P0` | 0 |

합계 24212105이고, 1.0초로 나누면 초당 24.21×10⁶이다.

## 4. 상태 이름을 주파수로 바꾸는 표 (IORegistry pmgr)

`IODeviceTree:/arm-io/pmgr`의 `voltage-states*` 속성이다. u32 두 개가 한 단계이고,
아래 표는 그중 앞 값만 모은 것이다.

| 속성 | 단계 수 | 단위 | 앞 값 |
|---|---|---|---|
| `voltage-states0` | 6 | 주파수 아님(주기 값이거나 비어 있음) | 1, 1, 1, 1, 1, 1 |
| `voltage-states1` | 8 | 주파수 아님(주기 값이거나 비어 있음) | 67423, 56888, 41373, 32899, 27863, 24272, 22110, 21501 |
| `voltage-states1-sram` | 8 | kHz → MHz로 환산 | 972, 1152, 1584, 1992, 2352, 2700, 2964, 3048 |
| `voltage-states11` | 5 | 주파수 아님(주기 값이거나 비어 있음) | 1, 1, 1, 1, 1 |
| `voltage-states2` | 8 | 주파수 아님(주기 값이거나 비어 있음) | 1, 1, 1, 1, 1, 1, 1, 1 |
| `voltage-states5` | 19 | 주파수 아님(주기 값이거나 비어 있음) | 50103, 40756, 33921, 29520, 26130, 23239, 21333, 19859, 18639, 17617, 16908, 16302, 15693, 15427, 15340, 15128, 14800, 14524, 14222 |
| `voltage-states5-sram` | 19 | kHz → MHz로 환산 | 1308, 1608, 1932, 2220, 2508, 2820, 3072, 3300, 3516, 3720, 3876, 4020, 4176, 4248, 4272, 4332, 4428, 4512, 4608 |
| `voltage-states8` | 26 | Hz → MHz로 환산 | 732, 864, 936, 1068, 1116, 1248, 1296, 1416, 1464, 1572, 1620, 1728, 1788, 1860, 1908, 1980, 2040, 2076, 2136, 2184, 2196, 2244, 2256, 2304, 2316, 2448 |
| `voltage-states9` | 14 | Hz → MHz로 환산 | 0, 338, 486, 636, 796, 888, 988, 1084, 1182, 1278, 1374, 1470, 1578, 1620 |
| `voltage-states9-sram` | 14 | Hz → MHz로 환산 | 0, 338, 486, 636, 796, 888, 988, 1084, 1182, 1278, 1374, 1470, 1578, 1620 |

## 5. 파생 결과: 클러스터별 평균 주파수

체류 시간 증가량을 가중치로 삼아, 1.0초 동안의 평균 주파수를 구한 것이다.
효율 코어는 `voltage-states1-sram`, 성능 코어는 `voltage-states5-sram`을 썼다.

| 채널 | 활성 비율 | 평균 주파수(MHz) |
|---|---|---|
| ECPM | 34.7% | 주파수 표를 찾지 못했다 |
| ECPM_IDLE | 100.0% | 주파수 표를 찾지 못했다 |
| ECPU | 29.9% | 1497 |
| ECPU0 | 18.1% | 1442 |
| ECPU1 | 10.1% | 1469 |
| ECPU2 | 6.9% | 1448 |
| ECPU3 | 3.7% | 1796 |
| ECPU4 | 4.3% | 1999 |
| ECPU5 | 0.8% | 1349 |
| PCPM | 22.0% | 주파수 표를 찾지 못했다 |
| PCPM_IDLE | 100.0% | 주파수 표를 찾지 못했다 |
| PCPU | 11.7% | 2136 |
| PCPU0 | 5.8% | 2130 |
| PCPU1 | 4.8% | 2183 |
| PCPU2 | 5.5% | 2158 |
| PCPU3 | 2.3% | 2131 |

## 6. 참고: 코어 구성

- 논리 코어: 10
- 성능 코어(`hw.perflevel0.logicalcpu`): 4
- 효율 코어(`hw.perflevel1.logicalcpu`): 6


// P0-PROBE-03. IOReport 프로브.
//
// CPU 주파수 채널을 **일반 권한으로** 구독하고 표본을 뜰 수 있는지 확인한다 (F-03)
// (요구사항 13) (요구사항 14.2c). IOReport는 비공개 프레임워크라 심볼을 dlsym으로 찾고,
// 없으면 없다는 사실 자체를 결과로 남긴다.
//
//   swift scripts/probes/probe-ioreport.swift > kb/raw/probes/YYYY-MM-DD-ioreport-cpu.md
//
// 주파수는 IOReport 혼자 주지 않는다. 채널은 DVFS 상태별 체류 시간만 주고, 상태 번호를 Hz로
// 바꾸는 표는 IORegistry의 pmgr 노드에 있다. 둘 다 읽혀야 F-03의 `현재 주파수`가 성립한다.
//
// 출력이 곧 원자료다 (kb/raw/README.md). 해석은 kb/wiki/research/probe-results.md가 맡는다.

import Foundation
import IOKit

// MARK: - 출처 헤더 (scripts/probes/probe-smc.swift와 같은 내용을 복사해 둔다)

func printHeader(title: String, source: String) {
    let model = sysctlString("hw.model") ?? "unknown"
    let chip = sysctlString("machdep.cpu.brand_string") ?? "unknown"
    let os = sysctlString("kern.osproductversion") ?? "unknown"
    let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

    print("# \(title)")
    print("")
    print("**Source:** \(source)")
    print("**Collected:** \(today)")
    print("**Published:** N/A (직접 측정)")
    print("**Machine:** \(model), \(chip), macOS \(os)")
    print("")
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

// MARK: - IOReport 심볼

typealias FnCopyAllChannels = @convention(c) (UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
typealias FnCopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
typealias FnCreateSubscription = @convention(c) (
    UnsafeMutableRawPointer?, CFMutableDictionary,
    UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?
) -> Unmanaged<AnyObject>?
typealias FnCreateSamples = @convention(c) (AnyObject?, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias FnCreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias FnChannelGetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
typealias FnStateGetCount = @convention(c) (CFDictionary) -> Int32
typealias FnStateGetNameForIndex = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
typealias FnStateGetResidency = @convention(c) (CFDictionary, Int32) -> Int64

struct IOReportSymbols {
    let copyAllChannels: FnCopyAllChannels
    let copyChannelsInGroup: FnCopyChannelsInGroup
    let createSubscription: FnCreateSubscription
    let createSamples: FnCreateSamples
    let createSamplesDelta: FnCreateSamplesDelta
    let channelGetGroup: FnChannelGetString
    let channelGetSubGroup: FnChannelGetString
    let channelGetName: FnChannelGetString
    let stateGetCount: FnStateGetCount
    let stateGetNameForIndex: FnStateGetNameForIndex
    let stateGetResidency: FnStateGetResidency
}

/// IOReport를 담고 있을 만한 자리. 오래된 코드는 대부분 첫 번째 경로를 박아 두는데, 이 기기에서는
/// 그 자리가 비어 있고 `/usr/lib/libIOReport.dylib`만 열린다. 순서대로 시도하고 어디서 열렸는지
/// 결과에 남긴다.
let IOREPORT_PATHS = [
    "/System/Library/PrivateFrameworks/IOReport.framework/IOReport",
    "/usr/lib/libIOReport.dylib",
]

func loadIOReport() -> (symbols: IOReportSymbols?, path: String?, missing: [String]) {
    var handle: UnsafeMutableRawPointer?
    var openedPath: String?
    for path in IOREPORT_PATHS {
        if let h = dlopen(path, RTLD_LAZY) {
            handle = h
            openedPath = path
            break
        }
    }
    guard let handle else {
        return (nil, nil, IOREPORT_PATHS.map { "dlopen(\($0))" })
    }
    var missing: [String] = []
    func sym(_ name: String) -> UnsafeMutableRawPointer? {
        guard let p = dlsym(handle, name) else {
            missing.append(name)
            return nil
        }
        return p
    }

    let names = [
        "IOReportCopyAllChannels", "IOReportCopyChannelsInGroup", "IOReportCreateSubscription",
        "IOReportCreateSamples", "IOReportCreateSamplesDelta", "IOReportChannelGetGroup",
        "IOReportChannelGetSubGroup", "IOReportChannelGetChannelName", "IOReportStateGetCount",
        "IOReportStateGetNameForIndex", "IOReportStateGetResidency",
    ]
    let pointers = names.map { sym($0) }
    guard !pointers.contains(where: { $0 == nil }) else { return (nil, openedPath, missing) }

    return (IOReportSymbols(
        copyAllChannels: unsafeBitCast(pointers[0]!, to: FnCopyAllChannels.self),
        copyChannelsInGroup: unsafeBitCast(pointers[1]!, to: FnCopyChannelsInGroup.self),
        createSubscription: unsafeBitCast(pointers[2]!, to: FnCreateSubscription.self),
        createSamples: unsafeBitCast(pointers[3]!, to: FnCreateSamples.self),
        createSamplesDelta: unsafeBitCast(pointers[4]!, to: FnCreateSamplesDelta.self),
        channelGetGroup: unsafeBitCast(pointers[5]!, to: FnChannelGetString.self),
        channelGetSubGroup: unsafeBitCast(pointers[6]!, to: FnChannelGetString.self),
        channelGetName: unsafeBitCast(pointers[7]!, to: FnChannelGetString.self),
        stateGetCount: unsafeBitCast(pointers[8]!, to: FnStateGetCount.self),
        stateGetNameForIndex: unsafeBitCast(pointers[9]!, to: FnStateGetNameForIndex.self),
        stateGetResidency: unsafeBitCast(pointers[10]!, to: FnStateGetResidency.self)
    ), openedPath, missing)
}

/// 표본 사전에서 채널 목록을 꺼낸다.
///
/// **Swift 사전으로 브리지하면 안 된다.** `IOReportStateGetNameForIndex`는 풀어낸 상태 이름을
/// 채널 사전에 다시 써 넣는데, 브리지된 `_SwiftDeferredNSDictionary`에는 쓸 수 없어
/// `unrecognized selector`로 프로세스가 죽는다. CoreFoundation 수준에서 원래 객체를 그대로
/// 넘긴다.
func channels(of samples: CFDictionary) -> [CFDictionary] {
    let key = "IOReportChannels" as CFString
    guard let raw = CFDictionaryGetValue(samples, Unmanaged.passUnretained(key).toOpaque()) else {
        return []
    }
    let array = unsafeBitCast(raw, to: CFArray.self)
    return (0..<CFArrayGetCount(array)).compactMap { i in
        guard let p = CFArrayGetValueAtIndex(array, i) else { return nil }
        return unsafeBitCast(p, to: CFDictionary.self)
    }
}

// MARK: - DVFS 주파수 표 (IORegistry)

/// pmgr 노드의 `voltage-states*` 속성. u32 두 개가 한 단계다. 앞이 주파수, 뒤가 전압(mV)인데
/// **단위가 표마다 다르다.** 이 기기에서 확인한 것은 다음과 같다.
///
/// - `voltage-states1`, `voltage-states5`: 주파수가 아니라 주기 값이다. 단계마다 줄어든다.
/// - `voltage-states1-sram`(효율 코어), `voltage-states5-sram`(성능 코어): kHz 단위 주파수다.
/// - `voltage-states8`, `voltage-states9`, `voltage-states9-sram`: Hz 단위 주파수다.
///
/// 이름만 보고는 단위를 알 수 없다. `-sram` 접미사가 붙어도 `voltage-states9-sram`은 Hz다.
/// 그래서 표 안의 가장 큰 값으로 단위를 정하고, 원시 값과 환산한 MHz를 함께 남긴다.
enum FrequencyUnit {
    case kilohertz, hertz, unknown

    var label: String {
        switch self {
        case .kilohertz: return "kHz"
        case .hertz: return "Hz"
        case .unknown: return "주파수 아님(주기 값이거나 비어 있음)"
        }
    }
}

func unit(ofMax max: UInt32) -> FrequencyUnit {
    if max >= 100_000_000 { return .hertz }
    if max >= 1_000_000 { return .kilohertz }
    return .unknown
}

func megahertz(_ raw: UInt32, unit: FrequencyUnit) -> Double? {
    switch unit {
    case .kilohertz: return Double(raw) / 1_000
    case .hertz: return Double(raw) / 1_000_000
    case .unknown: return nil
    }
}

func voltageStateTables() -> [(name: String, raw: [UInt32])] {
    var entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
    if entry == 0 {
        entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
    }
    guard entry != 0 else { return [] }
    defer { IOObjectRelease(entry) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
          let dict = props?.takeRetainedValue() as? [String: Any] else { return [] }

    var tables: [(String, [UInt32])] = []
    for (key, value) in dict where key.hasPrefix("voltage-states") {
        guard let data = value as? Data else { continue }
        var values: [UInt32] = []
        var offset = 0
        while offset + 8 <= data.count {
            let raw = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            }
            values.append(raw)
            offset += 8
        }
        if !values.isEmpty { tables.append((key, values)) }
    }
    return tables.sorted { $0.0 < $1.0 }
}

// MARK: - 실행

printHeader(
    title: "\(sysctlString("hw.model") ?? "이 기기")의 IOReport CPU 주파수 채널",
    source: "swift scripts/probes/probe-ioreport.swift"
)

let (symbols, openedPath, missing) = loadIOReport()

print("## 1. IOReport 라이브러리")
print("")
for path in IOREPORT_PATHS {
    let mark = path == openedPath ? "**열림**" : "없음"
    print("- `\(path)`: \(mark)")
}
guard let io = symbols else {
    print("- 심볼을 찾지 못했다: \(missing.joined(separator: ", "))")
    print("")
    print("IOReport로는 주파수를 읽을 수 없다. F-03의 `현재 주파수`를 결측으로 두어야 한다.")
    exit(0)
}
print("- 심볼 11개 모두 찾음 (관리자 권한 없이)")
print("")

// 전체 채널을 훑어 어떤 그룹이 있는지 본다.
print("## 2. 읽을 수 있는 채널 그룹")
print("")
/// 이 앱이 쓸 만한 그룹만 하위 그룹까지 펼친다. 전체 그룹은 수백 개라 원자료에 다 넣으면
/// 읽히지 않는다.
let INTERESTING_GROUPS = ["CPU Stats", "GPU Stats", "Energy Model"]

if let all = io.copyAllChannels(0, 0)?.takeRetainedValue() {
    let list = channels(of: all as CFDictionary)
    var groupTotals: [String: Int] = [:]
    var subCounts: [String: Int] = [:]
    for ch in list {
        let group = io.channelGetGroup(ch)?.takeUnretainedValue() as String? ?? "(없음)"
        groupTotals[group, default: 0] += 1
        guard INTERESTING_GROUPS.contains(group) else { continue }
        let sub = io.channelGetSubGroup(ch)?.takeUnretainedValue() as String? ?? "-"
        subCounts["\(group) / \(sub)", default: 0] += 1
    }
    print("`IOReportCopyAllChannels`가 채널 \(list.count)개, 그룹 \(groupTotals.count)개를 돌려주었다.")
    print("그중 이 앱이 쓸 그룹만 하위 그룹까지 펼친다.")
    print("")
    print("| 그룹 / 하위 그룹 | 채널 수 |")
    print("|---|---|")
    for key in subCounts.keys.sorted() {
        print("| \(key) | \(subCounts[key]!) |")
    }
    print("")
    let absent = INTERESTING_GROUPS.filter { groupTotals[$0] == nil }
    if !absent.isEmpty {
        print("이 기기에 없는 그룹: \(absent.joined(separator: ", "))")
    }
} else {
    print("`IOReportCopyAllChannels`가 nil을 돌려주었다.")
}
print("")

// CPU 상태 채널을 구독해 1초 간격으로 두 번 뜬다.
print("## 3. CPU 성능 상태 채널 구독")
print("")

let interval = 1.0
var subscribed: Unmanaged<CFMutableDictionary>?
guard let desired = io.copyChannelsInGroup("CPU Stats" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else {
    print("`IOReportCopyChannelsInGroup(\"CPU Stats\")`가 nil을 돌려주었다.")
    exit(0)
}
guard let subscription = io.createSubscription(nil, desired, &subscribed, 0, nil)?.takeRetainedValue(),
      let subbed = subscribed?.takeRetainedValue() else {
    print("- `IOReportCreateSubscription`: **실패**. 일반 권한으로는 구독할 수 없다.")
    exit(0)
}
print("- `IOReportCreateSubscription`: **성공** (관리자 권한 없이)")

guard let first = io.createSamples(subscription, subbed, nil)?.takeRetainedValue() else {
    print("- `IOReportCreateSamples`: **실패**")
    exit(0)
}
Thread.sleep(forTimeInterval: interval)
guard let second = io.createSamples(subscription, subbed, nil)?.takeRetainedValue(),
      let delta = io.createSamplesDelta(first, second, nil)?.takeRetainedValue() else {
    print("- 두 번째 표본이나 차이 계산에 실패했다.")
    exit(0)
}
print("- \(interval)초 간격으로 표본 두 개를 뜨고 차이를 구했다.")
print("")

// 성능 상태 채널만 추린다.
struct StateChannel {
    var subGroup: String
    var name: String
    var states: [(name: String, residency: Int64)]

    var total: Int64 { states.reduce(0) { $0 + $1.residency } }
    /// `IDLE`과 `OFF`는 코어가 멈춰 있던 시간이다. 주파수 평균의 분모에서 뺀다.
    var active: [(name: String, residency: Int64)] {
        states.filter { $0.name != "IDLE" && $0.name != "OFF" && $0.name != "DOWN" }
    }
}

let stateChannels: [StateChannel] = channels(of: delta).compactMap { ch in
    let sub = io.channelGetSubGroup(ch)?.takeUnretainedValue() as String? ?? ""
    guard sub.contains("Performance States") else { return nil }
    let name = io.channelGetName(ch)?.takeUnretainedValue() as String? ?? "-"
    let count = io.stateGetCount(ch)
    var states: [(String, Int64)] = []
    for i in 0..<count {
        let stateName = io.stateGetNameForIndex(ch, i)?.takeUnretainedValue() as String? ?? "state\(i)"
        states.append((stateName, io.stateGetResidency(ch, i)))
    }
    return StateChannel(subGroup: sub, name: name, states: states)
}

print("`CPU Stats` 그룹에서 성능 상태(DVFS) 채널 \(stateChannels.count)개를 찾았다.")
print("")

// 클러스터 단위 채널은 전부, 코어 단위 채널은 클러스터마다 하나만 원시 표로 남긴다.
// 나머지는 같은 모양이라 파생 결과(4절)로 충분하다.
var shownCorePrefixes: Set<String> = []
for ch in stateChannels {
    let isCore = ch.subGroup.contains("Core")
    if isCore {
        let prefix = String(ch.name.prefix(4))
        guard !shownCorePrefixes.contains(prefix) else { continue }
        shownCorePrefixes.insert(prefix)
    }
    print("### \(ch.subGroup) / \(ch.name)")
    print("")
    print("| 상태 | 체류 증가량 |")
    print("|---|---|")
    for s in ch.states {
        print("| `\(s.name)` | \(s.residency) |")
    }
    print("")
    print("합계 \(ch.total)이고, \(interval)초로 나누면 초당 \(String(format: "%.2f", Double(ch.total) / interval / 1_000_000))×10⁶이다.")
    print("")
}

// MARK: - DVFS 표

print("## 4. 상태 이름을 주파수로 바꾸는 표 (IORegistry pmgr)")
print("")
let tables = voltageStateTables()
if tables.isEmpty {
    print("pmgr 노드에서 `voltage-states*` 속성을 읽지 못했다. 상태 이름을 주파수로 바꿀 수 없다.")
} else {
    print("`IODeviceTree:/arm-io/pmgr`의 `voltage-states*` 속성이다. u32 두 개가 한 단계이고,")
    print("아래 표는 그중 앞 값만 모은 것이다.")
    print("")
    print("| 속성 | 단계 수 | 단위 | 앞 값 |")
    print("|---|---|---|---|")
    for t in tables {
        let u = unit(ofMax: t.raw.max() ?? 0)
        let shown = t.raw.map { raw -> String in
            guard let mhz = megahertz(raw, unit: u) else { return String(raw) }
            return String(format: "%.0f", mhz)
        }.joined(separator: ", ")
        let unitLabel = u == .unknown ? u.label : "\(u.label) → MHz로 환산"
        print("| `\(t.name)` | \(t.raw.count) | \(unitLabel) | \(shown) |")
    }
}
print("")

// MARK: - 파생: 평균 주파수

print("## 5. 파생 결과: 클러스터별 평균 주파수")
print("")
print("체류 시간 증가량을 가중치로 삼아, \(interval)초 동안의 평균 주파수를 구한 것이다.")
print("효율 코어는 `voltage-states1-sram`, 성능 코어는 `voltage-states5-sram`을 썼다.")
print("")

func frequencyTableMHz(for channelName: String) -> [Double]? {
    let tableName: String
    if channelName.hasPrefix("ECPU") {
        tableName = "voltage-states1-sram"
    } else if channelName.hasPrefix("PCPU") {
        tableName = "voltage-states5-sram"
    } else {
        return nil
    }
    guard let table = tables.first(where: { $0.name == tableName }) else { return nil }
    let u = unit(ofMax: table.raw.max() ?? 0)
    return table.raw.compactMap { megahertz($0, unit: u) }
}

print("| 채널 | 활성 비율 | 평균 주파수(MHz) |")
print("|---|---|---|")
for ch in stateChannels.sorted(by: { $0.name < $1.name }) {
    let total = ch.total
    let activeStates = ch.active
    let activeSum = activeStates.reduce(Int64(0)) { $0 + $1.residency }
    let share = total > 0 ? Double(activeSum) / Double(total) * 100 : 0

    guard let freqs = frequencyTableMHz(for: ch.name) else {
        print("| \(ch.name) | \(String(format: "%.1f%%", share)) | 주파수 표를 찾지 못했다 |")
        continue
    }
    guard freqs.count == activeStates.count else {
        print("| \(ch.name) | \(String(format: "%.1f%%", share)) | 상태 \(activeStates.count)개와 표 \(freqs.count)단계가 어긋난다 |")
        continue
    }
    guard activeSum > 0 else {
        print("| \(ch.name) | \(String(format: "%.1f%%", share)) | 활성 시간이 0이라 평균을 낼 수 없다 |")
        continue
    }
    var weighted = 0.0
    for (i, state) in activeStates.enumerated() {
        weighted += Double(state.residency) * freqs[i]
    }
    print("| \(ch.name) | \(String(format: "%.1f%%", share)) | \(String(format: "%.0f", weighted / Double(activeSum))) |")
}
print("")

print("## 6. 참고: 코어 구성")
print("")
print("- 논리 코어: \(sysctlInt("hw.logicalcpu").map(String.init) ?? "읽기 실패")")
print("- 성능 코어(`hw.perflevel0.logicalcpu`): \(sysctlInt("hw.perflevel0.logicalcpu").map(String.init) ?? "읽기 실패")")
print("- 효율 코어(`hw.perflevel1.logicalcpu`): \(sysctlInt("hw.perflevel1.logicalcpu").map(String.init) ?? "읽기 실패")")
print("")

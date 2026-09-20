// P0-PROBE-02. 열 센서 프로브.
//
// SMC와 IOHIDEventSystem에서 온도와 팬 RPM을 **일반 권한으로** 읽을 수 있는지 확인하고,
// 이 기기의 센서 키 목록을 그대로 남긴다 (F-06) (요구사항 14.2c).
//
//   swift scripts/probes/probe-smc.swift > kb/raw/probes/YYYY-MM-DD-thermal-sensors.md
//
// 출력이 곧 원자료다. 출처 헤더까지 스크립트가 직접 찍으므로 손으로 다듬지 않는다
// (kb/raw/README.md). 해석은 kb/wiki/research/probe-results.md가 맡는다.
//
// 프로브끼리 헤더 함수를 공유하지 않고 복사해 둔다. `swift a.swift b.swift`는 b를 컴파일하지
// 않고 인자로 넘기므로, 스크립트 하나는 파일 하나로 끝나야 한다 (scripts/kb.swift 머리말).
//
// 읽기 전용이다. SMC에 쓰지 않는다. 팬 제어는 이 앱이 하지 않는 일이다 (요구사항 11).

import Foundation
import IOKit

// MARK: - 출처 헤더

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

// MARK: - SMC 구조체
//
// AppleSMC 사용자 클라이언트가 주고받는 구조체다. C 레이아웃과 바이트 단위로 같아야 하므로
// 필드 순서와 크기를 바꾸지 않는다. 아래 stride 검사가 어긋나면 즉시 멈춘다.

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

let smcZeroBytes: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // C는 이 구조체를 12바이트로 채워 바깥 구조체에 넣지만, Swift는 stride가 아니라 size(9바이트)를
    // 그대로 이어 붙인다. 채움 바이트를 직접 적지 않으면 뒤따르는 필드가 3바이트씩 앞으로 밀린다.
    var pad0: UInt8 = 0
    var pad1: UInt8 = 0
    var pad2: UInt8 = 0
}

struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = smcZeroBytes
}

let kSMCKernelIndex: UInt32 = 2
let kSMCCmdReadBytes: UInt8 = 5
let kSMCCmdReadIndex: UInt8 = 8
let kSMCCmdReadKeyInfo: UInt8 = 9

func fourCC(_ s: String) -> UInt32 {
    var r: UInt32 = 0
    for ch in s.utf8.prefix(4) { r = (r << 8) | UInt32(ch) }
    return r
}

func fourCCString(_ v: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff),
        UInt8((v >> 8) & 0xff), UInt8(v & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

final class SMC {
    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var c: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &c) == kIOReturnSuccess else { return nil }
        conn = c
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    private func call(_ input: inout SMCKeyData) -> (SMCKeyData, kern_return_t) {
        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.stride
        let rc = IOConnectCallStructMethod(
            conn, kSMCKernelIndex,
            &input, MemoryLayout<SMCKeyData>.stride,
            &output, &outSize
        )
        return (output, rc)
    }

    /// 키 하나의 자료형과 크기. 값을 읽기 전에 반드시 먼저 물어본다.
    func keyInfo(_ key: UInt32) -> (size: UInt32, type: String)? {
        var input = SMCKeyData()
        input.key = key
        input.data8 = kSMCCmdReadKeyInfo
        let (out, rc) = call(&input)
        guard rc == kIOReturnSuccess, out.result == 0 else { return nil }
        return (out.keyInfo.dataSize, fourCCString(out.keyInfo.dataType))
    }

    func readBytes(_ key: UInt32, size: UInt32) -> [UInt8]? {
        var input = SMCKeyData()
        input.key = key
        input.keyInfo.dataSize = size
        input.data8 = kSMCCmdReadBytes
        let (out, rc) = call(&input)
        guard rc == kIOReturnSuccess, out.result == 0 else { return nil }
        return withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(size))) }
    }

    /// 인덱스로 키 이름을 얻는다. #KEY가 알려 준 개수만큼 돌리면 전체 목록이 된다.
    func keyAt(index: UInt32) -> UInt32? {
        var input = SMCKeyData()
        input.data8 = kSMCCmdReadIndex
        input.data32 = index
        let (out, rc) = call(&input)
        guard rc == kIOReturnSuccess, out.result == 0 else { return nil }
        return out.key
    }

    func keyCount() -> UInt32? {
        guard let info = keyInfo(fourCC("#KEY")),
              let bytes = readBytes(fourCC("#KEY"), size: info.size),
              bytes.count >= 4 else { return nil }
        return decodeUInt(bytes)
    }
}

/// SMC의 정수는 빅엔디언이다.
func decodeUInt(_ bytes: [UInt8]) -> UInt32 {
    var v: UInt32 = 0
    for b in bytes.prefix(4) { v = (v << 8) | UInt32(b) }
    return v
}

/// 키 자료형에 맞게 값을 푼다. 모르는 자료형은 nil이다. 결측을 0으로 바꾸지 않는다
/// (.claude/rules/collector.md).
func decodeValue(type: String, bytes: [UInt8]) -> Double? {
    switch type {
    case "flt ":
        guard bytes.count >= 4 else { return nil }
        // flt만 리틀엔디언이다.
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Double(Float(bitPattern: bits))
    case "ui8 ", "ui16", "ui32":
        return Double(decodeUInt(bytes))
    case "si8 ":
        guard let b = bytes.first else { return nil }
        return Double(Int8(bitPattern: b))
    case "si32":
        guard bytes.count >= 4 else { return nil }
        var v: UInt32 = 0
        for b in bytes.prefix(4).reversed() { v = (v << 8) | UInt32(b) }
        return Double(Int32(bitPattern: v))
    case "ioft":
        // 8바이트 고정소수점(48.16)이다. GPU 온도 계열(`TG0*`)이 이 자료형을 쓴다.
        // 바이트 순서는 리틀엔디언으로 읽어야 온도 범위가 나온다. 원시 바이트를 같이 남기므로
        // 판단이 틀렸다면 원자료에서 다시 셀 수 있다.
        guard bytes.count >= 8 else { return nil }
        var v: UInt64 = 0
        for b in bytes.prefix(8).reversed() { v = (v << 8) | UInt64(b) }
        return Double(v) / 65536.0
    case "sp78":
        guard bytes.count >= 2 else { return nil }
        return Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256.0
    case "fpe2":
        guard bytes.count >= 2 else { return nil }
        return Double((UInt16(bytes[0]) << 8 | UInt16(bytes[1])) >> 2)
    default:
        return nil
    }
}

// MARK: - IOHIDEventSystem (비공개)
//
// Apple Silicon의 온도는 SMC가 아니라 IOHIDEventSystem을 지난다. 공개 헤더에 없는 심볼이라
// dlsym으로 찾는다. 찾지 못하면 그 사실이 곧 프로브 결과다.

let kIOHIDEventTypeTemperature: Int64 = 15
let kHIDPage_AppleVendor: Int = 0xff00
let kHIDUsage_AppleVendor_TemperatureSensor: Int = 0x0005

typealias FnClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
typealias FnClientSetMatching = @convention(c) (AnyObject?, CFDictionary?) -> Int32
typealias FnClientCopyServices = @convention(c) (AnyObject?) -> Unmanaged<CFArray>?
typealias FnServiceCopyProperty = @convention(c) (AnyObject?, CFString) -> Unmanaged<AnyObject>?
typealias FnServiceCopyEvent = @convention(c) (AnyObject?, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
typealias FnEventGetFloatValue = @convention(c) (AnyObject?, Int32) -> Double

struct HIDSensors {
    var clientCreated: Bool
    var missingSymbols: [String]
    var readings: [(name: String, celsius: Double)]
    var serviceCount: Int
}

func readHIDTemperatures() -> HIDSensors {
    let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
    guard let handle = dlopen(path, RTLD_LAZY) else {
        return HIDSensors(clientCreated: false, missingSymbols: ["dlopen(IOKit)"], readings: [], serviceCount: 0)
    }
    defer { dlclose(handle) }

    var missing: [String] = []
    func sym(_ name: String) -> UnsafeMutableRawPointer? {
        guard let p = dlsym(handle, name) else {
            missing.append(name)
            return nil
        }
        return p
    }

    let pCreate = sym("IOHIDEventSystemClientCreate")
    let pMatch = sym("IOHIDEventSystemClientSetMatching")
    let pServices = sym("IOHIDEventSystemClientCopyServices")
    let pProperty = sym("IOHIDServiceClientCopyProperty")
    let pEvent = sym("IOHIDServiceClientCopyEvent")
    let pFloat = sym("IOHIDEventGetFloatValue")
    guard let pCreate, let pMatch, let pServices, let pProperty, let pEvent, let pFloat else {
        return HIDSensors(clientCreated: false, missingSymbols: missing, readings: [], serviceCount: 0)
    }

    let create = unsafeBitCast(pCreate, to: FnClientCreate.self)
    let setMatching = unsafeBitCast(pMatch, to: FnClientSetMatching.self)
    let copyServices = unsafeBitCast(pServices, to: FnClientCopyServices.self)
    let copyProperty = unsafeBitCast(pProperty, to: FnServiceCopyProperty.self)
    let copyEvent = unsafeBitCast(pEvent, to: FnServiceCopyEvent.self)
    let floatValue = unsafeBitCast(pFloat, to: FnEventGetFloatValue.self)

    guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
        return HIDSensors(clientCreated: false, missingSymbols: [], readings: [], serviceCount: 0)
    }

    let matching: [String: Any] = [
        "PrimaryUsagePage": kHIDPage_AppleVendor,
        "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor,
    ]
    _ = setMatching(client, matching as CFDictionary)

    guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject] else {
        return HIDSensors(clientCreated: true, missingSymbols: [], readings: [], serviceCount: 0)
    }

    var readings: [(String, Double)] = []
    let field = Int32(truncatingIfNeeded: kIOHIDEventTypeTemperature << 16)
    for service in services {
        let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String
        guard let event = copyEvent(service, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue() else { continue }
        readings.append((name ?? "(이름 없음)", floatValue(event, field)))
    }
    return HIDSensors(
        clientCreated: true, missingSymbols: [],
        readings: readings.sorted { $0.0 < $1.0 },
        serviceCount: services.count
    )
}

// MARK: - 실행

printHeader(
    title: "\(sysctlString("hw.model") ?? "이 기기")의 열 센서: SMC 키와 IOHID 온도 센서",
    source: "swift scripts/probes/probe-smc.swift"
)

guard MemoryLayout<SMCKeyData>.stride == 80 else {
    print("중단: SMCKeyData의 크기가 \(MemoryLayout<SMCKeyData>.stride)바이트다. C 구조체와 어긋났다.")
    exit(1)
}

print("## 1. SMC 연결")
print("")

if let smc = SMC() {
    print("- AppleSMC 사용자 클라이언트 열기: **성공** (관리자 권한 없이)")
    let count = smc.keyCount()
    print("- 등록된 키 개수(`#KEY`): \(count.map(String.init) ?? "읽기 실패")")
    print("")

    struct Reading {
        var key: String
        var type: String
        var hex: String
        var value: Double?
    }

    var temperatures: [Reading] = []
    var fans: [Reading] = []
    var noInfo: [String] = []

    if let count {
        for i in 0..<count {
            guard let key = smc.keyAt(index: i) else { continue }
            let name = fourCCString(key)
            guard name.hasPrefix("T") || name.hasPrefix("F") else { continue }
            guard let info = smc.keyInfo(key), let bytes = smc.readBytes(key, size: info.size) else {
                noInfo.append(name)
                continue
            }
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            let reading = Reading(
                key: name, type: info.type, hex: hex,
                value: decodeValue(type: info.type, bytes: bytes)
            )
            if name.hasPrefix("T") {
                temperatures.append(reading)
            } else {
                fans.append(reading)
            }
        }
    }

    /// 원시 바이트를 값 옆에 같이 둔다. 자료형의 바이트 순서를 잘못 짚었더라도 원자료에서
    /// 다시 셀 수 있어야 한다.
    func printTable(_ rows: [Reading]) {
        print("| 키 | 자료형 | 원시 바이트 | 해석값 |")
        print("|---|---|---|---|")
        for r in rows.sorted(by: { $0.key < $1.key }) {
            let shown = r.value.map { String(format: "%.2f", $0) } ?? "해석 못 함"
            print("| `\(r.key)` | `\(r.type)` | `\(r.hex)` | \(shown) |")
        }
    }

    let floatTemps = temperatures.filter { $0.type == "flt " }
    let otherTemps = temperatures.filter { $0.type != "flt " }

    print("## 2. SMC 온도 키")
    print("")
    print("`T`로 시작하는 키다. 대부분 `flt ` 자료형이고 단위는 섭씨다.")
    print("")
    if floatTemps.isEmpty {
        print("없음.")
    } else {
        printTable(floatTemps)
    }
    print("")
    if !otherTemps.isEmpty {
        print("`flt ` 외의 자료형을 쓰는 온도 키다.")
        print("")
        printTable(otherTemps)
        print("")
    }

    print("## 3. SMC 팬 키")
    print("")
    if fans.isEmpty {
        print("없음.")
    } else {
        printTable(fans)
    }
    print("")
    if !noInfo.isEmpty {
        print("자료형이나 값을 아예 읽지 못한 키 \(noInfo.count)개: \(noInfo.sorted().joined(separator: ", "))")
        print("")
    }
} else {
    print("- AppleSMC 사용자 클라이언트 열기: **실패**. 일반 권한으로 SMC에 접근하지 못했다.")
    print("")
    print("## 2. SMC 온도 키")
    print("")
    print("연결이 되지 않아 읽지 못했다.")
    print("")
    print("## 3. SMC 팬 키")
    print("")
    print("연결이 되지 않아 읽지 못했다.")
    print("")
}

print("## 4. IOHIDEventSystem 온도 센서")
print("")

let hid = readHIDTemperatures()
if !hid.missingSymbols.isEmpty {
    print("- 심볼을 찾지 못했다: \(hid.missingSymbols.joined(separator: ", "))")
} else if !hid.clientCreated {
    print("- `IOHIDEventSystemClientCreate`: **실패**. 일반 권한으로 클라이언트를 만들지 못했다.")
} else {
    print("- `IOHIDEventSystemClientCreate`: **성공** (관리자 권한 없이)")
    print("- 온도 센서로 매칭된 서비스: \(hid.serviceCount)개, 값을 읽은 센서: \(hid.readings.count)개")
    print("")
    if hid.readings.isEmpty {
        print("서비스는 잡혔지만 이벤트를 읽지 못했다.")
    } else {
        print("| 센서 이름(`Product`) | ℃ |")
        print("|---|---|")
        for r in hid.readings {
            print("| \(r.name) | \(String(format: "%.2f", r.celsius)) |")
        }
    }
}
print("")

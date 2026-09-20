// P0-PROBE-04. 다른 계정이 소유한 프로세스의 사용량 프로브.
//
// 일반 권한 앱이 `proc_pid_rusage`로 root와 `_`로 시작하는 시스템 계정의 프로세스를 읽을 수
// 있는지 확인한다 (F-09) (F-23) (요구사항 14.2d). 읽지 못한다면 상위 프로세스 목록에서
// Spotlight 색인과 Time Machine 백업이 통째로 빠지므로, 요구사항 14.2d가 제안한 대체 표시
// (`시스템 프로세스(개별 측정 불가)`)가 얼마나 큰 몫인지도 함께 잰다.
//
//   swift scripts/probes/probe-rusage.swift > kb/raw/probes/YYYY-MM-DD-proc-rusage.md
//
// **개인 정보를 남기지 않는다.** 이 기기에서 도는 프로세스 이름을 그대로 찍으면 사용자가 무엇을
// 쓰는지가 공개 저장소에 남는다 (.claude/rules/docs-kb.md). 그래서 이름을 밝히는 대상은 아래
// NAMED_TARGETS에 적은 시스템 데몬뿐이고, 나머지는 계정별 개수로만 센다. 내 계정 이름도 찍지
// 않는다.
//
// 출력이 곧 원자료다 (kb/raw/README.md). 해석은 kb/wiki/research/probe-results.md가 맡는다.

import Foundation
import Darwin

/// 이름까지 밝히는 대상. 어느 맥에나 있는 시스템 데몬이라 개인 정보가 되지 않는다.
/// 앞의 셋은 요구사항 14.2d가 직접 지목한 프로세스다.
let NAMED_TARGETS = ["mds", "mds_stores", "backupd", "kernel_task", "launchd", "WindowServer"]

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

// MARK: - 프로세스 훑기

func allPIDs() -> [pid_t] {
    let capacity = Int(proc_listallpids(nil, 0))
    guard capacity > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: capacity)
    let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
    guard count > 0 else { return [] }
    // pid 0(`kernel_task`)도 남긴다. 커널이 쓴 시간이 잔여분의 큰 몫이라 빼 두면 안 된다.
    return Array(pids.prefix(Int(count))).filter { $0 >= 0 }
}

/// 정보를 어느 경로로 얻었는지. 두 경로의 권한이 다르다는 것이 이 프로브의 핵심이다.
enum InfoSource: String {
    case full = "PROC_PIDTBSDINFO"
    case short = "PROC_PIDT_SHORTBSDINFO"
    case none = "둘 다 실패"
}

struct ProcessFacts {
    var pid: pid_t
    var uid: uid_t?
    var name: String?
    var source: InfoSource
    /// 축약 정보의 이름은 15자에서 잘린다. 잘린 이름으로 매칭할 때 알아야 한다.
    var nameTruncated: Bool
}

/// 소유 계정과 이름. 전체 정보가 거부되면 축약 정보로 내려간다.
func describe(_ pid: pid_t) -> ProcessFacts {
    var full = proc_bsdinfo()
    let fullSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    let fullRC = withUnsafeMutablePointer(to: &full) {
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, fullSize)
    }
    if fullRC == fullSize {
        var name = withUnsafePointer(to: full.pbi_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: full.pbi_name)) {
                String(cString: $0)
            }
        }
        if name.isEmpty {
            name = withUnsafePointer(to: full.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: full.pbi_comm)) {
                    String(cString: $0)
                }
            }
        }
        return ProcessFacts(pid: pid, uid: full.pbi_uid, name: name, source: .full, nameTruncated: false)
    }

    var short = proc_bsdshortinfo()
    let shortSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
    let shortRC = withUnsafeMutablePointer(to: &short) {
        proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, $0, shortSize)
    }
    if shortRC == shortSize {
        let comm = withUnsafePointer(to: short.pbsi_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: short.pbsi_comm)) {
                String(cString: $0)
            }
        }
        return ProcessFacts(
            pid: pid, uid: short.pbsi_uid, name: comm, source: .short,
            nameTruncated: comm.utf8.count >= 15
        )
    }

    return ProcessFacts(pid: pid, uid: nil, name: nil, source: .none, nameTruncated: false)
}

/// `ri_user_time`과 `ri_system_time`의 단위는 나노초가 아니라 **mach 절대 시간 단위**다.
/// Apple Silicon에서 이 둘은 41.67배 차이가 나므로, 나노초로 착각하면 CPU 시간이 42분의 1로
/// 줄어든다. 이 프로브에서 부하 5.03초가 0.120초로 나오던 것이 그 증상이었다.
let machTimebase: (numer: Double, denom: Double) = {
    var info = mach_timebase_info_data_t()
    guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return (1, 1) }
    return (Double(info.numer), Double(info.denom))
}()

func machTicksToSeconds(_ ticks: UInt64) -> Double {
    Double(ticks) * machTimebase.numer / machTimebase.denom / 1_000_000_000
}

struct RUsageResult {
    var succeeded: Bool
    var errorCode: Int32
    /// 사용자 시간과 시스템 시간의 합. mach 절대 시간 단위다.
    var cpuTicks: UInt64
}

func readRUsage(_ pid: pid_t) -> RUsageResult {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    guard rc == 0 else {
        return RUsageResult(succeeded: false, errorCode: errno, cpuTicks: 0)
    }
    return RUsageResult(
        succeeded: true, errorCode: 0,
        cpuTicks: info.ri_user_time + info.ri_system_time
    )
}

func errorName(_ code: Int32) -> String {
    switch code {
    case EPERM: return "EPERM(권한 없음)"
    case ESRCH: return "ESRCH(프로세스 없음)"
    case EINVAL: return "EINVAL(잘못된 인자)"
    default: return "errno \(code)"
    }
}

/// 계정 이름. **내 계정 이름은 절대 찍지 않는다.** 시스템 계정만 이름을 밝힌다.
func accountLabel(uid: uid_t, myUID: uid_t) -> String {
    if uid == myUID { return "내 계정(uid \(uid))" }
    guard let pw = getpwuid(uid) else { return "uid \(uid)" }
    let name = String(cString: pw.pointee.pw_name)
    if name == "root" || name.hasPrefix("_") { return "\(name)(uid \(uid))" }
    return "uid \(uid)"
}

// MARK: - 전체 CPU 바쁜 시간

/// `host_statistics`의 누적 틱. 틱 하나가 코어 하나의 1/100초다.
func hostBusyTicks() -> Double? {
    var info = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard rc == KERN_SUCCESS else { return nil }
    return Double(info.cpu_ticks.0) + Double(info.cpu_ticks.1) + Double(info.cpu_ticks.3)
}

// MARK: - 실행

printHeader(
    title: "\(sysctlString("hw.model") ?? "이 기기")에서 다른 계정이 소유한 프로세스의 사용량 읽기",
    source: "swift scripts/probes/probe-rusage.swift"
)

let myUID = getuid()
let interval = 1.0

let first = allPIDs()
var described: [pid_t: ProcessFacts] = [:]
var firstUsage: [pid_t: RUsageResult] = [:]
for pid in first {
    described[pid] = describe(pid)
    firstUsage[pid] = readRUsage(pid)
}

/// 한 구간 동안 "전체 CPU 바쁜 시간"과 "읽을 수 있는 프로세스의 CPU 시간 합"을 잰다.
/// `load`가 참이면 이 프로세스가 직접 코어를 돌려 부하를 만든다. 내 계정 소유라서 읽을 수 있는
/// 부하이고, 유휴 상태와 비교하면 잔여분이 배경 부하에서 온다는 것이 드러난다.
struct Measurement {
    var busySeconds: Double
    var measuredSeconds: Double
    var missed: Int
    var utilizationPercent: Double
}

func measure(interval: Double, load: Bool, cores: Int) -> Measurement? {
    let pids = allPIDs()
    var before: [pid_t: RUsageResult] = [:]
    for pid in pids { before[pid] = readRUsage(pid) }
    guard let busyBefore = hostBusyTicks() else { return nil }

    if load {
        let deadline = Date().addingTimeInterval(interval)
        let group = DispatchGroup()
        for _ in 0..<max(1, cores / 2) {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                var acc = 0.0
                while Date() < deadline { acc += Double.random(in: 0...1) }
                if acc < 0 { print("") }  // 최적화로 반복문이 사라지지 않게 한다
            }
        }
        group.wait()
    } else {
        Thread.sleep(forTimeInterval: interval)
    }

    var after: [pid_t: RUsageResult] = [:]
    for pid in pids { after[pid] = readRUsage(pid) }
    guard let busyAfter = hostBusyTicks() else { return nil }

    // 틱 하나가 코어 하나의 1/100초다.
    let busySeconds = (busyAfter - busyBefore) / 100.0
    var measuredTicks: UInt64 = 0
    var missed = 0
    for (pid, b) in before {
        guard let a = after[pid] else { continue }
        guard b.succeeded, a.succeeded else {
            missed += 1
            continue
        }
        if a.cpuTicks >= b.cpuTicks {
            measuredTicks += a.cpuTicks - b.cpuTicks
        }
    }
    return Measurement(
        busySeconds: busySeconds,
        measuredSeconds: machTicksToSeconds(measuredTicks),
        missed: missed,
        utilizationPercent: busySeconds / (interval * Double(cores)) * 100
    )
}

// 1. 요약
print("## 1. 요약")
print("")
print("- 프로세스 \(first.count)개를 훑었다. 관리자 권한 없이 실행했다.")
let fullCount = described.values.filter { $0.source == .full }.count
let shortCount = described.values.filter { $0.source == .short }.count
let noneCount = described.values.filter { $0.source == .none }.count
print("- `proc_pidinfo(PROC_PIDTBSDINFO)` 성공: \(fullCount)개")
print("- 전체 정보가 막혀 `PROC_PIDT_SHORTBSDINFO`로 내려간 경우: \(shortCount)개 (이름과 소유 계정은 읽힌다)")
print("- 두 경로 모두 실패: \(noneCount)개")
let usageFailures = firstUsage.values.filter { !$0.succeeded }.count
print("- `proc_pid_rusage(RUSAGE_INFO_V4)` 실패: \(usageFailures)개")
print("")

// 2. 계정별 결과
print("## 2. 소유 계정별 결과")
print("")
print("계정 이름은 root와 `_`로 시작하는 시스템 계정만 밝힌다. 나머지는 uid 숫자로만 센다.")
print("")

struct Bucket {
    var total = 0
    var ok = 0
    var failures: [Int32: Int] = [:]
}
var buckets: [String: Bucket] = [:]
for (pid, info) in described {
    let label = info.uid.map { accountLabel(uid: $0, myUID: myUID) } ?? "소유 계정을 읽지 못함"
    var bucket = buckets[label] ?? Bucket()
    bucket.total += 1
    if let usage = firstUsage[pid], usage.succeeded {
        bucket.ok += 1
    } else if let usage = firstUsage[pid] {
        bucket.failures[usage.errorCode, default: 0] += 1
    }
    buckets[label] = bucket
}

print("| 소유 계정 | 프로세스 수 | rusage 성공 | 실패 |")
print("|---|---|---|---|")
for label in buckets.keys.sorted() {
    let b = buckets[label]!
    let failureText = b.failures.isEmpty
        ? "0"
        : b.failures.keys.sorted().map { "\(b.failures[$0]!)(\(errorName($0)))" }.joined(separator: ", ")
    print("| \(label) | \(b.total) | \(b.ok) | \(failureText) |")
}
print("")

// 3. 14.2d가 지목한 프로세스
print("## 3. 요구사항 14.2d가 지목한 프로세스")
print("")
print("축약 정보의 이름은 15자에서 잘리므로, 잘린 이름은 앞부분만 맞으면 같은 것으로 본다.")
print("")
print("| 프로세스 | 소유 계정 | 정보 경로 | `proc_pid_rusage` | 누적 CPU 시간(초) |")
print("|---|---|---|---|---|")
for target in NAMED_TARGETS {
    let match = described.values.first {
        guard let name = $0.name else { return false }
        return name == target || ($0.nameTruncated && target.hasPrefix(name))
    }
    guard let match else {
        print("| `\(target)` | - | 프로세스 목록에 없음 | - | - |")
        continue
    }
    let owner = match.uid.map { accountLabel(uid: $0, myUID: myUID) } ?? "읽지 못함"
    let usage = firstUsage[match.pid] ?? RUsageResult(succeeded: false, errorCode: ESRCH, cpuTicks: 0)
    let usageText = usage.succeeded ? "성공" : "실패 \(errorName(usage.errorCode))"
    let cpuText = usage.succeeded
        ? String(format: "%.1f", machTicksToSeconds(usage.cpuTicks))
        : "-"
    print("| `\(target)` | \(owner) | `\(match.source.rawValue)` | \(usageText) | \(cpuText) |")
}
print("")

// 4. 개별 측정이 안 되는 몫
print("## 4. 개별 측정이 되지 않는 CPU 시간의 몫")
print("")
let cores = sysctlInt("hw.logicalcpu") ?? 1
print("`host_statistics`가 주는 전체 CPU 바쁜 시간에서, 읽을 수 있는 프로세스의 CPU 시간 합을 뺀 것이다.")
print("그 잔여분이 요구사항 14.2d가 `시스템 프로세스(개별 측정 불가)`로 묶자고 한 몫이다.")
print("유휴 상태와 부하 상태를 따로 쟀다. 부하는 이 프로브가 코어 \(max(1, cores / 2))개를 직접 돌려 만든 것이라,")
print("내 계정 소유이고 따라서 읽을 수 있는 부하다.")
print("")
print("| 구간 | 평균 CPU 사용률 | 전체 바쁜 시간 | 읽은 합 | 잔여분 | 잔여 비율 |")
print("|---|---|---|---|---|---|")
for (label, load) in [("유휴", false), ("부하", true)] {
    guard let m = measure(interval: interval, load: load, cores: cores) else {
        print("| \(label) | `host_statistics` 읽기 실패 | - | - | - | - |")
        continue
    }
    let remainder = m.busySeconds - m.measuredSeconds
    let share = m.busySeconds > 0 ? remainder / m.busySeconds * 100 : 0
    print("| \(label) | \(String(format: "%.1f%%", m.utilizationPercent)) | \(String(format: "%.3f", m.busySeconds))초 | \(String(format: "%.3f", m.measuredSeconds))초 | \(String(format: "%.3f", remainder))초 | \(String(format: "%.1f%%", share)) |")
}
print("")
print("구간은 각각 \(interval)초이고, 논리 코어는 \(cores)개다. 코어가 여러 개라 CPU 시간의 합은 경과 시간보다 클 수 있다.")
print("")

// 5. ps와 top의 권한 비트
print("## 5. `ps`와 `top`의 권한 비트")
print("")
print("요구사항 14.2d는 두 도구가 setuid root라서 모든 프로세스를 보여 준다고 적었다.")
print("프로세스를 띄우지 않고 파일 권한만 확인한 것이다.")
print("")
print("| 파일 | 권한 | 소유자 | setuid |")
print("|---|---|---|---|")
for path in ["/bin/ps", "/usr/bin/top"] {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let permissions = attrs[.posixPermissions] as? NSNumber,
          let owner = attrs[.ownerAccountName] as? String else {
        print("| `\(path)` | 읽지 못함 | - | - |")
        continue
    }
    let mode = permissions.uint16Value
    let setuid = (mode & 0o4000) != 0
    print("| `\(path)` | \(String(mode, radix: 8)) | \(owner) | \(setuid ? "예" : "아니오") |")
}
print("")

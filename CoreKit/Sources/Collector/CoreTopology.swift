import Darwin
import Foundation
import IOKit

/// 논리 CPU 번호를 P코어와 E코어로 나눈 표 (F-03).
///
/// `host_processor_info`는 코어를 번호 순서로만 돌려주고 종류를 알려주지 않는다. 그리고 종류를
/// 이름으로 짐작하면 안 된다. `hw.perflevel0.name`은 이 기기(M5)에서 `Performance`가 아니라
/// `Super`다. 장치 트리의 `cluster-type`(`E`/`P`)이 확실한 근거다.
///
/// 이 기기에서 확인한 값: 논리 CPU 0\~5가 `E`, 6\~9가 `P`이고 `hw.perflevel0.logicalcpu` 4,
/// `hw.perflevel1.logicalcpu` 6과 맞는다. 순서를 가정하지 않고 표를 그대로 쓴다.
public struct CoreTopology: Sendable, Hashable {

    /// 번호 오름차순. 정렬해 두어야 같은 기기에서 같은 합이 나온다
    public let performance: [Int]
    public let efficiency: [Int]

    public init(performance: [Int], efficiency: [Int]) {
        self.performance = performance.sorted()
        self.efficiency = efficiency.sorted()
    }

    /// 이 기기의 표. Apple Silicon에서만 나오고, Intel 맥은 P·E 구분이 없어 `nil`이다.
    public static func current() -> CoreTopology? {
        make(
            clusterTypes: readClusterTypes(),
            performanceCount: Sysctl.int("hw.perflevel0.logicalcpu"),
            efficiencyCount: Sysctl.int("hw.perflevel1.logicalcpu")
        )
    }

    /// 장치 트리에서 읽은 표와 `sysctl`의 코어 개수를 맞춰 본다.
    ///
    /// 두 경로가 어긋나면 구분을 포기하고 `nil`을 돌린다. 틀린 구분으로 `cpu_p`를 채우면 규칙
    /// 엔진이 P코어 포화를 엉뚱한 코어에서 세고, 그 오류는 아무 신호도 내지 않는다. 구분을 잃으면
    /// `cpu_total`만 남고 `cpu_p`·`cpu_e`는 NULL이 되므로, 잘못된 값보다 이쪽이 낫다
    /// (`.claude/rules/collector.md`).
    ///
    /// 개수를 못 읽었으면(`nil`) 검산을 건너뛴다. 장치 트리 쪽이 더 직접적인 근거다.
    static func make(
        clusterTypes: [Int: String],
        performanceCount: Int?,
        efficiencyCount: Int?
    ) -> CoreTopology? {
        guard !clusterTypes.isEmpty else { return nil }

        // 사전을 정렬해 훑는다. 순서가 흔들리면 같은 기기에서 다른 표가 나온다
        let performance = clusterTypes.filter { $0.value == "P" }.keys.sorted()
        let efficiency = clusterTypes.filter { $0.value == "E" }.keys.sorted()
        guard !performance.isEmpty || !efficiency.isEmpty else { return nil }

        if let performanceCount, performanceCount != performance.count { return nil }
        if let efficiencyCount, efficiencyCount != efficiency.count { return nil }

        return CoreTopology(performance: performance, efficiency: efficiency)
    }

    // MARK: - 장치 트리

    /// `IODeviceTree:/cpus`의 자식마다 `logical-cpu-id`와 `cluster-type`을 읽는다.
    ///
    /// 공개 IOKit이다. 비공개 API 격리 대상(IOReport, IOHID)이 아니다. 자식은 서비스 평면이 아니라
    /// **장치 트리 평면**으로 훑어야 나온다. 서비스 평면으로 물으면 오류 없이 빈 표가 돌아온다.
    ///
    /// 빈 표는 Intel 맥이거나 이 속성이 없어진 경우다. 둘 다 P·E 구분이 없다는 뜻으로 다룬다.
    private static func readClusterTypes() -> [Int: String] {
        var table: [Int: String] = [:]

        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return table }
        defer { IOObjectRelease(cpus) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS
        else { return table }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let id = property(child, "logical-cpu-id") as? NSNumber,
                  let type = property(child, "cluster-type") as? Data
            else { continue }
            // OSData가 담은 것은 C 문자열이라 끝에 NUL이 붙는다. 그대로 만들면 `E`가 아니라 `E\0`이다
            table[id.intValue] = String(decoding: type.prefix { $0 != 0 }, as: UTF8.self)
        }
        return table
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}

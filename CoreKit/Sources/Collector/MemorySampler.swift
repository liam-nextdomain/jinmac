import Darwin
import Model

/// 메모리 지표 한 묶음 (F-02).
///
/// `host_statistics64` 한 번으로 얻는 값은 옵셔널이 아니고, 따로 `sysctl`을 부르는 스왑 사용량과
/// 압박 등급은 각각 실패할 수 있어 옵셔널이다. 호출이 갈리는 곳에서 결측도 갈린다.
public struct MemoryReading: Sendable, Hashable {

    /// 물리 메모리 총량 `hw.memsize`. 요구사항 7장 `sample`에는 열이 없고, 기기마다 고정인 값이라
    /// 리포트의 근거 수치로만 쓴다
    public var totalBytes: UInt64?

    /// 활성 모니터의 `사용된 메모리`와 같은 정의다. 앱 메모리(내부 페이지에서 해제 가능한 몫을 뺀
    /// 값) + 확보된 메모리 + 압축 메모리
    public var usedBytes: UInt64

    public var compressedBytes: UInt64

    /// `vm.swapusage`의 사용량. 압박이 풀린 뒤에도 남기 때문에 신호가 아니라 근거 수치다 (14.3a)
    public var swapUsedBytes: UInt64?

    /// 부팅 이후 누적. 페이지 수가 아니라 **바이트**다 (14.3a).
    ///
    /// 페이지 크기가 Apple Silicon 16KB, Intel 4KB로 달라서, 페이지 수로 저장하면 판정 쪽이
    /// 기기의 페이지 크기를 알아야 초당 바이트 기준과 비교할 수 있다. 환산은 읽은 곳이 맡는다
    public var swapInBytes: UInt64
    public var swapOutBytes: UInt64

    public var pressure: MemoryPressure?

    public init(
        totalBytes: UInt64?,
        usedBytes: UInt64,
        compressedBytes: UInt64,
        swapUsedBytes: UInt64?,
        swapInBytes: UInt64,
        swapOutBytes: UInt64,
        pressure: MemoryPressure?
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapInBytes = swapInBytes
        self.swapOutBytes = swapOutBytes
        self.pressure = pressure
    }
}

/// 메모리를 읽는다 (F-02).
///
/// 세 경로를 쓴다. `host_statistics64`로 페이지 수를, `sysctl vm.swapusage`로 스왑 사용량을,
/// `sysctl kern.memorystatus_vm_pressure_level`로 압박 등급을 읽는다. 전부 공개 API이고 일반
/// 권한으로 읽힌다.
///
/// 압박 등급은 `dispatch_source` 이벤트가 아니라 샘플마다 폴링으로 읽는다 (14.2a 채택). 이벤트는
/// 등급이 바뀌는 순간만 알려서 "지금 등급"을 기록하는 샘플링에 맞지 않고, 한 번 놓치면 현재
/// 등급을 알 방법이 없다.
public struct MemorySampler: Sampler {

    public typealias Reading = MemoryReading

    private let totalBytes: UInt64?
    private let pageSize: UInt64?

    /// `hw.memsize`와 페이지 크기는 기기마다 고정이라 한 번만 읽는다 (F-10).
    public init() {
        self.init(totalBytes: Sysctl.uint64("hw.memsize"), pageSize: Sysctl.uint64("hw.pagesize"))
    }

    /// 테스트가 페이지 크기를 Intel의 4KB로 두어 바이트 환산을 확인할 수 있게 열어 둔다.
    init(totalBytes: UInt64?, pageSize: UInt64?) {
        self.totalBytes = totalBytes
        self.pageSize = pageSize
    }

    /// 페이지 크기를 모르면 바이트로 바꿀 수 없어 메모리 묶음 전체가 결측이 된다. 16KB로
    /// 가정하면 Intel 맥에서 모든 값이 네 배로 부풀고, 그 오류는 아무 신호도 내지 않는다.
    public func read() -> MemoryReading? {
        guard let pageSize, let statistics = Self.virtualMemoryStatistics() else { return nil }

        return Self.reading(
            from: statistics,
            pageSize: pageSize,
            totalBytes: totalBytes,
            swapUsedBytes: Self.swapUsedBytes(),
            pressure: Self.pressure()
        )
    }

    /// 페이지 수를 바이트로 바꾸고 `사용된 메모리`를 계산한다.
    ///
    /// 커널을 건드리지 않아 테스트가 페이지 수를 직접 넣어 환산을 확인할 수 있다. 단위 환산 오류는
    /// 값만 배수로 틀리고 오류를 내지 않아서, 검사로 잡을 수 있게 해 두어야 한다 (프로브 결과 4.3).
    static func reading(
        from statistics: vm_statistics64,
        pageSize: UInt64,
        totalBytes: UInt64?,
        swapUsedBytes: UInt64?,
        pressure: MemoryPressure?
    ) -> MemoryReading {
        let internalPages = UInt64(statistics.internal_page_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        // 해제 가능한 몫이 내부 페이지보다 크게 보고되는 순간이 있다. UInt64 뺄셈은 그때 트랩한다
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let wiredPages = UInt64(statistics.wire_count)
        let compressedPages = UInt64(statistics.compressor_page_count)

        return MemoryReading(
            totalBytes: totalBytes,
            usedBytes: (appPages + wiredPages + compressedPages) * pageSize,
            compressedBytes: compressedPages * pageSize,
            swapUsedBytes: swapUsedBytes,
            swapInBytes: UInt64(statistics.swapins) * pageSize,
            swapOutBytes: UInt64(statistics.swapouts) * pageSize,
            pressure: pressure
        )
    }

    // MARK: - 커널 값 읽기

    private static func virtualMemoryStatistics() -> vm_statistics64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return statistics
    }

    private static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_used
    }

    private static func pressure() -> MemoryPressure? {
        guard let level = Sysctl.uint64("kern.memorystatus_vm_pressure_level") else { return nil }
        return pressure(level: level)
    }

    /// 커널의 압박 등급을 요구사항 7장 `mem_pressure`의 0/1/2로 바꾼다 (14.2a).
    ///
    /// 커널 값은 연속된 0/1/2가 아니라 1(정상)·2(경고)·4(위험)이다. 값을 그대로 저장하면 7장의
    /// 정의와 어긋나고, 아는 값이 아니면 짐작하지 않고 결측으로 둔다.
    static func pressure(level: UInt64) -> MemoryPressure? {
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return nil
        }
    }
}

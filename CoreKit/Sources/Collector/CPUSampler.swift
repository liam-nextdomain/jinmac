import Darwin
import Model

/// 부팅 이후 누적 틱. 한 읽기만으로는 사용률이 되지 않고, 두 읽기의 증가량이 사용률이 된다.
public struct CPUTicks: Sendable, Hashable {

    /// 사용자 + 시스템 + nice
    public var busy: UInt64
    public var idle: UInt64

    public init(busy: UInt64, idle: UInt64) {
        self.busy = busy
        self.idle = idle
    }

    public var total: UInt64 { busy &+ idle }
}

/// CPU 틱 한 묶음 (F-03).
///
/// 주파수(`cpu_freq`)는 여기에 없다. IOReport를 써야 하고 1단계 범위 밖이다 (프로브 결과 3).
public struct CPUReading: Sendable, Hashable {

    public var all: CPUTicks

    /// P코어 합. Intel 맥과 코어 구분을 얻지 못한 기기는 `nil`이다 (F-03)
    public var performance: CPUTicks?
    public var efficiency: CPUTicks?

    public init(all: CPUTicks, performance: CPUTicks?, efficiency: CPUTicks?) {
        self.all = all
        self.performance = performance
        self.efficiency = efficiency
    }
}

/// 구간 사용률. 요구사항 7장 `cpu_total`·`cpu_p`·`cpu_e`에 그대로 들어간다.
public struct CPUUtilization: Sendable, Hashable {

    /// 0...1
    public var total: Double?
    public var performance: Double?
    public var efficiency: Double?

    public init(total: Double?, performance: Double?, efficiency: Double?) {
        self.total = total
        self.performance = performance
        self.efficiency = efficiency
    }
}

extension CPUReading {

    /// 이전 읽기와의 틱 증가량으로 사용률을 낸다.
    ///
    /// 샘플 간격을 가정하지 않는다. 틱은 코어마다 초당 약 100번 늘기 때문에 증가량의 합이 곧 그
    /// 구간의 실제 경과 시간이고, 잠자기로 간격이 튀거나 시계가 점프해도 분모가 함께 커진다
    /// (요구사항 8장). 그래서 경과 시간을 따로 받지 않는다.
    public func utilization(since previous: CPUReading) -> CPUUtilization {
        CPUUtilization(
            total: Self.ratio(from: previous.all, to: all),
            performance: Self.ratio(from: previous.performance, to: performance),
            efficiency: Self.ratio(from: previous.efficiency, to: efficiency)
        )
    }

    /// 되감김과 증가량 0은 `nil`이다.
    ///
    /// 재부팅하면 커널의 누적 틱이 0부터 다시 시작한다. 그때 뺄셈을 그대로 하면 UInt64가 트랩하거나
    /// 되감긴 값이 사용률로 들어간다. 같은 읽기를 두 번 넘겨도 분모가 0이라 `nil`이다.
    static func ratio(from previous: CPUTicks?, to current: CPUTicks?) -> Double? {
        guard let previous, let current,
              current.busy >= previous.busy, current.idle >= previous.idle
        else { return nil }

        let total = current.total - previous.total
        guard total > 0 else { return nil }
        return Double(current.busy - previous.busy) / Double(total)
    }
}

/// CPU를 읽는다 (F-03).
///
/// `host_processor_info`의 `PROCESSOR_CPU_LOAD_INFO` 하나만 쓴다. 공개 API이고 일반 권한으로
/// 읽힌다. 코어 종류는 `CoreTopology`가 장치 트리에서 한 번 읽어 둔 표로 가른다.
public struct CPUSampler: Sampler {

    public typealias Reading = CPUReading

    private let topology: CoreTopology?

    /// 코어 구분 표는 기기마다 고정이라 한 번만 읽는다. 샘플마다 IORegistry를 훑을 이유가 없다 (F-10).
    public init() {
        self.init(topology: CoreTopology.current())
    }

    /// 테스트가 Intel(`nil`)과 Apple Silicon을 모두 흉내낼 수 있게 열어 둔다.
    public init(topology: CoreTopology?) {
        self.topology = topology
    }

    public func read() -> CPUReading? {
        guard let perCore = Self.perCoreTicks(), !perCore.isEmpty else { return nil }

        var all = CPUTicks(busy: 0, idle: 0)
        for ticks in perCore {
            all.busy &+= ticks.busy
            all.idle &+= ticks.idle
        }

        return CPUReading(
            all: all,
            performance: Self.sum(perCore, at: topology?.performance),
            efficiency: Self.sum(perCore, at: topology?.efficiency)
        )
    }

    /// 표의 번호가 이번 읽기의 코어 개수를 벗어나면 `nil`이다.
    ///
    /// 코어 개수는 부팅 뒤에도 바뀔 수 있다. 벗어난 번호를 건너뛰고 합을 내면 일부 코어만 더한
    /// 값이 사용률로 들어가므로, 그 종류 전체를 결측으로 둔다.
    static func sum(_ perCore: [CPUTicks], at indices: [Int]?) -> CPUTicks? {
        guard let indices, !indices.isEmpty else { return nil }

        var sum = CPUTicks(busy: 0, idle: 0)
        for index in indices {
            guard perCore.indices.contains(index) else { return nil }
            sum.busy &+= perCore[index].busy
            sum.idle &+= perCore[index].idle
        }
        return sum
    }

    private static func perCoreTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }

        // 커널이 할당해 준 메모리다. 5초마다 돌면서 반납하지 않으면 상주 메모리 50MB가 곧 깨진다 (F-10)
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * states
            // integer_t는 부호가 있지만 값은 누적 카운터다. Int32 최대를 넘으면 음수로 보인다
            func ticks(_ state: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: info[base + Int(state)]))
            }
            return CPUTicks(
                busy: ticks(CPU_STATE_USER) &+ ticks(CPU_STATE_SYSTEM) &+ ticks(CPU_STATE_NICE),
                idle: ticks(CPU_STATE_IDLE)
            )
        }
    }
}

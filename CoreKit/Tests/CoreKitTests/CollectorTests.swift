import Darwin
import XCTest
@testable import Collector
@testable import Model

/// 메모리·CPU 샘플러 테스트 (P1-COLL-01, P1-COLL-02).
///
/// 대부분은 커널을 건드리지 않는 순수 계산 검사다. 실기기를 읽는 검사는 마지막 `실기기` 절에만
/// 두고, 값이 흔들려도 통과하도록 범위로만 본다.
final class CollectorTests: XCTestCase {

    // MARK: - 압박 등급 (14.2a)

    /// 커널 값은 연속된 0/1/2가 아니라 1·2·4다. 그대로 저장하면 7장의 정의와 어긋난다.
    func testPressureLevelMapsToChapterSevenValues() {
        XCTAssertEqual(MemorySampler.pressure(level: 1), .normal)
        XCTAssertEqual(MemorySampler.pressure(level: 2), .warning)
        XCTAssertEqual(MemorySampler.pressure(level: 4), .critical)
    }

    /// 커널이 값을 더하면 아는 척하지 않고 결측으로 둔다. 0을 정상으로 읽으면 안 된다.
    func testUnknownPressureLevelIsMissing() {
        XCTAssertNil(MemorySampler.pressure(level: 0))
        XCTAssertNil(MemorySampler.pressure(level: 3))
        XCTAssertNil(MemorySampler.pressure(level: 8))
    }

    // MARK: - 페이지를 바이트로 (14.3a)

    private func statistics(
        internalPages: UInt32 = 0,
        purgeablePages: UInt32 = 0,
        wiredPages: UInt32 = 0,
        compressedPages: UInt32 = 0,
        swapIns: UInt64 = 0,
        swapOuts: UInt64 = 0
    ) -> vm_statistics64 {
        var value = vm_statistics64()
        value.internal_page_count = internalPages
        value.purgeable_count = purgeablePages
        value.wire_count = wiredPages
        value.compressor_page_count = compressedPages
        value.swapins = swapIns
        value.swapouts = swapOuts
        return value
    }

    private func reading(from statistics: vm_statistics64, pageSize: UInt64) -> MemoryReading {
        MemorySampler.reading(
            from: statistics, pageSize: pageSize,
            totalBytes: nil, swapUsedBytes: nil, pressure: nil)
    }

    /// `사용된 메모리` = 앱 메모리(내부 - 해제 가능) + 확보된 메모리 + 압축 메모리.
    func testUsedMemoryFollowsActivityMonitorDefinition() {
        let value = reading(
            from: statistics(
                internalPages: 100, purgeablePages: 40, wiredPages: 20, compressedPages: 10),
            pageSize: 16_384)

        XCTAssertEqual(value.usedBytes, (60 + 20 + 10) * 16_384)
        XCTAssertEqual(value.compressedBytes, 10 * 16_384)
    }

    /// 해제 가능한 몫이 내부 페이지보다 크게 보고되는 순간이 있다. UInt64 뺄셈은 그때 트랩한다.
    func testPurgeableLargerThanInternalDoesNotTrap() {
        let value = reading(
            from: statistics(internalPages: 10, purgeablePages: 999, wiredPages: 5),
            pageSize: 16_384)

        XCTAssertEqual(value.usedBytes, 5 * 16_384)
    }

    /// 스왑 누적값은 페이지 수가 아니라 바이트다. 페이지로 두면 판정 쪽이 페이지 크기를 알아야 한다.
    ///
    /// 같은 페이지 수가 Apple Silicon(16KB)과 Intel(4KB)에서 네 배 차이 나는 것을 확인한다. 이
    /// 환산을 빠뜨려도 오류는 나지 않고 값만 틀리므로 검사로 잡는다.
    func testSwapCountersAreConvertedToBytesWithThePageSize() {
        let counters = statistics(swapIns: 3, swapOuts: 7)

        let appleSilicon = reading(from: counters, pageSize: 16_384)
        XCTAssertEqual(appleSilicon.swapInBytes, 3 * 16_384)
        XCTAssertEqual(appleSilicon.swapOutBytes, 7 * 16_384)

        let intel = reading(from: counters, pageSize: 4_096)
        XCTAssertEqual(intel.swapOutBytes, 7 * 4_096)
        XCTAssertEqual(appleSilicon.swapOutBytes, intel.swapOutBytes * 4)
    }

    /// 초당 1MB(`rules.json`의 `swap_out_bytes_per_second_above`)와 비교할 수 있는 단위인지 본다.
    /// 5초 간격에 16KB 페이지 400장이면 초당 1.25MB다.
    func testSwapOutGrowthIsComparableToTheRuleThreshold() {
        let before = reading(from: statistics(swapOuts: 1_000), pageSize: 16_384)
        let after = reading(from: statistics(swapOuts: 1_400), pageSize: 16_384)

        let perSecond = Double(after.swapOutBytes - before.swapOutBytes) / 5.0
        XCTAssertEqual(perSecond, 400 * 16_384 / 5.0)
        XCTAssertGreaterThan(perSecond, 1_048_576)
    }

    // MARK: - 코어 구분 표 (F-03)

    /// 이 기기(M5)에서 읽은 실제 배치다. E코어가 앞에 오지만 순서를 가정하지 않고 표를 그대로 쓴다.
    func testClusterTypesBecomeSortedIndexLists() {
        let topology = CoreTopology.make(
            clusterTypes: [0: "E", 1: "E", 2: "E", 3: "E", 4: "E", 5: "E",
                           6: "P", 7: "P", 8: "P", 9: "P"],
            performanceCount: 4, efficiencyCount: 6)

        XCTAssertEqual(topology?.performance, [6, 7, 8, 9])
        XCTAssertEqual(topology?.efficiency, [0, 1, 2, 3, 4, 5])
    }

    /// P코어가 앞에 오는 기기가 있어도 번호를 그대로 따른다.
    func testPerformanceCoresMayComeFirst()  {
        let topology = CoreTopology.make(
            clusterTypes: [0: "P", 1: "P", 2: "E", 3: "E"],
            performanceCount: 2, efficiencyCount: 2)

        XCTAssertEqual(topology?.performance, [0, 1])
        XCTAssertEqual(topology?.efficiency, [2, 3])
    }

    /// Intel 맥에는 `cluster-type`이 없다. 빈 표는 P·E 구분이 없다는 뜻이다.
    func testEmptyClusterTableMeansNoCoreSplit() {
        XCTAssertNil(CoreTopology.make(
            clusterTypes: [:], performanceCount: nil, efficiencyCount: nil))
    }

    /// 장치 트리와 `sysctl`이 어긋나면 구분을 포기한다. 틀린 구분으로 `cpu_p`를 채우면 규칙 엔진이
    /// 엉뚱한 코어에서 포화를 세고, 그 오류는 아무 신호도 내지 않는다.
    func testCountMismatchGivesUpTheCoreSplit() {
        XCTAssertNil(CoreTopology.make(
            clusterTypes: [0: "E", 1: "P"], performanceCount: 4, efficiencyCount: 6))
    }

    /// 개수를 못 읽었으면 검산을 건너뛴다. 장치 트리 쪽이 더 직접적인 근거다.
    func testMissingCountsSkipTheCrossCheck() {
        let topology = CoreTopology.make(
            clusterTypes: [0: "E", 1: "P"], performanceCount: nil, efficiencyCount: nil)

        XCTAssertEqual(topology?.performance, [1])
        XCTAssertEqual(topology?.efficiency, [0])
    }

    /// 모르는 종류가 섞이면 어느 쪽에도 넣지 않는다. 개수 검산이 그것을 잡는다.
    func testUnknownClusterTypeIsNotCounted() {
        XCTAssertNil(CoreTopology.make(
            clusterTypes: [0: "E", 1: "X"], performanceCount: 1, efficiencyCount: 1))

        let topology = CoreTopology.make(
            clusterTypes: [0: "E", 1: "X"], performanceCount: 0, efficiencyCount: 1)
        XCTAssertEqual(topology?.performance, [])
        XCTAssertEqual(topology?.efficiency, [0])
    }

    // MARK: - 코어 종류별 합

    private let perCore = [
        CPUTicks(busy: 1, idle: 99),
        CPUTicks(busy: 2, idle: 98),
        CPUTicks(busy: 30, idle: 70),
        CPUTicks(busy: 40, idle: 60),
    ]

    func testSumAddsOnlyTheListedCores() {
        let sum = CPUSampler.sum(perCore, at: [2, 3])
        XCTAssertEqual(sum, CPUTicks(busy: 70, idle: 130))
    }

    /// 표에 없으면(Intel) 그 종류는 결측이다.
    func testSumWithoutIndicesIsMissing() {
        XCTAssertNil(CPUSampler.sum(perCore, at: nil))
        XCTAssertNil(CPUSampler.sum(perCore, at: []))
    }

    /// 코어 개수가 줄면 남은 코어만 더한 값이 사용률로 들어간다. 그 종류 전체를 결측으로 둔다.
    func testIndexBeyondTheCoreCountIsMissing() {
        XCTAssertNil(CPUSampler.sum(perCore, at: [2, 9]))
    }

    // MARK: - 사용률 (F-03)

    private func reading(all: CPUTicks, performance: CPUTicks? = nil, efficiency: CPUTicks? = nil)
        -> CPUReading {
        CPUReading(all: all, performance: performance, efficiency: efficiency)
    }

    func testUtilizationIsTheBusyShareOfTheTickGrowth() throws {
        let before = reading(
            all: CPUTicks(busy: 1_000, idle: 9_000),
            performance: CPUTicks(busy: 400, idle: 3_600),
            efficiency: CPUTicks(busy: 600, idle: 5_400))
        let after = reading(
            all: CPUTicks(busy: 1_250, idle: 9_250),
            performance: CPUTicks(busy: 600, idle: 3_600),
            efficiency: CPUTicks(busy: 650, idle: 5_650))

        let utilization = after.utilization(since: before)
        XCTAssertEqual(try XCTUnwrap(utilization.total), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(utilization.performance), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(utilization.efficiency), 0.1666666, accuracy: 1e-6)
    }

    /// 간격을 가정하지 않는다. 틱은 코어마다 초당 약 100번 늘므로 증가량의 합이 그 구간의 실제
    /// 경과 시간이다. 1초 세션과 5초 샘플에서 같은 부하가 같은 사용률로 나와야 한다 (14.3a와 같은 이유).
    func testUtilizationDoesNotDependOnTheSampleInterval() {
        let start = reading(all: CPUTicks(busy: 0, idle: 0))
        let afterOneSecond = reading(all: CPUTicks(busy: 25, idle: 75))
        let afterFiveSeconds = reading(all: CPUTicks(busy: 125, idle: 375))

        XCTAssertEqual(afterOneSecond.utilization(since: start).total,
                       afterFiveSeconds.utilization(since: start).total)
    }

    /// 재부팅하면 커널의 누적 틱이 0부터 다시 시작한다. 되감긴 값을 사용률로 쓰면 안 된다.
    func testCounterResetIsMissingRatherThanWrapped() {
        let before = reading(all: CPUTicks(busy: 5_000, idle: 5_000))
        let after = reading(all: CPUTicks(busy: 10, idle: 20))

        XCTAssertNil(after.utilization(since: before).total)
    }

    /// 같은 읽기를 두 번 넘기면 분모가 0이다. 0으로 나누거나 0%로 읽어서는 안 된다.
    func testZeroGrowthIsMissingNotZeroPercent() {
        let same = reading(all: CPUTicks(busy: 1_000, idle: 9_000))
        XCTAssertNil(same.utilization(since: same).total)
    }

    /// Intel 맥은 P·E 구분이 없다. 전체 사용률만 남고 두 열은 결측이다.
    func testIntelKeepsTotalAndDropsTheCoreSplit() throws {
        let before = reading(all: CPUTicks(busy: 0, idle: 0))
        let after = reading(all: CPUTicks(busy: 25, idle: 75))

        let utilization = after.utilization(since: before)
        XCTAssertEqual(try XCTUnwrap(utilization.total), 0.25, accuracy: 1e-9)
        XCTAssertNil(utilization.performance)
        XCTAssertNil(utilization.efficiency)
    }

    // MARK: - 샘플에 옮기기

    /// 읽은 항목만 채운다. 수집하지 않는 지표는 `nil`로 남아야 저장 계층이 NULL을 넣는다.
    func testApplyingMemoryLeavesUncollectedMetricsMissing() {
        var sample = Sample(timestamp: 1_700_000_000)
        sample.apply(MemoryReading(
            totalBytes: 17_179_869_184,
            usedBytes: 11_000_000_000,
            compressedBytes: 2_500_000_000,
            swapUsedBytes: nil,
            swapInBytes: 0,
            swapOutBytes: 16_384,
            pressure: .warning))

        XCTAssertEqual(sample.memoryUsedBytes, 11_000_000_000)
        XCTAssertEqual(sample.memoryCompressedBytes, 2_500_000_000)
        XCTAssertEqual(sample.swapOutBytes, 16_384)
        XCTAssertEqual(sample.memoryPressure, .warning)
        // 따로 실패한 스왑 사용량과 아직 수집하지 않는 2단계 지표
        XCTAssertNil(sample.swapUsedBytes)
        XCTAssertNil(sample.cpuTotal)
        XCTAssertNil(sample.gpuUtilization)
        XCTAssertNil(sample.cpuTemperature)
    }

    /// 검진의 첫 샘플에는 이전 읽기가 없어 사용률이 없다. 그래도 샘플을 버리지 않는다.
    func testFirstSampleHasNoUtilizationYet() {
        var sample = Sample(timestamp: 1_700_000_000)
        sample.apply(CPUUtilization(total: nil, performance: nil, efficiency: nil))

        XCTAssertNil(sample.cpuTotal)
        XCTAssertNil(sample.cpuPerformance)
    }

    // MARK: - 프로토콜 더블

    /// 정해진 값만 돌려주는 샘플러. 수집 루프(S06)를 실기기 없이 시험하기 위한 것이다.
    ///
    /// 값 하나만 들고 있다. 여러 번 읽는 흐름은 스텁을 여럿 두어 만든다. 가변 상태를 넣으면
    /// `@unchecked Sendable`이 필요해지는데, 그것은 CoreKit에서 먼저 물어야 하는 수단이다
    /// (`.claude/rules/corekit.md`).
    private struct StubSampler<Value: Sendable>: Sampler {
        let value: Value?

        func read() -> Value? { value }
    }

    /// 더블로 두 번 읽어 샘플 두 행을 만든다. 첫 행은 사용률이 없고 둘째 행에는 있다.
    func testSamplerDoubleDrivesTwoSamplesWithoutTouchingTheMachine() throws {
        let before = StubSampler(
            value: CPUReading(all: CPUTicks(busy: 100, idle: 900), performance: nil, efficiency: nil))
        let after = StubSampler(
            value: CPUReading(all: CPUTicks(busy: 300, idle: 1_700), performance: nil, efficiency: nil))

        let first = try XCTUnwrap(before.read())
        let second = try XCTUnwrap(after.read())

        var firstSample = Sample(timestamp: 1_700_000_000)
        firstSample.apply(CPUUtilization(total: nil, performance: nil, efficiency: nil))
        var secondSample = Sample(timestamp: 1_700_000_005)
        secondSample.apply(second.utilization(since: first))

        XCTAssertNil(firstSample.cpuTotal)
        XCTAssertEqual(try XCTUnwrap(secondSample.cpuTotal), 0.2, accuracy: 1e-9)
    }

    /// 읽기 실패는 `throw`가 아니라 `nil`이다. 수집은 멈추지 않는다 (요구사항 8장).
    func testFailedReadIsNilRatherThanAnError() {
        let sampler = StubSampler<CPUReading>(value: nil)
        XCTAssertNil(sampler.read())
    }

    // MARK: - 실기기

    /// 이 기기에서 메모리가 실제로 읽히는지 본다. 값은 흔들리므로 범위로만 본다.
    func testReadsMemoryOnThisMachine() throws {
        let value = try XCTUnwrap(MemorySampler().read())
        let total = try XCTUnwrap(value.totalBytes)

        XCTAssertGreaterThan(value.usedBytes, 0)
        XCTAssertLessThanOrEqual(value.usedBytes, total)
        XCTAssertLessThanOrEqual(value.compressedBytes, value.usedBytes)
        XCTAssertNotNil(value.pressure)
    }

    /// 두 번 읽어 사용률이 0...1에 들어오는지 본다. 사이를 쉬어 틱이 늘 시간을 준다.
    func testReadsCPUUtilizationOnThisMachine() throws {
        let sampler = CPUSampler()
        let before = try XCTUnwrap(sampler.read())
        usleep(250_000)
        let after = try XCTUnwrap(sampler.read())

        let total = try XCTUnwrap(after.utilization(since: before).total)
        XCTAssertGreaterThanOrEqual(total, 0)
        XCTAssertLessThanOrEqual(total, 1)
    }

    /// Apple Silicon에서는 코어 구분이 나와야 한다. 못 나오면 `cpu_p` 열이 계속 NULL로 남아
    /// 5장의 P코어 포화 신호를 계산할 수 없다.
    func testCoreSplitIsAvailableOnAppleSilicon() throws {
        #if arch(arm64)
        let topology = try XCTUnwrap(CoreTopology.current())
        XCTAssertFalse(topology.performance.isEmpty)
        XCTAssertFalse(topology.efficiency.isEmpty)

        let ticks = try XCTUnwrap(CPUSampler().read())
        XCTAssertNotNil(ticks.performance)
        XCTAssertNotNil(ticks.efficiency)

        // 종류별 합이 전체를 넘을 수 없다
        let performance = try XCTUnwrap(ticks.performance)
        XCTAssertLessThanOrEqual(performance.total, ticks.all.total)
        #else
        throw XCTSkip("Intel 맥에는 P·E 구분이 없다 (요구사항 14.1, 비공식 지원)")
        #endif
    }
}

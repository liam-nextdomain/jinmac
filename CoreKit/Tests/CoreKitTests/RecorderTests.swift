import os
import XCTest
@testable import Collector
@testable import Model
@testable import Recorder
@testable import Store

/// 수집 루프와 검진 상태 테스트 (P1-COLL-04, F-01, F-63).
///
/// 샘플러는 전부 더블이고 시각은 인자로 넣는다. 실기기를 읽지 않고, `sleep`으로 시간을 맞추지
/// 않는다 (`.claude/rules/testing.md`). 저장소는 임시 디렉터리에서만 연다.
final class RecorderTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinMacRecorderTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let t0: Int64 = 1_758_500_000
    private let day: Int64 = 86_400

    private func openStore() throws -> SampleStore {
        try SampleStore(directory: directory)
    }

    private func makeRecorder(
        store: SampleStore,
        memory: any Sampler<MemoryReading> = FixedSampler(value: RecorderTests.memory),
        cpu: any Sampler<CPUReading> = FixedSampler<CPUReading>(value: nil),
        flushInterval: Int64 = CheckupRecorder.defaultFlushInterval
    ) async throws -> CheckupRecorder {
        try await CheckupRecorder(store: store, memory: memory, cpu: cpu, flushInterval: flushInterval)
    }

    // MARK: - 검진 시작 (F-01)

    /// 저장소가 비어 있으면 검진이 없고, 틱은 아무것도 읽지 않는다.
    func testStartsIdleWithAnEmptyStore() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store)

        let checkup = await recorder.checkup
        let sample = await recorder.tick(at: t0)
        XCTAssertNil(checkup)
        XCTAssertNil(sample)
        let count = try await store.sampleCount()
        XCTAssertEqual(count, 0)
    }

    func testStartRecordsARunningCheckup() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store)

        let started = try await recorder.start(targetDays: 14, at: t0)

        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored, started)
        XCTAssertEqual(started.status, .running)
        XCTAssertEqual(started.startedAt, t0)
        XCTAssertEqual(started.targetDays, 14)
        XCTAssertNil(started.endedAt)
    }

    /// 검진 기간은 7·14·30일 중 하나다 (F-01). 다른 값은 설정 화면의 실수이므로 거부한다.
    func testRejectsTargetDaysOutsideTheChoices() async throws {
        let recorder = try await makeRecorder(store: try openStore())

        for days in [0, 10, 31] {
            do {
                _ = try await recorder.start(targetDays: days, at: t0)
                XCTFail("\(days)일은 거부해야 한다")
            } catch {
                XCTAssertEqual(error as? RecorderError, .invalidTargetDays(days))
            }
        }
        let checkup = await recorder.checkup
        XCTAssertNil(checkup)
    }

    /// 진행 중인 검진을 두고 새 검진을 시작하지 않는다. 초기화를 먼저 거친다.
    func testRejectsASecondStartWhileInProgress() async throws {
        let recorder = try await makeRecorder(store: try openStore())
        try await recorder.start(targetDays: 7, at: t0)

        await XCTAssertThrowsRecorderError(
            try await recorder.start(targetDays: 7, at: t0 + 10), .checkupInProgress)

        try await recorder.pause(at: t0 + 20)
        await XCTAssertThrowsRecorderError(
            try await recorder.start(targetDays: 7, at: t0 + 30), .checkupInProgress)
    }

    // MARK: - 샘플 (S05에서 넘어온 조건)

    /// 사용률은 두 읽기의 증가량이다. 첫 샘플에는 이전 읽기가 없어 CPU가 비지만, 샘플은 버리지 않고
    /// 메모리만 담아 저장한다.
    func testFirstSampleKeepsMemoryWithoutCPU() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(
            store: store, cpu: ScriptedSampler([Self.cpu(busy: 100, idle: 900)]))
        try await recorder.start(targetDays: 14, at: t0)

        let sample = try await XCTUnwrapAsync(await recorder.tick(at: t0))
        try await recorder.flush()

        XCTAssertEqual(sample.memoryUsedBytes, Self.memory.usedBytes)
        XCTAssertEqual(sample.memoryPressure, .normal)
        XCTAssertNil(sample.cpuTotal)
        let stored = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(stored, [sample])
    }

    func testSecondSampleCarriesUtilizationSinceThePreviousReading() async throws {
        let recorder = try await makeRecorder(
            store: try openStore(),
            cpu: ScriptedSampler([
                Self.cpu(busy: 100, idle: 900),
                Self.cpu(busy: 300, idle: 1_700),
            ]))
        try await recorder.start(targetDays: 14, at: t0)

        await recorder.tick(at: t0)
        let second = try await XCTUnwrapAsync(await recorder.tick(at: t0 + 5))

        XCTAssertEqual(try XCTUnwrap(second.cpuTotal), 0.2, accuracy: 1e-9)
    }

    /// 읽기 실패는 결측으로 남기고 샘플은 저장한다. 0이나 이전 값으로 채우지 않는다 (요구사항 8장).
    ///
    /// CPU를 한 번 못 읽으면 다음 샘플도 CPU가 빈다. 실패한 읽기를 건너 더 앞의 읽기와 빼면 한
    /// 샘플이 두 구간을 대표하게 된다.
    func testFailedReadingsStayMissingAndTheSampleIsKept() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(
            store: store,
            memory: FixedSampler<MemoryReading>(value: nil),
            cpu: ScriptedSampler([
                Self.cpu(busy: 100, idle: 900),
                nil,
                Self.cpu(busy: 300, idle: 1_700),
                Self.cpu(busy: 400, idle: 2_100),
            ]))
        try await recorder.start(targetDays: 14, at: t0)

        for offset in stride(from: Int64(0), through: 15, by: 5) {
            await recorder.tick(at: t0 + offset)
        }
        try await recorder.flush()

        let stored = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(stored.map(\.timestamp), [t0, t0 + 5, t0 + 10, t0 + 15])
        XCTAssertTrue(stored.allSatisfy { $0.memoryUsedBytes == nil && $0.memoryPressure == nil })
        XCTAssertEqual(stored.map { $0.cpuTotal == nil }, [true, true, true, false])
        XCTAssertEqual(try XCTUnwrap(stored[3].cpuTotal), 0.2, accuracy: 1e-9)
    }

    // MARK: - 배치 버퍼링 (요구사항 8장, 14.5b)

    /// 행마다 커밋하면 하루 디스크 쓰기 5MB 예산을 넘긴다. 버퍼에 모았다가 한 번에 넘긴다.
    func testBuffersUntilTheFlushIntervalThenWritesOneBatch() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store, flushInterval: 20)
        try await recorder.start(targetDays: 14, at: t0)

        for offset in stride(from: Int64(0), through: 15, by: 5) {
            await recorder.tick(at: t0 + offset)
        }
        var count = try await store.sampleCount()
        XCTAssertEqual(count, 0, "간격이 차기 전에는 쓰지 않는다")

        await recorder.tick(at: t0 + 20)
        count = try await store.sampleCount()
        XCTAssertEqual(count, 5)
    }

    /// 시계가 뒤로 가면 경과 시간이 음수라 간격이 영영 차지 않는다. 그때는 모은 것을 바로 쓴다.
    func testClockGoingBackwardsFlushesTheBuffer() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store, flushInterval: 600)
        try await recorder.start(targetDays: 14, at: t0)

        await recorder.tick(at: t0 + 100)
        await recorder.tick(at: t0 + 105)
        await recorder.tick(at: t0 + 50)

        let count = try await store.sampleCount()
        XCTAssertEqual(count, 3)
    }

    // MARK: - 일시정지와 재개 (F-63)

    func testPauseFlushesAndStopsSampling() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store)
        let started = try await recorder.start(targetDays: 14, at: t0)
        await recorder.tick(at: t0)
        await recorder.tick(at: t0 + 5)

        let paused = try await recorder.pause(at: t0 + 7)
        let whilePaused = await recorder.tick(at: t0 + 10)

        XCTAssertEqual(paused.status, .paused)
        XCTAssertNil(whilePaused)
        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored?.status, .paused)
        let count = try await store.sampleCount()
        XCTAssertEqual(count, 2, "일시정지 전 샘플은 쓰고, 정지 중에는 읽지 않는다")
    }

    /// 재개 뒤 첫 샘플에는 CPU가 없다. 이전 읽기를 그대로 두면 정지한 구간이 분모에 들어가
    /// 사용률이 낮게 나온다.
    ///
    /// 정지 전 읽기(1000/1000)와 재개 후 읽기(1500/1500)를 빼면 50%가 나오는데, 그 값이 나오면
    /// 안 된다.
    func testResumeDropsThePreviousCPUReading() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(
            store: store,
            cpu: ScriptedSampler([
                Self.cpu(busy: 900, idle: 900),
                Self.cpu(busy: 1_000, idle: 1_000),
                Self.cpu(busy: 1_500, idle: 1_500),
                Self.cpu(busy: 1_590, idle: 1_510),
            ]))
        let started = try await recorder.start(targetDays: 14, at: t0)
        await recorder.tick(at: t0)
        await recorder.tick(at: t0 + 5)

        try await recorder.pause(at: t0 + 6)
        let resumed = try await recorder.resume(at: t0 + 3_600)
        let first = try await XCTUnwrapAsync(await recorder.tick(at: t0 + 3_600))
        let second = try await XCTUnwrapAsync(await recorder.tick(at: t0 + 3_605))

        XCTAssertEqual(resumed.status, .running)
        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored?.status, .running)
        XCTAssertNil(first.cpuTotal)
        XCTAssertEqual(try XCTUnwrap(second.cpuTotal), 0.9, accuracy: 1e-9)
    }

    func testTransitionsFromTheWrongStateAreRejected() async throws {
        let recorder = try await makeRecorder(store: try openStore())

        await XCTAssertThrowsRecorderError(try await recorder.pause(at: t0), .notRunning)
        await XCTAssertThrowsRecorderError(try await recorder.resume(at: t0), .notPaused)
        await XCTAssertThrowsRecorderError(try await recorder.reset(), .noCheckupInProgress)

        try await recorder.start(targetDays: 14, at: t0)
        await XCTAssertThrowsRecorderError(try await recorder.resume(at: t0 + 5), .notPaused)
        try await recorder.pause(at: t0 + 10)
        await XCTAssertThrowsRecorderError(try await recorder.pause(at: t0 + 15), .notRunning)
    }

    // MARK: - 초기화 (F-63)

    /// 초기화는 진행 중인 검진의 행과 그 기간의 샘플을 지운다. 버퍼에 남은 샘플도 쓰지 않고
    /// 버린다. 앞서 끝난 검진과 그 샘플은 그대로 둔다.
    func testResetDeletesOnlyTheCheckupInProgressAndItsSamples() async throws {
        let store = try openStore()
        let earlier = try await store.insertCheckup(startedAt: t0 - 8 * day, targetDays: 7)
        try await store.updateCheckup(id: earlier, status: .completed, endedAt: t0 - day)
        try await store.insert([Sample(timestamp: t0 - 8 * day), Sample(timestamp: t0 - day - 5)])

        let recorder = try await makeRecorder(store: store, flushInterval: 600)
        let started = try await recorder.start(targetDays: 14, at: t0)
        await recorder.tick(at: t0)
        try await recorder.flush()
        await recorder.tick(at: t0 + 5)

        let current = try await recorder.reset()
        try await recorder.flush()

        XCTAssertEqual(current?.id, earlier, "남은 검진 중 가장 최근 것이 현재 검진이 된다")
        XCTAssertEqual(current?.status, .completed)
        let removed = try await store.checkup(id: started.id)
        XCTAssertNil(removed)
        let stored = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(stored.map(\.timestamp), [t0 - 8 * day, t0 - day - 5])
    }

    /// 저장 도중에 초기화가 끼어들어도 지운 검진의 샘플이 파일에 남지 않는다.
    ///
    /// actor는 `await`에서 다른 호출을 받는다. 동작을 한 줄로 세우지 않으면 저장소가 삭제를 먼저
    /// 처리하고 틱의 삽입을 나중에 처리해, 어느 검진에도 속하지 않은 샘플이 남는다. 틱마다 저장하게
    /// 두고 초기화를 동시에 여러 번 부른다.
    func testResetDuringWritesLeavesNoOrphanSamples() async throws {
        let start = t0
        for round in 0..<20 {
            let store = try SampleStore(
                directory: directory.appendingPathComponent("round-\(round)", isDirectory: true))
            let recorder = try await makeRecorder(store: store, flushInterval: 0)
            try await recorder.start(targetDays: 14, at: start)

            await withTaskGroup(of: Void.self) { group in
                for offset in 0..<40 {
                    group.addTask { await recorder.tick(at: start + Int64(offset)) }
                    if offset == 20 {
                        group.addTask { _ = try? await recorder.reset() }
                    }
                }
            }

            let count = try await store.sampleCount()
            XCTAssertEqual(count, 0, "\(round)번째 시도에서 지운 검진의 샘플이 남았다")
        }
    }

    /// 초기화한 뒤에는 새 검진을 시작할 수 있고, 첫 샘플의 CPU는 비어 있다.
    func testCanStartAgainAfterReset() async throws {
        let recorder = try await makeRecorder(
            store: try openStore(),
            cpu: ScriptedSampler([
                Self.cpu(busy: 100, idle: 900),
                Self.cpu(busy: 200, idle: 1_800),
            ]))
        try await recorder.start(targetDays: 14, at: t0)
        await recorder.tick(at: t0)
        try await recorder.reset()

        let started = try await recorder.start(targetDays: 30, at: t0 + 60)
        let sample = try await XCTUnwrapAsync(await recorder.tick(at: t0 + 60))

        XCTAssertEqual(started.targetDays, 30)
        XCTAssertNil(sample.cpuTotal)
    }

    // MARK: - 검진 종료 (F-01)

    /// 시작 시각에 목표 일수를 더한 시각에 끝난다. 그 시각부터는 읽지 않고, 모은 샘플을 쓴 뒤
    /// `completed`로 남긴다. 끝난 시각은 알아챈 시각이 아니라 예정 시각이다.
    func testCompletesAtTheScheduledEnd() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store, flushInterval: 600)
        let started = try await recorder.start(targetDays: 7, at: t0)
        let end = t0 + 7 * day

        await recorder.tick(at: t0)
        let last = await recorder.tick(at: end - 5)
        let afterEnd = await recorder.tick(at: end + 3_600)

        XCTAssertNotNil(last)
        XCTAssertNil(afterEnd)
        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored?.status, .completed)
        XCTAssertEqual(stored?.endedAt, end)
        let current = await recorder.checkup
        XCTAssertEqual(current, stored)
        let samples = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(samples.map(\.timestamp), [t0, end - 5])
    }

    /// 일시정지한 채로 기간이 지나도 끝난다. 정지한 구간도 검진 기간에 들어간다.
    func testCompletesWhilePaused() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store)
        let started = try await recorder.start(targetDays: 7, at: t0)
        try await recorder.pause(at: t0 + day)

        await recorder.tick(at: t0 + 7 * day)

        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored?.status, .completed)
        XCTAssertEqual(stored?.endedAt, t0 + 7 * day)
    }

    /// 기간이 지난 뒤에 재개를 누르면 수집을 다시 시작하지 않고 검진을 끝낸다.
    func testResumeAfterTheScheduledEndCompletesInstead() async throws {
        let recorder = try await makeRecorder(store: try openStore())
        try await recorder.start(targetDays: 7, at: t0)
        try await recorder.pause(at: t0 + day)

        let checkup = try await recorder.resume(at: t0 + 8 * day)

        XCTAssertEqual(checkup.status, .completed)
        XCTAssertEqual(checkup.endedAt, t0 + 7 * day)
    }

    /// 끝난 검진 뒤에는 새 검진을 시작할 수 있다.
    func testCanStartANewCheckupAfterCompletion() async throws {
        let recorder = try await makeRecorder(store: try openStore())
        try await recorder.start(targetDays: 7, at: t0)
        await recorder.tick(at: t0 + 7 * day)

        let next = try await recorder.start(targetDays: 14, at: t0 + 8 * day)
        XCTAssertEqual(next.status, .running)
    }

    // MARK: - 재실행 뒤 복원

    /// 앱을 다시 띄우면 진행 중인 검진을 저장소에서 이어받는다. 이전 CPU 읽기는 없으므로 첫 샘플의
    /// CPU는 비어 있다.
    func testRestoresTheCheckupInProgressFromTheStore() async throws {
        let store = try openStore()
        let first = try await makeRecorder(store: store)
        let started = try await first.start(targetDays: 14, at: t0)
        await first.tick(at: t0)
        try await first.flush()

        let second = try await makeRecorder(
            store: store, cpu: ScriptedSampler([Self.cpu(busy: 100, idle: 900)]))
        let restored = await second.checkup
        let sample = try await XCTUnwrapAsync(await second.tick(at: t0 + 60))

        XCTAssertEqual(restored, started)
        XCTAssertNil(sample.cpuTotal)
    }

    /// 앱이 꺼진 사이에 기간이 지났으면 첫 틱에서 끝낸다.
    func testRestoredCheckupPastItsEndCompletesOnTheFirstTick() async throws {
        let store = try openStore()
        let first = try await makeRecorder(store: store)
        let started = try await first.start(targetDays: 7, at: t0)

        let second = try await makeRecorder(store: store)
        let sample = await second.tick(at: t0 + 10 * day)

        XCTAssertNil(sample)
        let stored = try await store.checkup(id: started.id)
        XCTAssertEqual(stored?.status, .completed)
    }

    // MARK: - 수집 주기 (F-01)

    /// 주기는 1\~30초다. 기본값은 5초다.
    func testIntervalMustStayWithinOneToThirtySeconds() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store)

        let initial = await recorder.interval
        XCTAssertEqual(initial, 5)
        for seconds in [0, 31, -5] {
            await XCTAssertThrowsRecorderError(
                try await recorder.setInterval(seconds), .invalidInterval(seconds))
        }
        try await recorder.setInterval(1)
        try await recorder.setInterval(30)
        let changed = await recorder.interval
        XCTAssertEqual(changed, 30)

        do {
            _ = try await CheckupRecorder(
                store: store,
                memory: FixedSampler(value: Self.memory),
                cpu: FixedSampler<CPUReading>(value: nil),
                interval: 0)
            XCTFail("0초는 거부해야 한다")
        } catch {
            XCTAssertEqual(error as? RecorderError, .invalidInterval(0))
        }
    }

    /// 주기 실행은 틱 → 설정한 주기만큼 대기를 되풀이한다. 대기가 끝나지 않으면(취소) 멈추고,
    /// 모아 둔 샘플을 쓴다.
    ///
    /// 시계와 대기를 주입해서 실제로 기다리지 않는다.
    func testRunLoopTicksAtTheIntervalAndFlushesWhenItStops() async throws {
        let store = try openStore()
        let recorder = try await makeRecorder(store: store, flushInterval: 600)
        try await recorder.start(targetDays: 14, at: t0)
        try await recorder.setInterval(12)

        let clock = TestClock(now: t0, stopAfter: 3)
        await recorder.run(now: clock.now, sleep: clock.sleep)

        XCTAssertEqual(clock.sleeps, [.seconds(12), .seconds(12), .seconds(12)])
        let stored = try await store.samples(from: 0, to: .max, limit: 10)
        XCTAssertEqual(stored.map(\.timestamp), [t0, t0 + 12, t0 + 24])
    }

    // MARK: - 픽스처

    private static let memory = MemoryReading(
        totalBytes: 17_179_869_184,
        usedBytes: 9_663_676_416,
        compressedBytes: 1_073_741_824,
        swapUsedBytes: 0,
        swapInBytes: 0,
        swapOutBytes: 0,
        pressure: .normal)

    private static func cpu(busy: UInt64, idle: UInt64) -> CPUReading {
        CPUReading(all: CPUTicks(busy: busy, idle: idle), performance: nil, efficiency: nil)
    }
}

// MARK: - 더블

/// 늘 같은 값을 돌려주는 샘플러. `nil`이면 매번 읽기에 실패한다.
private struct FixedSampler<Value: Sendable>: Sampler {
    let value: Value?

    func read() -> Value? { value }
}

/// 정해 둔 값을 차례로 돌려주고, 다 쓰면 `nil`(읽기 실패)을 돌려준다.
///
/// 여러 번 읽는 흐름에는 가변 상태가 필요하다. 잠금이 상태를 소유하게 해서 `@unchecked Sendable`
/// 없이 `Sendable`을 지킨다 (`.claude/rules/corekit.md`).
private final class ScriptedSampler<Value: Sendable>: Sampler, Sendable {
    private let queue: OSAllocatedUnfairLock<[Value?]>

    init(_ values: [Value?]) {
        queue = OSAllocatedUnfairLock(initialState: values)
    }

    func read() -> Value? {
        queue.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    }
}

/// 주기 실행에 넣는 시계. 대기하는 대신 시각을 그만큼 앞당기고, 정해 둔 횟수가 차면 취소로 끝낸다.
private final class TestClock: Sendable {
    private struct State {
        var now: Int64
        var sleeps: [Duration] = []
    }

    private let state: OSAllocatedUnfairLock<State>
    private let stopAfter: Int

    init(now: Int64, stopAfter: Int) {
        state = OSAllocatedUnfairLock(initialState: State(now: now))
        self.stopAfter = stopAfter
    }

    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    var now: @Sendable () -> Int64 {
        { [state] in state.withLock { $0.now } }
    }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [state, stopAfter] duration in
            let count = state.withLock { value in
                value.sleeps.append(duration)
                value.now += duration.components.seconds
                return value.sleeps.count
            }
            if count >= stopAfter { throw CancellationError() }
        }
    }
}

// MARK: - 단언

private func XCTAssertThrowsRecorderError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: RecorderError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("\(expected) 오류가 나야 한다", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? RecorderError, expected, file: file, line: line)
    }
}

/// `XCTUnwrap`은 `async` 식을 받지 못한다.
private func XCTUnwrapAsync<T>(
    _ expression: @autoclosure () async throws -> T?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}

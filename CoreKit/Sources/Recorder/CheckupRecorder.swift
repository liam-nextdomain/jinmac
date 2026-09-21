import Collector
import Foundation
import Model
import Store

/// 수집 루프와 검진 상태 (F-01, F-63).
///
/// 주기마다 샘플러를 읽어 샘플 한 행을 만들고, 버퍼에 모았다가 한 번에 저장한다. 검진 시작·
/// 일시정지·재개·초기화·종료의 전이 규칙도 여기에 있다.
///
/// 시각은 인자로 받는다. 틱과 전이는 `at:`으로 받고, 주기 실행은 시계와 대기를 주입받는다. 그래서
/// 테스트가 실제로 기다리지 않고 14일을 흘려 볼 수 있다.
///
/// 판정 쪽(`Verdict`, `Report`, `Narrator`)은 이 모듈을 import하지 않는다. 판정이 살아 있는 수집
/// 상태에 기대면 같은 입력에 같은 출력을 보장할 수 없다 (F-33).
public actor CheckupRecorder {

    /// F-01의 기본 수집 주기(초)
    public static let defaultInterval = 5

    /// F-01의 설정 범위(초)
    public static let intervalRange = 1...30

    /// 버퍼를 비우는 간격(초). 첫 샘플과 지금 샘플의 시각 차이로 잰다.
    ///
    /// 행마다 커밋하면 하루 디스크 쓰기 5MB 예산을 넘긴다 (요구사항 8장, 14.5b). 커밋마다 WAL에
    /// 페이지를 통째로 쓰기 때문이다. 10분이면 하루 144번이고, 앱이 비정상 종료해도 잃는 샘플은
    /// 10분치다. 실제 쓰기량은 P1-STORE-02에서 잰다.
    public static let defaultFlushInterval: Int64 = 600

    /// 저장이 계속 실패할 때 버퍼가 들고 있을 최대 샘플 수. 넘으면 오래된 것부터 버린다.
    ///
    /// 5초 주기로 5시간치이고 메모리는 약 1.5MB다. 제한이 없으면 저장소가 망가진 채로 며칠이
    /// 지나 상주 메모리 50MB 예산(F-10)을 넘긴다.
    static let maxBufferedSamples = 3_600

    private let store: SampleStore
    private let memorySampler: any Sampler<MemoryReading>
    private let cpuSampler: any Sampler<CPUReading>
    private let flushInterval: Int64

    /// 가장 최근 검진. 진행 중이거나, 끝났거나, 한 번도 시작하지 않았으면 `nil`이다.
    public private(set) var checkup: Checkup?

    /// 수집 주기(초). 바꾸면 다음 대기부터 적용된다.
    public private(set) var interval: Int

    /// 마지막 저장 실패. 다음 저장에 성공하면 `nil`로 돌아간다. 메뉴가 경고를 띄울 자리다.
    public private(set) var lastWriteError: (any Error)?

    /// 사용률은 두 읽기의 증가량이라 이전 읽기를 들고 있다 (S05).
    ///
    /// 검진 시작·재개·초기화 때 버린다. 정지한 구간이 분모에 들어가면 사용률이 낮게 나온다.
    private var previousCPU: CPUReading?

    private var buffer: [Sample] = []

    /// 공개 동작을 한 줄로 세운다.
    ///
    /// actor는 `await`에서 다른 호출을 받아들인다. 버퍼를 쓰는 도중에 초기화가 끼어들면, 저장소
    /// actor가 삭제를 먼저 처리하고 지운 검진의 샘플을 나중에 써 넣을 수 있다. 그 샘플은 어느
    /// 검진에도 속하지 않은 채 남고, 사용자는 지웠다고 생각한 기록이 파일에 남는다.
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// 저장소에서 가장 최근 검진을 이어받는다. 진행 중이던 검진이면 첫 틱부터 다시 수집한다.
    ///
    /// 샘플러는 한 번 만들어 계속 쓴다. 만들 때 기기마다 고정인 값(`hw.memsize`, 페이지 크기,
    /// 코어 구분 표)을 읽으므로 샘플마다 새로 만들면 F-10 예산을 깎는다 (S05).
    public init(
        store: SampleStore,
        memory: any Sampler<MemoryReading> = MemorySampler(),
        cpu: any Sampler<CPUReading> = CPUSampler(),
        interval: Int = CheckupRecorder.defaultInterval,
        flushInterval: Int64 = CheckupRecorder.defaultFlushInterval
    ) async throws {
        guard Self.intervalRange.contains(interval) else {
            throw RecorderError.invalidInterval(interval)
        }
        let latest = try await store.latestCheckup()

        self.store = store
        self.memorySampler = memory
        self.cpuSampler = cpu
        self.interval = interval
        self.flushInterval = flushInterval
        self.checkup = latest
    }

    /// 벽시계의 Unix 시각(초). 샘플 시각과 검진 시각이 이것을 쓴다.
    public static func wallClock() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    // MARK: - 주기 실행 (F-01)

    /// 틱 → 주기만큼 대기를 되풀이한다. 작업이 취소되거나 대기가 오류를 내면 멈추고, 모아 둔
    /// 샘플을 쓴다.
    ///
    /// 앱이 실행될 때 한 번 띄워 두면 된다. 검진이 없거나 일시정지 중일 때의 틱은 읽지 않고
    /// 종료 시각만 확인한다.
    ///
    /// 기본 대기 `Task.sleep`은 `ContinuousClock`을 쓴다. 잠자기 동안에도 시간이 흐르므로 깨어나면
    /// 곧바로 틱이 돈다. 샘플 간격은 가정하지 않는다. 사용률은 틱 증가량으로, 스왑 비율은 실제
    /// 시각 차이로 계산한다.
    public func run(
        now: @Sendable () -> Int64 = { CheckupRecorder.wallClock() },
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        while !Task.isCancelled {
            await tick(at: now())
            do {
                try await sleep(.seconds(interval))
            } catch {
                break
            }
        }

        await acquire()
        defer { release() }
        await writeBufferRecordingFailure()
    }

    public func setInterval(_ seconds: Int) throws {
        guard Self.intervalRange.contains(seconds) else {
            throw RecorderError.invalidInterval(seconds)
        }
        interval = seconds
    }

    /// 한 주기의 일. 검진이 수집 중이면 샘플 한 행을 만들어 버퍼에 넣고 그 샘플을 돌려준다.
    ///
    /// 수집 중이 아니거나 이번 틱에 검진이 끝났으면 `nil`이다. 저장 실패는 던지지 않는다. 수집은
    /// 저장소 오류로 멈추지 않고, 버퍼가 샘플을 들고 다음 저장을 기다린다 (요구사항 8장).
    @discardableResult
    public func tick(at now: Int64) async -> Sample? {
        await acquire()
        defer { release() }

        do {
            if try await completeIfDue(at: now) { return nil }
        } catch {
            // 종료를 기록하지 못했다. 기간이 지났으니 읽지 않고 다음 틱에 다시 끝낸다
            lastWriteError = error
            return nil
        }
        guard checkup?.status == .running else { return nil }

        let sample = read(at: now)
        buffer.append(sample)

        // 시계가 뒤로 가면 경과 시간이 음수라 간격이 영영 차지 않는다. 그때는 모은 것을 바로 쓴다
        if let oldest = buffer.first?.timestamp, now - oldest >= flushInterval || now < oldest {
            await writeBufferRecordingFailure()
        }
        return sample
    }

    /// 버퍼를 지금 쓴다. 기간 중 리포트 요청(F-30)과 앱 종료가 부른다.
    public func flush() async throws {
        await acquire()
        defer { release() }
        try await writeBuffer()
    }

    // MARK: - 검진 상태 (F-63)

    /// 새 검진을 시작한다. 진행 중인 검진이 있으면 거부한다. 초기화하거나 기간이 끝나야 한다.
    @discardableResult
    public func start(targetDays: Int = Checkup.defaultTargetDays, at now: Int64) async throws -> Checkup {
        await acquire()
        defer { release() }

        guard Checkup.targetDayChoices.contains(targetDays) else {
            throw RecorderError.invalidTargetDays(targetDays)
        }
        if let checkup, checkup.status.isInProgress {
            throw RecorderError.checkupInProgress
        }

        let id = try await store.insertCheckup(startedAt: now, targetDays: targetDays)
        let started = Checkup(id: id, startedAt: now, targetDays: targetDays, status: .running)
        checkup = started
        buffer.removeAll()
        previousCPU = nil
        return started
    }

    /// 모아 둔 샘플을 쓰고 수집을 멈춘다. 기간이 이미 지났으면 대신 검진을 끝낸다.
    @discardableResult
    public func pause(at now: Int64) async throws -> Checkup {
        await acquire()
        defer { release() }

        guard var current = checkup, current.status == .running else {
            throw RecorderError.notRunning
        }
        if try await completeIfDue(at: now), let checkup { return checkup }

        try await writeBuffer()
        try await store.updateCheckup(id: current.id, status: .paused)
        current.status = .paused
        checkup = current
        previousCPU = nil
        return current
    }

    /// 수집을 다시 시작한다. 기간이 이미 지났으면 재개하지 않고 검진을 끝낸다.
    ///
    /// 재개 뒤 첫 샘플에는 CPU 사용률이 없다. 정지 전 읽기와 빼면 정지한 구간이 분모에 들어간다.
    @discardableResult
    public func resume(at now: Int64) async throws -> Checkup {
        await acquire()
        defer { release() }

        guard var current = checkup, current.status == .paused else {
            throw RecorderError.notPaused
        }
        if try await completeIfDue(at: now), let checkup { return checkup }

        try await store.updateCheckup(id: current.id, status: .running)
        current.status = .running
        checkup = current
        previousCPU = nil
        return current
    }

    /// 진행 중인 검진과 그 기간의 샘플을 지운다. 버퍼에 남은 샘플은 쓰지 않고 버린다.
    ///
    /// 앞서 끝난 검진은 남는다. 돌려주는 값은 남은 검진 중 가장 최근 것이고, 없으면 `nil`이다.
    @discardableResult
    public func reset() async throws -> Checkup? {
        await acquire()
        defer { release() }

        guard let current = checkup, current.status.isInProgress else {
            throw RecorderError.noCheckupInProgress
        }

        try await store.deleteCheckup(id: current.id)
        buffer.removeAll()
        previousCPU = nil
        lastWriteError = nil
        checkup = nil
        checkup = try await store.latestCheckup()
        return checkup
    }

    // MARK: - 내부 동작 (잠금을 잡은 쪽에서만 부른다)

    /// 기간이 지났으면 모은 샘플을 쓰고 검진을 끝낸다. 끝냈으면 `true`.
    ///
    /// 끝난 시각은 알아챈 시각이 아니라 예정 시각이다. 잠자기 중에 기간이 지나 깨어나서야 알아채도
    /// 검진 기간이 늘어나지 않는다. 샘플을 다 쓰기 전에는 끝내지 않는다. 먼저 끝내면 리포트가
    /// 마지막 몇 분을 빠뜨린다.
    private func completeIfDue(at now: Int64) async throws -> Bool {
        guard var current = checkup, current.status.isInProgress, now >= current.scheduledEndAt else {
            return false
        }

        try await writeBuffer()
        try await store.updateCheckup(id: current.id, status: .completed, endedAt: current.scheduledEndAt)
        current.status = .completed
        current.endedAt = current.scheduledEndAt
        checkup = current
        previousCPU = nil
        return true
    }

    /// 샘플러를 읽어 샘플 한 행을 만든다. 읽지 못한 묶음은 건드리지 않아 `nil`로 남는다.
    ///
    /// CPU를 못 읽으면 이전 읽기도 버린다. 다음 샘플이 실패한 읽기를 건너 더 앞의 읽기와 빼면 한
    /// 샘플이 두 구간을 대표한다.
    private func read(at now: Int64) -> Sample {
        var sample = Sample(timestamp: now)
        if let memory = memorySampler.read() {
            sample.apply(memory)
        }

        let cpu = cpuSampler.read()
        if let cpu, let previousCPU {
            sample.apply(cpu.utilization(since: previousCPU))
        }
        previousCPU = cpu
        return sample
    }

    private func writeBuffer() async throws {
        guard !buffer.isEmpty else { return }
        try await store.insert(buffer)
        buffer.removeAll(keepingCapacity: true)
        lastWriteError = nil
    }

    /// 실패해도 버퍼를 지키고 다음 저장을 기다린다. 버퍼가 한도를 넘으면 오래된 것부터 버린다.
    private func writeBufferRecordingFailure() async {
        do {
            try await writeBuffer()
        } catch {
            lastWriteError = error
            let overflow = buffer.count - Self.maxBufferedSamples
            if overflow > 0 {
                buffer.removeFirst(overflow)
            }
        }
    }

    // MARK: - 직렬화

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// 기다리는 쪽이 있으면 잠금을 풀지 않고 그대로 넘긴다.
    private func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

public enum RecorderError: Error, Equatable {
    /// 검진 기간은 `Checkup.targetDayChoices` 중 하나다 (F-01)
    case invalidTargetDays(Int)
    /// 수집 주기는 `CheckupRecorder.intervalRange` 안이다 (F-01)
    case invalidInterval(Int)
    /// 진행 중인 검진이 있어 새로 시작할 수 없다
    case checkupInProgress
    /// 수집 중인 검진이 없어 일시정지할 수 없다
    case notRunning
    /// 일시정지한 검진이 없어 재개할 수 없다
    case notPaused
    /// 진행 중인 검진이 없어 초기화할 수 없다
    case noCheckupInProgress
}

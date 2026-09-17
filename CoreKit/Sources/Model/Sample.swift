import Foundation

/// 수집 한 번의 결과. 요구사항 7장 `sample` 테이블의 한 행이다.
///
/// 읽지 못한 지표는 0이 아니라 `nil`이다. 센서 읽기 실패·권한 거부·비공개 API 변경이 있어도
/// 해당 샘플의 그 항목만 결측으로 남긴다 (8장 견고성). 0으로 채우면 규칙 엔진이 "여유"로 읽는다.
public struct Sample: Sendable, Hashable, Codable {
    /// Unix 시각(초). 잠자기 뒤에는 간격이 튄다. 간격을 가정하지 않는다
    public var timestamp: Int64

    // MARK: 메모리 (F-02)

    public var memoryUsedBytes: UInt64?
    public var memoryCompressedBytes: UInt64?
    public var swapUsedBytes: UInt64?
    /// 누적값. 구간 증가량으로 읽는다
    public var swapIns: UInt64?
    /// 누적값. 구간 증가량으로 읽는다
    public var swapOuts: UInt64?
    public var memoryPressure: MemoryPressure?

    // MARK: CPU (F-03)

    /// 0...1
    public var cpuTotal: Double?
    /// P코어 평균, 0...1. Intel 맥은 `nil`
    public var cpuPerformance: Double?
    /// E코어 평균, 0...1. Intel 맥은 `nil`
    public var cpuEfficiency: Double?
    public var cpuFrequencyMHz: Double?

    // MARK: GPU (F-04)

    /// 0...1
    public var gpuUtilization: Double?
    public var gpuMemoryBytes: UInt64?

    // MARK: 디스크 (F-05)

    public var diskReadBytes: UInt64?
    public var diskWriteBytes: UInt64?
    /// 7장의 `io_wait`. macOS에는 iowait 지표가 없어 정의를 다시 정해야 한다 (요구사항 14.2)
    public var ioWait: Double?
    /// 0...1
    public var diskFreeRatio: Double?

    // MARK: 열 (F-06)

    public var cpuTemperature: Double?
    public var gpuTemperature: Double?
    public var fanRPM: Double?
    public var throttled: Bool?

    // MARK: 전력·컨텍스트 (F-07, F-08)

    public var onBattery: Bool?
    public var idle: Bool?
    /// 번들 ID만 남긴다. 창 제목·파일명·URL은 수집하지 않는다 (8장 프라이버시)
    public var frontmostBundleID: String?

    public init(timestamp: Int64) {
        self.timestamp = timestamp
    }
}

/// macOS 메모리 압박 등급. 7장 `mem_pressure` 컬럼의 0/1/2 값과 같다.
public enum MemoryPressure: Int, Sendable, Hashable, Codable, CaseIterable {
    case normal = 0
    case warning = 1
    case critical = 2
}

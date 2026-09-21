import Model

/// 읽은 묶음을 샘플 한 행에 옮긴다.
///
/// 읽은 항목만 채우고 나머지는 건드리지 않는다. 저장 계층이 `nil`을 NULL로 넣으므로 0을 채워 넣을
/// 이유가 없고, 채워 넣으면 규칙 엔진이 그 샘플을 "여유"로 읽는다 (요구사항 8장).
extension Sample {

    public mutating func apply(_ memory: MemoryReading) {
        memoryUsedBytes = memory.usedBytes
        memoryCompressedBytes = memory.compressedBytes
        swapUsedBytes = memory.swapUsedBytes
        swapInBytes = memory.swapInBytes
        swapOutBytes = memory.swapOutBytes
        memoryPressure = memory.pressure
    }

    /// 사용률은 두 읽기의 증가량이라서, 검진의 첫 샘플에는 이전 읽기가 없어 세 값 모두 `nil`이다.
    /// 수집 루프가 그 샘플을 버리지 않고 메모리만 담아 저장한다 (S06).
    public mutating func apply(_ cpu: CPUUtilization) {
        cpuTotal = cpu.total
        cpuPerformance = cpu.performance
        cpuEfficiency = cpu.efficiency
    }
}

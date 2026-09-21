import Darwin

/// `sysctl` 정수 읽기. 샘플러 여럿이 쓰므로 한 곳에 둔다.
///
/// `sysctl` **명령**을 띄워 값을 얻지 않는다. 프로세스 생성 비용만으로 5초 간격에서 F-10의
/// 예산이 깨진다 (`.claude/rules/collector.md`).
enum Sysctl {

    /// 노드의 크기를 먼저 물어 4바이트와 8바이트를 모두 받는다.
    ///
    /// 크기를 8바이트로 가정하고 물으면 4바이트 노드에서 `ENOMEM`으로 실패하고, 4바이트로
    /// 가정하면 8바이트 노드의 상위 절반이 잘린다. `hw.memsize`가 8바이트,
    /// `kern.memorystatus_vm_pressure_level`이 4바이트라서 두 경우가 실제로 다 나온다.
    static func uint64(_ name: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }

        switch size {
        case 4:
            var value: UInt32 = 0
            var length = size
            guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
            return UInt64(value)
        case 8:
            var value: UInt64 = 0
            var length = size
            guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
            return value
        default:
            // 정수 노드가 아니다. 크기를 짐작해 읽으면 쓰레기 값이 나오므로 결측으로 둔다
            return nil
        }
    }

    static func int(_ name: String) -> Int? {
        guard let value = uint64(name) else { return nil }
        return Int(exactly: value)
    }
}

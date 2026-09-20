import Foundation
import Narrator

/// `--probe-narrator` 인자로 실행했을 때만 도는 숨은 진입점이다 (P0-PROBE-01).
///
/// 배포 서명 설치본에서 Foundation Models가 실제로 문장을 만드는지 확인하려면, 그 설치본의
/// 바이너리를 그대로 실행해야 한다. 메뉴를 거치지 않는 이유는 출력이 터미널로 나와야 원자료로
/// 옮길 수 있기 때문이다.
///
///     /Applications/JinMac.app/Contents/MacOS/JinMac --probe-narrator
///
/// 메뉴바 앱을 띄우지 않고 결과만 찍고 끝낸다. 이 경로는 사용자가 쓰는 흐름에 없다.
enum NarratorProbeCommand {

    static let flag = "--probe-narrator"

    static var requested: Bool {
        CommandLine.arguments.contains(flag)
    }

    /// 결과를 찍고 프로세스를 끝낸다. 돌아오지 않는다.
    static func runAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        // 결과를 옮겨 담을 자리. 아래 `wait`가 끝난 뒤에만 읽으므로 경합하지 않는다.
        nonisolated(unsafe) var outcome: NarratorProbeResult?

        // 메인 스레드를 막고 기다린다. `NarratorProbe`는 메인 액터를 요구하지 않으므로
        // 교착하지 않고, 이 진입점은 결과를 찍은 즉시 끝나므로 막아도 잃을 것이 없다.
        Task {
            outcome = await NarratorProbe.generateOneSentence()
            semaphore.signal()
        }

        // A-06의 목표는 10초다. 그보다 넉넉히 주되, 멈춘 채로 남지는 않게 한다.
        if semaphore.wait(timeout: .now() + 120) == .timedOut {
            print("실패: 120초 안에 응답이 없었습니다.")
            exit(2)
        }

        printHeader()
        switch outcome {
        case .generated(let text, let seconds):
            print("결과: 생성 성공")
            print("걸린 시간: \(String(format: "%.2f", seconds))초")
            print("")
            print("생성된 문장:")
            print(text)
            exit(0)
        case .unavailable(let reason):
            print("결과: 모델을 부르지 않았습니다")
            print("사유: \(reason)")
            exit(1)
        case .failed(let reason):
            print("결과: 생성 실패")
            print("사유: \(reason)")
            exit(1)
        case nil:
            print("결과: 알 수 없음. 작업이 값을 남기지 않았습니다.")
            exit(2)
        }
    }

    /// 출력이 그대로 `kb/raw/probes/`로 가므로 출처 헤더를 같이 찍는다 (kb/raw/README.md).
    private static func printHeader() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        print("# \(sysctlString("hw.model") ?? "이 기기")에서 Foundation Models 문장 생성")
        print("")
        print("**Source:** JinMac \(version) (\(build)) --probe-narrator")
        print("**Collected:** \(today)")
        print("**Published:** N/A (직접 측정)")
        print("**Machine:** \(sysctlString("hw.model") ?? "unknown"), "
            + "\(sysctlString("machdep.cpu.brand_string") ?? "unknown"), "
            + "macOS \(sysctlString("kern.osproductversion") ?? "unknown")")
        // 홈 디렉터리를 `~/`로 줄인다. 출력이 공개 저장소의 원자료가 되므로 사용자 이름이
        // 들어간 경로를 그대로 남기지 않는다 (`.claude/rules/docs-kb.md`).
        let home = NSHomeDirectory()
        let path = bundle.bundlePath.hasPrefix(home)
            ? "~" + bundle.bundlePath.dropFirst(home.count)
            : bundle.bundlePath
        print("**App path:** \(path)")
        print("")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        if let end = buf.firstIndex(of: 0) { buf = Array(buf[..<end]) }
        return String(decoding: buf, as: UTF8.self)
    }
}

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 0단계 검증 결과 (P0-PROBE-01).
public enum NarratorProbeResult: Sendable, Equatable {
    /// 문장이 나왔다. 걸린 시간을 함께 담는다. A-06의 10초 목표를 가늠하기 위해서다.
    case generated(text: String, seconds: Double)
    /// 모델을 부르지 않았다. 사유는 `NarratorAvailability`가 그대로 돌려준 것이다.
    case unavailable(NarratorAvailability)
    /// 모델을 불렀으나 실패했다.
    case failed(reason: String)
}

/// 배포 서명 설치본에서 Foundation Models가 **실제로 한국어 문장을 만드는지** 한 번 확인하는
/// 최소 경로다 (P0-PROBE-01) (A-01) (요구사항 13).
///
/// 이것은 `Narrator`의 본 구현이 아니다. 본 구현은 2단계에서 `@Generable` 구조체를 받고 수치를
/// 검증한다 (A-03, A-04). 여기서는 문장이 나오는지, 한국어로 나오는지, 얼마나 걸리는지만 본다.
/// 그래서 결과가 리포트로 흘러가지 않고 프로브 출력으로만 쓰인다.
///
/// 앱에서는 `--probe-narrator` 인자로만 불린다 (`App/NarratorProbeCommand.swift`).
public enum NarratorProbe {

    /// 요구사항 6장의 문체 지시다. 존댓말로 설명하고, 등급과 수치를 바꾸지 않으며,
    /// 기기 이름이나 가격을 말하지 않는다.
    public static let instructions = """
        당신은 맥 사용 기록 검진 리포트의 문장을 다듬는 역할입니다.
        주어진 등급과 수치를 바꾸지 말고, 그 값만 사용해 존댓말로 설명하십시오.
        과장하지 말고, 기기 이름이나 가격은 언급하지 마십시오.
        """

    /// 합성 판정값이다. 실제 기기의 사용 기록을 넣지 않는다 (`.claude/rules/docs-kb.md`).
    public static let prompt = """
        다음 판정을 한 문장으로 설명하십시오.
        자원: 메모리
        등급: 한계
        한계 신호가 활성 시간에서 차지한 비율: 23%
        """

    /// 가용성을 주입받는다. 기본값은 실제 확인이고, 테스트는 사유를 넣어 모델을 건드리지 않는다.
    public static func generateOneSentence(
        availability: NarratorAvailability = .current()
    ) async -> NarratorProbeResult {
        guard availability == .available else { return .unavailable(availability) }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await respondOnce()
        }
        #endif
        // 가용성은 `.available`인데 프레임워크가 없다. 일어나면 안 되는 조합이다.
        return .unavailable(.unavailable)
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension NarratorProbe {
    /// 벽시계가 아니라 단조 시계로 잰다. 잠자기와 시각 보정에 흔들리지 않는다.
    static func respondOnce() async -> NarratorProbeResult {
        let clock = ContinuousClock()
        let started = clock.now
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let elapsed = Double((clock.now - started).components.seconds)
                + Double((clock.now - started).components.attoseconds) / 1e18
            return .generated(text: response.content, seconds: elapsed)
        } catch {
            return .failed(reason: String(describing: error))
        }
    }
}
#endif

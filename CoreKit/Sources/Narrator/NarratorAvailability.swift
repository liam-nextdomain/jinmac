import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 온디바이스 AI 문장 생성을 쓸 수 있는지, 없다면 왜인지 (A-01).
///
/// 최소 지원 OS는 macOS 14이고 Foundation Models는 macOS 26부터다. 프레임워크를 약하게 링크해야
/// macOS 14~15에서 앱이 실행된다. 이 파일 밖에서 `FoundationModels`를 import하지 않는다.
///
/// AI를 못 쓰면 템플릿 문장으로 대체한다 (A-07). 판정과 수치는 AI가 만들지 않는다 (2장).
public enum NarratorAvailability: Sendable, Equatable {
    case available
    /// macOS 26 미만
    case unsupportedOS
    /// Apple Intelligence를 지원하지 않는 기기
    case deviceNotEligible
    /// Apple Intelligence가 꺼져 있다
    case appleIntelligenceNotEnabled
    /// 모델을 내려받는 중이다
    case modelNotReady
    /// 모델은 쓸 수 있지만 한국어를 지원하지 않는다 (요구사항 14장 검토 의견)
    case koreanNotSupported
    /// 알려지지 않은 사유
    case unavailable

    public static func current() -> NarratorAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return systemModelAvailability()
        }
        #endif
        return .unsupportedOS
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension NarratorAvailability {
    static func systemModelAvailability() -> NarratorAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "ko_KR")) ? .available : .koreanNotSupported
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable
            }
        }
    }
}
#endif

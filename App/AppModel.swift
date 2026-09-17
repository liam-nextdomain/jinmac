import AppKit
import Narrator
import Observation
import SwiftUI

/// 앱 전역 상태. 수집·저장·판정을 잇는 자리다.
///
/// 지금은 뼈대라 검진을 시작하지 않는다. UI 값은 메인 액터에서만 바뀐다.
@MainActor
@Observable
final class AppModel {

    /// AI 문장 생성을 쓸 수 있는지 (A-01). 실행할 때 한 번 확인한다.
    private(set) var narratorAvailability: NarratorAvailability = .current()

    @ObservationIgnored
    private let windows = WindowPresenter()

    /// 메뉴 첫 줄. 검진 경과일/목표일이 들어갈 자리 (F-60).
    var statusLine: String {
        String(localized: "검진을 시작하지 않았습니다")
    }

    var narratorStatusLine: String {
        switch narratorAvailability {
        case .available: String(localized: "AI 문장 생성: 사용 가능")
        case .unsupportedOS: String(localized: "AI 문장 생성: macOS 26 이상 필요")
        case .deviceNotEligible: String(localized: "AI 문장 생성: 지원하지 않는 기기")
        case .appleIntelligenceNotEnabled: String(localized: "AI 문장 생성: Apple Intelligence 꺼짐")
        case .modelNotReady: String(localized: "AI 문장 생성: 모델 준비 중")
        case .koreanNotSupported: String(localized: "AI 문장 생성: 한국어 미지원")
        case .unavailable: String(localized: "AI 문장 생성: 사용 불가")
        }
    }

    func showMainWindow() {
        windows.show(id: "main", title: "JinMac", size: CGSize(width: 640, height: 480)) {
            MainWindowView()
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

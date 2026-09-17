import SwiftUI

/// 메인 창. 온보딩 → 진행 → 리포트 → 리포트 목록 순서로 흐른다 (F-62).
struct MainWindowView: View {

    enum Screen: Hashable {
        /// 수집 항목 고지와 동의 (8장 프라이버시)
        case onboarding
        /// 경과일/목표일
        case progress
        case report
        case reportList
    }

    @State private var screen: Screen = .onboarding

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("아직 검진 기록이 없습니다")
                .font(.headline)
            Text("검진 기능은 준비 중입니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

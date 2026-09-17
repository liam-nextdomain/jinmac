import SwiftUI

/// JinMac: 지금 하는 작업을 이 맥이 잘 소화하고 있는지 측정해서 답하는 검진 앱.
///
/// 메뉴바 아이콘 하나로 상주한다 (F-60). Dock 아이콘은 없다 (`LSUIElement`).
/// 메뉴바에 실시간 그래프를 그리지 않는다 (F-61).
@main
struct JinMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(systemName: "stethoscope")
                .accessibilityLabel(Text("JinMac"))
        }
        .menuBarExtraStyle(.menu)
    }
}

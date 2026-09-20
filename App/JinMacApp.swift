import SwiftUI

/// 실행 진입점. 보통은 메뉴바 앱을 띄우고, `--probe-narrator`로 실행했을 때만 0단계 프로브를
/// 돌리고 끝낸다 (P0-PROBE-01).
///
/// `@main`을 `JinMacApp`에서 떼어 온 이유는, 프로브가 `NSApplication`이 올라오기 **전에**
/// 갈라져야 하기 때문이다. 앱이 뜬 뒤에 갈라지면 메뉴바 아이콘이 잠깐 나타났다 사라진다.
@main
enum JinMacMain {
    static func main() {
        if NarratorProbeCommand.requested {
            NarratorProbeCommand.runAndExit()
        }
        JinMacApp.main()
    }
}

/// JinMac: 지금 하는 작업을 이 맥이 잘 소화하고 있는지 측정해서 답하는 검진 앱.
///
/// 메뉴바 아이콘 하나로 상주한다 (F-60). Dock 아이콘은 없다 (`LSUIElement`).
/// 메뉴바에 실시간 그래프를 그리지 않는다 (F-61).
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

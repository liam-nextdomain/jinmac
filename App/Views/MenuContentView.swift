import SwiftUI

/// 메뉴바 아이콘을 클릭하면 나오는 메뉴 (F-60, F-63).
///
/// 아직 구현하지 않은 항목은 자리만 잡고 비활성으로 둔다.
struct MenuContentView: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)

        Divider()

        Button("검진 시작") {}
            .disabled(true)
        Button("세션 시작") {}
            .disabled(true)

        Divider()

        Button("리포트 열기…") { model.showMainWindow() }

        Divider()

        Text(model.narratorStatusLine)
        Button("설정…") {}
            .disabled(true)

        Divider()

        Button("JinMac 종료") { model.quit() }
            .keyboardShortcut("q")
    }
}

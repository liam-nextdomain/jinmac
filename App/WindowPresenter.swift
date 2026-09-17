import AppKit
import SwiftUI

/// 메인 창(온보딩·진행·리포트·리포트 목록)을 띄운다 (F-62).
///
/// SwiftUI의 `Window` 장면 대신 `NSWindow`를 직접 쓴다. Dock 아이콘이 없는 앱
/// (`LSUIElement`)은 창을 띄울 때 스스로 앞으로 나와야 하고, 첫 실행 온보딩은
/// 메뉴를 열기 **전에** 떠야 하는데 `openWindow`는 뷰 안에서만 부를 수 있기 때문이다.
@MainActor
final class WindowPresenter {

    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    /// 같은 `id`로 다시 부르면 이미 떠 있는 창을 앞으로 가져온다.
    func show<Content: View>(id: String,
                             title: String,
                             size: CGSize,
                             @ViewBuilder content: () -> Content) {
        if let existing = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        window.isReleasedWhenClosed = false
        window.center()

        // 창이 닫히면 참조를 놓아 준다. 안 그러면 계속 쌓인다.
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget(id: id) }
        }

        windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(id: String) {
        windows[id]?.close()
        forget(id: id)
    }

    private func forget(id: String) {
        windows[id] = nil
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

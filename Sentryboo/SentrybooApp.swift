import SwiftUI
import AppKit

@main
struct SentrybooApp: App {
    @StateObject private var session = AlertSession()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(session)
        } label: {
            MenuBarLabel(status: session.status, problemCount: session.problems.count)
        }
        .menuBarExtraStyle(.window)

        Window("设置", id: "settings") {
            SettingsView()
                .environmentObject(session)
                .frame(minWidth: 420, minHeight: 360)
                .background(SettingsWindowBootstrap())
        }
        .defaultSize(width: 460, height: 420)
    }
}

/// 确保设置窗在菜单栏应用中真正成为前台键盘窗口。
private struct SettingsWindowBootstrap: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct MenuBarLabel: View {
    let status: SourceStatus
    let problemCount: Int

    var body: some View {
        switch status {
        case .ok:
            if problemCount > 0 {
                Text("⚠️\(problemCount)")
            } else {
                Text("◎")
            }
        case .error:
            Text("⚠️")
        case .syncing:
            Text("↻")
        case .idle:
            Text("◎")
        }
    }
}

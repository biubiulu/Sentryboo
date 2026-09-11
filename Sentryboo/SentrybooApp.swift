import SwiftUI
import AppKit

@main
struct SentrybooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏图标改由 AppKit NSStatusItem 接管（MenuBarExtra 会强制 template → 透明/发黑）。
        // 这里保留 Settings 场景，供系统「设置」菜单与程序化打开。
        Settings {
            SettingsView()
                .environmentObject(appDelegate.session)
                .frame(minWidth: 520, minHeight: 560)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let session = AlertSession()
    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var policyTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        ProcessInfo.processInfo.disableAutomaticTermination("Sentryboo menu bar keepalive")
        applyPreferredPolicy()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(session: session)
        applyPreferredPolicy()
        policyTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyPreferredPolicy()
            }
        }
        if let policyTimer {
            RunLoop.main.add(policyTimer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        policyTimer?.invalidate()
        policyTimer = nil
        menuBarController = nil
        ProcessInfo.processInfo.enableAutomaticTermination("Sentryboo menu bar keepalive")
    }

    func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // 优先走 SwiftUI Settings 场景（系统偏好样式）。
        let settingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.sendAction(settingsSelector, to: nil, from: nil) {
            return
        }

        // 兜底：自建 NSWindow，避免 openWindow 在弹层里静默失败。
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(session)
                    .frame(minWidth: 520, minHeight: 560)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "设置"
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 540, height: 620))
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// macOS 26：状态栏图标被系统隐藏时，accessory 应用会被 Automatic Termination 收掉。
    private func applyPreferredPolicy() {
        clearHiddenStatusItemFlagsIfNeeded()
        let policy: NSApplication.ActivationPolicy =
            Self.menuBarItemHiddenBySystem ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private static var menuBarItemHiddenBySystem: Bool {
        let defaults = UserDefaults.standard
        return defaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix("NSStatusItem Visible")
                && (defaults.object(forKey: key) as? NSNumber)?.boolValue == false
        }
    }

    private func clearHiddenStatusItemFlagsIfNeeded() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSStatusItem Visible") {
            if (defaults.object(forKey: key) as? NSNumber)?.boolValue == false {
                defaults.set(true, forKey: key)
            }
        }
    }
}

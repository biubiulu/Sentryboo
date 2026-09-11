import AppKit
import SwiftUI
import Combine

/// 用原生 NSStatusItem + 自定义视图画彩色呼吸灯。
/// 不用 MenuBarExtra label：系统会强制 template → 透明/发黑。
@MainActor
final class MenuBarController: NSObject {
    private let session: AlertSession
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let dotView: StatusDotView
    private var cancellables = Set<AnyCancellable>()

    init(session: AlertSession) {
        self.session = session
        self.statusItem = NSStatusBar.system.statusItem(withLength: 18)
        self.dotView = StatusDotView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        super.init()

        configureStatusItem()
        configurePopover()
        bindSession()
        applyIndicator()
    }

    deinit {
        // statusItem 由系统持有；应用退出时一并释放即可。
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        statusItem.button?.title = ""
        statusItem.button?.image = nil
        statusItem.button?.appearsDisabled = false
        statusItem.length = 18

        // 自定义视图挂在 button 上，颜色不会被 template 化。
        if let button = statusItem.button {
            button.wantsLayer = true
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.addSubview(dotView)
            dotView.frame = button.bounds
            dotView.autoresizingMask = [.width, .height]
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        rebuildPopoverContent()
    }

    private func rebuildPopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(session)
        )
    }

    private func bindSession() {
        session.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyIndicator()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sentrybooOpenSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closePopover()
            }
            .store(in: &cancellables)
    }

    private func applyIndicator() {
        let next = indicator
        statusItem.button?.toolTip = next.label
        dotView.configure(color: next.color, breathing: next.breathing)
    }

    private var indicator: (color: NSColor, breathing: Bool, label: String) {
        let hasAccounts = !session.accounts.isEmpty
        let hasDisaster = session.problems.contains { $0.severity == .disaster }
        switch session.status {
        case .error:
            return (NSColor.systemRed, false, "连接异常")
        case .idle where !hasAccounts:
            return (NSColor.systemRed, false, "连接异常")
        case .ok, .partial, .syncing, .idle:
            if hasDisaster {
                return (NSColor.systemRed, true, "存在灾难级告警")
            }
            return (NSColor.systemGreen, true, "运行正常")
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            rebuildPopoverContent()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            Task { await session.refresh(reason: .appActivated) }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }
}

/// 自绘圆点 + Timer 呼吸；完全绕开 template 渲染。
final class StatusDotView: NSView {
    private var color: NSColor = .systemGreen
    private var breathing = false
    private var timer: Timer?
    private var startedAt = Date()
    private let period: TimeInterval = 1.4
    private var phaseOpacity: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        timer?.invalidate()
    }

    override var isOpaque: Bool { false }

    func configure(color: NSColor, breathing: Bool) {
        let colorChanged = !self.color.isEqual(color)
        let breathingChanged = self.breathing != breathing
        self.color = color
        self.breathing = breathing

        if breathing {
            if timer == nil || breathingChanged || colorChanged {
                startBreathing()
            }
        } else {
            stopBreathing()
            phaseOpacity = 1
            needsDisplay = true
        }
    }

    private func startBreathing() {
        timer?.invalidate()
        startedAt = Date()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let phase = Date().timeIntervalSince(self.startedAt)
                .truncatingRemainder(dividingBy: self.period) / self.period
            self.phaseOpacity = CGFloat(0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2 * .pi)))
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        needsDisplay = true
    }

    private func stopBreathing() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let diameter = min(bounds.width, bounds.height) * 0.45
        let rect = NSRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        color.withAlphaComponent(phaseOpacity).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    // 点击交给外层 button，不拦截事件。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension Notification.Name {
    static let sentrybooOpenSettings = Notification.Name("sentrybooOpenSettings")
}

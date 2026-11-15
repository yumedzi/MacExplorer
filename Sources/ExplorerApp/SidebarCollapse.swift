import AppKit

/// Click the sidebar divider to collapse it. Hover the leading edge to restore the last width.
@MainActor
final class SidebarCollapseController {
    static let minimumOpenWidth: CGFloat = 165
    static let maximumWidth: CGFloat = 300
    static let defaultWidth: CGFloat = 210

    private let reveal = SidebarRevealStrip()
    private weak var split: ExplorerSplitView?
    private var collapsed: Bool
    private var savedWidth: CGFloat
    private var adjusting = false
    private var positioned = false
    private nonisolated(unsafe) var preferenceObserver: NSObjectProtocol?

    var isCollapsed: Bool { collapsed }

    init() {
        collapsed = AppPreferences.shared.sidebarCollapsed
        savedWidth = CGFloat(AppPreferences.shared.sidebarWidth)
    }

    func install(in host: NSView, split: ExplorerSplitView) {
        self.split = split
        split.collapsesOnDividerClick = true
        split.onDividerClick = { [weak self] in self?.close() }
        reveal.translatesAutoresizingMaskIntoConstraints = false
        reveal.isHidden = !collapsed
        reveal.onHover = { [weak self] in self?.open() }
        host.addSubview(reveal)
        NSLayoutConstraint.activate([
            reveal.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            reveal.topAnchor.constraint(equalTo: split.topAnchor),
            reveal.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            reveal.widthAnchor.constraint(equalToConstant: 6)
        ])
        preferenceObserver = NotificationCenter.default.addObserver(forName: AppPreferences.changed, object: AppPreferences.shared, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyFromPreferences() }
        }
    }

    func restorePosition() {
        guard split != nil else { return }
        positioned = true
        applyPosition(collapsed ? 0 : savedWidth)
        reveal.isHidden = !collapsed
    }

    func noteResize(of split: NSSplitView) {
        guard positioned, !adjusting, split === self.split, let pane = split.arrangedSubviews.first else { return }
        let width = pane.frame.width
        if width < Self.minimumOpenWidth - 1 {
            guard !collapsed else { reveal.isHidden = false; return }
            collapsed = true
            reveal.isHidden = false
            writePreferences()
        } else {
            let clamped = min(Self.maximumWidth, max(Self.minimumOpenWidth, width))
            let changed = collapsed || abs(savedWidth - clamped) > 0.5
            collapsed = false
            savedWidth = clamped
            reveal.isHidden = true
            if changed { writePreferences() }
        }
    }

    func close() {
        guard let split, !collapsed else { return }
        let width = split.arrangedSubviews[0].frame.width
        if width >= Self.minimumOpenWidth { savedWidth = min(Self.maximumWidth, width) }
        collapsed = true
        writePreferences()
        applyPosition(0)
        reveal.isHidden = false
    }

    func open() {
        guard collapsed else { return }
        collapsed = false
        writePreferences()
        applyPosition(savedWidth)
        reveal.isHidden = true
    }

    private func applyPosition(_ position: CGFloat) {
        guard let split else { return }
        adjusting = true
        split.setPosition(position, ofDividerAt: 0)
        adjusting = false
    }

    private func applyFromPreferences() {
        let preferences = AppPreferences.shared
        let nextCollapsed = preferences.sidebarCollapsed
        let nextWidth = CGFloat(preferences.sidebarWidth)
        guard nextCollapsed != collapsed || abs(nextWidth - savedWidth) > 0.5 else { return }
        collapsed = nextCollapsed
        savedWidth = nextWidth
        guard positioned else { return }
        applyPosition(collapsed ? 0 : savedWidth)
        reveal.isHidden = !collapsed
    }

    private func writePreferences() {
        let preferences = AppPreferences.shared
        preferences.sidebarCollapsed = collapsed
        preferences.sidebarWidth = Double(savedWidth)
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }
}

@MainActor
private final class SidebarRevealStrip: NSView {
    var onHover: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var hoverTask: Task<Void, Never>?
    private var hovering = false

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.onHover?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
        hoverTask?.cancel()
        hoverTask = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            bounds.fill()
        }
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        Palette.line.setFill()
        NSRect(x: 0, y: 0, width: pixel, height: bounds.height).fill()
    }

    override var isFlipped: Bool { true }
}

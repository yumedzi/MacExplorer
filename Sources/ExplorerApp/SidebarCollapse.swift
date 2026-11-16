import AppKit

/// Click the sidebar divider to collapse it. The same hover line marks the open divider and the collapsed edge.
@MainActor
final class SidebarCollapseController {
    static let minimumOpenWidth: CGFloat = 165
    static let maximumWidth: CGFloat = 300
    static let defaultWidth: CGFloat = 210

    private let reveal = SidebarRevealStrip()
    private var revealLeading: NSLayoutConstraint!
    private weak var split: ExplorerSplitView?
    private var collapsed: Bool
    private var savedWidth: CGFloat
    private var dragOrigin: CGFloat = 0
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
        reveal.onClick = { [weak self] in
            guard let self else { return }
            if self.collapsed { self.open() } else { self.close() }
        }
        reveal.onDragBegan = { [weak self] in self?.beginDividerDrag() }
        reveal.onDrag = { [weak self] delta in self?.dragDivider(by: delta) }
        host.addSubview(reveal)
        revealLeading = reveal.leadingAnchor.constraint(equalTo: split.leadingAnchor)
        NSLayoutConstraint.activate([
            revealLeading,
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
        placeReveal()
    }

    func noteResize(of split: NSSplitView) {
        guard positioned, !adjusting, split === self.split, let pane = split.arrangedSubviews.first else { return }
        let width = pane.frame.width
        if width < Self.minimumOpenWidth - 1 {
            if !collapsed {
                collapsed = true
                writePreferences()
            }
        } else {
            let clamped = min(Self.maximumWidth, max(Self.minimumOpenWidth, width))
            let changed = collapsed || abs(savedWidth - clamped) > 0.5
            collapsed = false
            savedWidth = clamped
            if changed { writePreferences() }
        }
        placeReveal()
    }

    func close() {
        guard let split, !collapsed else { return }
        let width = split.arrangedSubviews[0].frame.width
        if width >= Self.minimumOpenWidth { savedWidth = min(Self.maximumWidth, width) }
        collapsed = true
        writePreferences()
        applyPosition(0)
        placeReveal()
    }

    func open() {
        guard collapsed else { return }
        collapsed = false
        writePreferences()
        applyPosition(savedWidth)
        placeReveal()
    }

    private func beginDividerDrag() {
        guard !collapsed, let pane = split?.arrangedSubviews.first else { return }
        dragOrigin = pane.frame.maxX
    }

    private func dragDivider(by delta: CGFloat) {
        guard !collapsed else { return }
        split?.setPosition(dragOrigin + delta, ofDividerAt: 0)
    }

    private func placeReveal() {
        guard let pane = split?.arrangedSubviews.first else { return }
        let atEdge = pane.frame.width < Self.minimumOpenWidth - 1
        revealLeading.constant = atEdge ? 0 : pane.frame.maxX
        reveal.usesResizeCursor = !atEdge
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
        placeReveal()
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
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var usesResizeCursor = false { didSet { if usesResizeCursor != oldValue { window?.invalidateCursorRects(for: self) } } }
    private var tracking: NSTrackingArea?
    private var hovering = false

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: usesResizeCursor ? .resizeLeftRight : .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        var dragged = false
        var began = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 { dragged = true }
            if dragged {
                if !began { began = true; onDragBegan?() }
                onDrag?(next.locationInWindow.x - start.x)
            }
        }
        if !dragged { onClick?() }
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

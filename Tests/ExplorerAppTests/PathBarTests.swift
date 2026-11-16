import AppKit
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct PathBarTests {
    private func bar() -> (NSWindow, PathBar, NSButton, NSTextField, NSStackView) {
        _ = NSApplication.shared
        let bar = PathBar(frame: NSRect(x: 0, y: 0, width: 520, height: 34))
        let host = NSView(frame: bar.frame)
        host.addSubview(bar)
        bar.update(URL(fileURLWithPath: "/Users/viktor/docs/godot/ZRS2"))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let edit = bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == "Edit folder path (⌘L)" }!
        let field = bar.subviews.compactMap { $0 as? NSTextField }.first!
        let crumbs = bar.subviews.compactMap { $0 as? NSStackView }.first!
        return (window, bar, edit, field, crumbs)
    }

    @Test func pencilClickIsNotClaimedByTheDoubleClickGesture() {
        let (window, bar, edit, _, _) = bar()
        defer { window.close() }
        let recognizer = bar.gestureRecognizers[0]
        let onPencil = mouse(at: edit.convert(NSPoint(x: edit.bounds.midX, y: edit.bounds.midY), to: nil), window: window)
        #expect(bar.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: onPencil) == false)
        let onBackground = mouse(at: bar.convert(NSPoint(x: 8, y: 1), to: nil), window: window)
        #expect(bar.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: onBackground) == true)
        let local = edit.convert(NSPoint(x: edit.bounds.midX, y: edit.bounds.midY), to: bar.superview)
        #expect(bar.hitTest(local) === edit)
    }

    @Test func openingClickDoesNotImmediatelyCloseThePathField() async {
        let (window, bar, edit, field, crumbs) = bar()
        defer { window.close() }
        edit.performClick(nil)
        #expect(field.isHidden == false)
        #expect(crumbs.isHidden == true)
        #expect(field.stringValue == "/Users/viktor/docs/godot/ZRS2")
        bar.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
        bar.update(URL(fileURLWithPath: "/tmp"))
        #expect(field.isHidden == false)
        #expect(crumbs.isHidden == true)
        #expect(field.stringValue == "/Users/viktor/docs/godot/ZRS2")
        await Task.yield()
        await Task.yield()
        window.makeFirstResponder(nil)
        #expect(field.isHidden == true)
        #expect(crumbs.isHidden == false)
    }

    private func mouse(at location: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
}

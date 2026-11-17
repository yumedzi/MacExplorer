import AppKit
import Testing
@testable import ExplorerApp

@Suite @MainActor
struct ColumnHeaderTests {
    private func pixels(ascending: Bool?) -> [UInt8] {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 180, height: 80))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        let header = AlignedHeaderCell(textCell: "Name")
        header.font = .systemFont(ofSize: 11)
        column.headerCell = header
        column.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        table.addTableColumn(column)
        if let ascending {
            table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: ascending)]
        }
        let headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        headerView.tableView = table
        let bounds = NSRect(x: 0, y: 0, width: 120, height: 24)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        bounds.fill()
        header.drawInterior(withFrame: bounds, in: headerView)
        NSGraphicsContext.restoreGraphicsState()
        return Array(UnsafeBufferPointer(start: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    @Test func sortedColumnDrawsADirectionIndicator() {
        let plain = pixels(ascending: nil)
        let up = pixels(ascending: true)
        let down = pixels(ascending: false)
        #expect(plain != up)
        #expect(up != down)
    }
}

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
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor.black.setFill()
        bounds.fill()
        header.drawInterior(withFrame: bounds, in: headerView)
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: image.size)
        let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        return [UInt8](cg.dataProvider!.data! as Data)
    }

    @Test func sortedColumnDrawsADirectionIndicator() {
        let plain = pixels(ascending: nil)
        let up = pixels(ascending: true)
        let down = pixels(ascending: false)
        #expect(plain != up)
        #expect(up != down)
    }
}

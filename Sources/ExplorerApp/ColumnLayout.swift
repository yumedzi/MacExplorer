import AppKit

/// Header titles use the same left inset as the text in the cells under them.
/// NSTableHeaderCell draws its title from a private rect, so titleRect changes never show up.
final class AlignedHeaderCell: NSTableHeaderCell {
    var textInset: CGFloat = 9
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ]
        var rect = cellFrame
        if alignment == .right {
            rect.size.width = max(0, rect.width - 12)
        } else {
            rect.origin.x += textInset
            rect.size.width = max(0, rect.width - textInset - 4)
        }
        let title = stringValue as NSString
        let height = title.size(withAttributes: attributes).height
        title.draw(in: NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height), withAttributes: attributes)
    }
}

struct DetailColumnLayout: Codable, Equatable {
    var order: [String]
    var hidden: [String]
    var widths: [String: Double]

    static let knownOrder = ["name", "modified", "kind", "size", "location", "created"]
    static let standard = DetailColumnLayout(
        order: knownOrder,
        hidden: ["created"],
        widths: ["name": 385, "modified": 185, "kind": 140, "size": 85, "location": 180, "created": 185]
    )

    func sanitized() -> DetailColumnLayout {
        let known = Set(Self.knownOrder)
        var order: [String] = []
        for id in self.order where known.contains(id) && !order.contains(id) { order.append(id) }
        for id in Self.knownOrder where !order.contains(id) { order.append(id) }
        let hidden = hidden.filter { known.contains($0) && $0 != "name" }
        var widths = Self.standard.widths
        for (id, width) in self.widths where known.contains(id) && width.isFinite {
            let minimum: Double = id == "name" ? 160 : 60
            widths[id] = min(2000, max(minimum, width))
        }
        return DetailColumnLayout(order: order, hidden: hidden, widths: widths)
    }
}

@MainActor
enum ColumnLayout {
    private static var applyingDepth = 0
    private static let titles = [
        "name": "Name", "modified": "Date modified", "kind": "Type",
        "size": "Size", "created": "Date created", "location": "Folder"
    ]
    private static let menuOrder = ["name", "modified", "kind", "size", "created", "location"]

    static func apply(to table: NSTableView, content: Bool, showsLocation: Bool) {
        let layout = AppPreferences.shared.detailColumns
        applyingDepth += 1
        defer { applyingDepth -= 1 }
        if !content {
            for (target, id) in layout.order.enumerated() {
                let current = table.column(withIdentifier: NSUserInterfaceItemIdentifier(id))
                guard current >= 0, current != target else { continue }
                table.moveColumn(current, toColumn: target)
            }
            for column in table.tableColumns {
                let id = column.identifier.rawValue
                guard let width = layout.widths[id], abs(column.width - CGFloat(width)) > 0.5 else { continue }
                column.width = CGFloat(width)
            }
        }
        for column in table.tableColumns {
            let id = column.identifier.rawValue
            switch id {
            case "name": column.isHidden = false
            case "location": column.isHidden = content || !showsLocation || layout.hidden.contains(id)
            default: column.isHidden = content || layout.hidden.contains(id)
            }
        }
        if !content { fillFlexibleColumn(table) }
    }

    static func performWithoutSaving(_ body: () -> Void) {
        applyingDepth += 1
        body()
        applyingDepth -= 1
    }

    static func save(from table: NSTableView) {
        guard applyingDepth == 0 else { return }
        var layout = AppPreferences.shared.detailColumns
        layout.order = table.tableColumns.map(\.identifier.rawValue)
        for column in table.tableColumns {
            layout.widths[column.identifier.rawValue] = Double(column.width)
        }
        AppPreferences.shared.detailColumns = layout
    }

    static func populate(_ menu: NSMenu, showsLocation: Bool, target: AnyObject) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let hidden = Set(AppPreferences.shared.detailColumns.hidden)
        for id in menuOrder where id != "location" || showsLocation {
            guard let title = titles[id] else { continue }
            let item = NSMenuItem(title: title, action: #selector(ColumnHeaderMenu.toggleColumn(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = id
            item.state = (id == "name" || !hidden.contains(id)) ? .on : .off
            item.isEnabled = id != "name"
            menu.addItem(item)
        }
    }

    private static func fillFlexibleColumn(_ table: NSTableView) {
        guard table.frame.width > 1, let flexible = table.tableColumns.first(where: { !$0.isHidden }) else { return }
        let others = table.tableColumns.reduce(CGFloat(0)) { sum, column in
            column === flexible || column.isHidden ? sum : sum + column.width
        }
        let available = max(flexible.minWidth, table.frame.width - others)
        if abs(flexible.width - available) > 0.5 { flexible.width = available }
    }
}

@MainActor
final class ColumnHeaderMenu: NSObject, NSMenuDelegate {
    weak var browser: BrowserViewController?
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let browser else { return }
        ColumnLayout.populate(menu, showsLocation: browser.tab.isRecursiveSearch, target: self)
    }
    @objc func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        browser?.toggleDetailColumn(id)
    }
}

extension BrowserViewController {
    func toggleDetailColumn(_ identifier: String) {
        guard identifier != "name" else { return }
        var layout = AppPreferences.shared.detailColumns
        if let index = layout.hidden.firstIndex(of: identifier) { layout.hidden.remove(at: index) }
        else { layout.hidden.append(identifier) }
        AppPreferences.shared.detailColumns = layout
        configureTablePresentation()
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        guard viewMode == .details else { return }
        ColumnLayout.save(from: table)
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard viewMode == .details else { return }
        ColumnLayout.save(from: table)
    }
}

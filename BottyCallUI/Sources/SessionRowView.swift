import AppKit

extension NSPasteboard.PasteboardType {
    static let sessionDrag = NSPasteboard.PasteboardType("com.bottycall.session-drag")
}

class SessionRowView: NSView {
    private let selectorLabel = NSTextField(labelWithString: " ")
    private let iconLabel = NSTextField(labelWithString: "")
    private let slugLabel = NSTextField(labelWithString: "")
    private let tokenLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    var session: Session?
    var onClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?

    static let rowHeight: CGFloat = 28
    static let leadingPad: CGFloat = 10
    static let trailingPad: CGFloat = 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        let mono12 = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        selectorLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        selectorLabel.textColor = .clear
        selectorLabel.isBezeled = false
        selectorLabel.drawsBackground = false
        selectorLabel.isEditable = false
        selectorLabel.isSelectable = false
        selectorLabel.setContentHuggingPriority(.required, for: .horizontal)

        iconLabel.font = mono12
        iconLabel.isBezeled = false
        iconLabel.drawsBackground = false
        iconLabel.isEditable = false
        iconLabel.isSelectable = false
        iconLabel.setContentHuggingPriority(.required, for: .horizontal)

        slugLabel.font = mono12
        slugLabel.textColor = NSColor(white: 0.80, alpha: 1)
        slugLabel.lineBreakMode = .byTruncatingTail
        slugLabel.maximumNumberOfLines = 1
        slugLabel.cell?.truncatesLastVisibleLine = true
        slugLabel.isBezeled = false
        slugLabel.drawsBackground = false
        slugLabel.isEditable = false
        slugLabel.isSelectable = false
        slugLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tokenLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        tokenLabel.textColor = NSColor(white: 0.35, alpha: 1)
        tokenLabel.alignment = .right
        tokenLabel.isBezeled = false
        tokenLabel.drawsBackground = false
        tokenLabel.isEditable = false
        tokenLabel.isSelectable = false
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        timeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = NSColor(white: 0.45, alpha: 1)
        timeLabel.alignment = .right
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        for v in [selectorLabel, iconLabel, slugLabel, tokenLabel, timeLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            selectorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingPad),
            selectorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            selectorLabel.widthAnchor.constraint(equalToConstant: 12),

            iconLabel.leadingAnchor.constraint(equalTo: selectorLabel.trailingAnchor, constant: 2),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 14),

            slugLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 4),
            slugLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            slugLabel.trailingAnchor.constraint(lessThanOrEqualTo: tokenLabel.leadingAnchor, constant: -6),

            tokenLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -6),
            tokenLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingPad),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    func applyExpanded(_ expanded: Bool) {
        let main: CGFloat = expanded ? 14 : 12
        let time: CGFloat = expanded ? 13 : 11
        selectorLabel.font = .monospacedSystemFont(ofSize: main, weight: .bold)
        iconLabel.font     = .monospacedSystemFont(ofSize: main, weight: .regular)
        slugLabel.font     = .monospacedSystemFont(ofSize: main, weight: .regular)
        timeLabel.font     = .monospacedSystemFont(ofSize: time,  weight: .regular)
    }

    func configure(with session: Session, label: String? = nil, depth: Int = 0) {
        self.session = session
        let color = statusColor(session.status)
        iconLabel.stringValue = session.status.icon
        iconLabel.textColor = color
        slugLabel.stringValue = label ?? session.slug
        tokenLabel.stringValue = formatTokens(session.totalTokens)
        timeLabel.stringValue = relativeTime(from: session.last_activity)
        setSelected(false)
    }

    func updateTime(for session: Session) {
        tokenLabel.stringValue = formatTokens(session.totalTokens)
        timeLabel.stringValue = relativeTime(from: session.last_activity)
    }

    func setSelected(_ selected: Bool) {
        if selected {
            selectorLabel.stringValue = ">"
            selectorLabel.textColor = NSColor(red: 0.337, green: 0.718, blue: 0.337, alpha: 1)
            slugLabel.textColor = .white
        } else {
            selectorLabel.stringValue = " "
            selectorLabel.textColor = .clear
            slugLabel.textColor = NSColor(white: 0.80, alpha: 1)
        }
    }

    func setDropHighlight(_ highlighted: Bool) {
        if highlighted {
            layer?.backgroundColor = NSColor(red: 0.15, green: 0.2, blue: 0.35, alpha: 1).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = nil
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    private func statusColor(_ status: Status) -> NSColor {
        switch status {
        case .Working: NSColor(red: 0.820, green: 0.620, blue: 0.118, alpha: 1)
        case .Attention: .systemRed
        case .Idle: NSColor(red: 0.337, green: 0.718, blue: 0.337, alpha: 1)
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        var v: NSView? = superview
        while let parent = v {
            if parent is SidebarView {
                window?.makeFirstResponder(parent)
                break
            }
            v = parent.superview
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session = session, let downEvent = mouseDownEvent else { return }

        let start = convert(downEvent.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard dx * dx + dy * dy > 16 else { return }

        mouseDownEvent = nil

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(session.session_id, forType: .sessionDrag)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragImage())

        alphaValue = 0.4
        beginDraggingSession(with: [draggingItem], event: downEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if layer?.borderWidth == 0 {
            layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if layer?.borderWidth == 0 {
            layer?.backgroundColor = nil
        }
    }

    private func dragImage() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

extension SessionRowView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1.0
    }
}

import AppKit

extension NSPasteboard.PasteboardType {
    static let sessionDrag = NSPasteboard.PasteboardType("com.bottycall.session-drag")
}

class SessionRowView: NSView {
    private let selectorLabel = NSTextField(labelWithString: " ")
    private let iconLabel = NSTextField(labelWithString: "")
    private let slugLabel = NSTextField(labelWithString: "")
    private let tokenLabel = NSTextField(labelWithString: "")

    var session: Session?
    var onClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var displayedTokens: Double = 0
    private var targetTokens: Int = 0
    private var tokensPerFrame: Double = 0
    private var colorBrightness: Double = 0.50
    private var animTimer: Timer?

    private static let normalBrightness: Double = 0.50
    private static let activeBrightness: Double = 1.0
    // Fade back to normal over ~0.8s at 60fps
    private static let fadeSpeed: Double = (activeBrightness - normalBrightness) / (0.8 * 60)

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
        tokenLabel.textColor = NSColor(white: 0.50, alpha: 1)
        tokenLabel.alignment = .right
        tokenLabel.isBezeled = false
        tokenLabel.drawsBackground = false
        tokenLabel.isEditable = false
        tokenLabel.isSelectable = false
        tokenLabel.setContentHuggingPriority(.required, for: .horizontal)
        tokenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        for v in [selectorLabel, iconLabel, slugLabel, tokenLabel] {
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

            tokenLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.trailingPad),
            tokenLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
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
        selectorLabel.font = .monospacedSystemFont(ofSize: main, weight: .bold)
        iconLabel.font     = .monospacedSystemFont(ofSize: main, weight: .regular)
        slugLabel.font     = .monospacedSystemFont(ofSize: main, weight: .regular)
    }

    func configure(with session: Session, label: String? = nil, depth: Int = 0) {
        let isSameSession = self.session?.session_id == session.session_id
        self.session = session

        let color = statusColor(session.status)
        iconLabel.stringValue = session.status.icon
        iconLabel.textColor = color
        slugLabel.stringValue = label ?? session.slug

        if isSameSession {
            updateTime(for: session)
        } else {
            animTimer?.invalidate()
            animTimer = nil
            displayedTokens = Double(session.totalTokens)
            targetTokens = session.totalTokens
            colorBrightness = Self.normalBrightness
            tokenLabel.textColor = NSColor(white: Self.normalBrightness, alpha: 1)
            tokenLabel.stringValue = formatTokens(session.totalTokens)
        }

        setSelected(false)
    }

    func updateTime(for session: Session) {
        let newTokens = session.totalTokens
        if newTokens > targetTokens {
            let diff = Double(newTokens) - displayedTokens
            // Target ~1.8s to count through the full jump at 60fps
            tokensPerFrame = max(1, diff / (1.8 * 60))
            targetTokens = newTokens
            colorBrightness = Self.activeBrightness
            tokenLabel.textColor = NSColor(white: Self.activeBrightness, alpha: 1)
            startTokenAnimation()
        } else if newTokens != targetTokens {
            // Tokens decreased or reset — snap immediately
            displayedTokens = Double(newTokens)
            targetTokens = newTokens
            tokenLabel.stringValue = formatTokens(newTokens)
        }
    }

    private func startTokenAnimation() {
        animTimer?.invalidate()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if self.displayedTokens < Double(self.targetTokens) {
                self.displayedTokens = min(self.displayedTokens + self.tokensPerFrame, Double(self.targetTokens))
                self.tokenLabel.stringValue = formatTokens(Int(self.displayedTokens.rounded()))
            } else {
                // Counting done — fade color back to normal
                self.colorBrightness = max(Self.normalBrightness, self.colorBrightness - Self.fadeSpeed)
                self.tokenLabel.textColor = NSColor(white: self.colorBrightness, alpha: 1)
                if self.colorBrightness <= Self.normalBrightness {
                    timer.invalidate()
                    self.animTimer = nil
                }
            }
        }
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

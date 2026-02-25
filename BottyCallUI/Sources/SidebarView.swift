import AppKit

class SidebarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "BottyCall")
    private let subtitleLabel = NSTextField(labelWithString: "Sessions")
    private let topSeparator = NSView()
    private let columnHeader = ColumnHeaderView()
    private let scrollView = NSScrollView()
    private let contentView = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "No sessions")
    private let leftBorder = NSView()

    private var rowViews: [SessionRowView] = []
    private var sessions: [Session] = []
    private var refreshTimer: Timer?
    private var selectedIndex: Int?

    var onSessionClick: ((Session) -> Void)?
    var onSessionDrop: ((_ source: Session, _ target: Session) -> Bool)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onHide: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
    }

    @objc private func windowDidBecomeKey() {
        window?.makeFirstResponder(self)
    }

    @objc private func windowDidResignKey() {
        clearSelection()
    }

    private func setup() {
        wantsLayer = true
        registerForDraggedTypes([.sessionDrag])

        let green = NSColor(red: 0.337, green: 0.718, blue: 0.337, alpha: 1)

        titleLabel.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = green
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false

        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.28, alpha: 1)
        subtitleLabel.alignment = .right
        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false

        topSeparator.wantsLayer = true
        topSeparator.layer?.backgroundColor = NSColor(white: 0.28, alpha: 1).cgColor

        emptyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = NSColor(white: 0.30, alpha: 1)
        emptyLabel.alignment = .center
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isHidden = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = contentView

        leftBorder.wantsLayer = true
        leftBorder.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor

        for v in [titleLabel, subtitleLabel, topSeparator, columnHeader,
                  scrollView, emptyLabel, leftBorder] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            leftBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftBorder.topAnchor.constraint(equalTo: topAnchor),
            leftBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftBorder.widthAnchor.constraint(equalToConstant: 1),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            subtitleLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            topSeparator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1),

            columnHeader.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: 5),
            columnHeader.leadingAnchor.constraint(equalTo: leadingAnchor),
            columnHeader.trailingAnchor.constraint(equalTo: trailingAnchor),
            columnHeader.heightAnchor.constraint(equalToConstant: 18),

            scrollView.topAnchor.constraint(equalTo: columnHeader.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshTimes()
        }
    }

    func update(groups: [SessionGroup]) {
        let selectedId = selectedIndex.flatMap {
            $0 < sessions.count ? sessions[$0].session_id : nil
        }

        contentView.subviews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        sessions = groups.flatMap { $0.entries.map { $0.session } }

        emptyLabel.isHidden = !sessions.isEmpty

        var y: CGFloat = 0
        let width = scrollView.contentSize.width
        let showHeaders = groups.count > 1 || (groups.count == 1 && groups[0].repoPath != nil)

        for (groupIdx, group) in groups.enumerated() {
            if showHeaders {
                if groupIdx > 0 { y += 6 }
                let header = SectionHeaderView(frame: NSRect(x: 0, y: y, width: width, height: SectionHeaderView.headerHeight))
                header.autoresizingMask = [.width]
                header.configure(name: group.name)
                contentView.addSubview(header)
                y += SectionHeaderView.headerHeight
            }

            for entry in group.entries {
                let row = SessionRowView(frame: NSRect(x: 0, y: y, width: width, height: SessionRowView.rowHeight))
                row.autoresizingMask = [.width]
                let label = (group.repoPath != nil ? entry.session.git_branch : nil) ?? entry.session.slug
                row.configure(with: entry.session, label: label, depth: entry.depth)

                let s = entry.session
                row.onClick = { [weak self] in self?.onSessionClick?(s) }

                contentView.addSubview(row)
                rowViews.append(row)
                y += SessionRowView.rowHeight
            }
        }

        contentView.frame = NSRect(
            x: 0, y: 0,
            width: scrollView.contentSize.width,
            height: max(y, scrollView.contentSize.height)
        )

        selectedIndex = nil
        if let savedId = selectedId,
           let newIdx = sessions.firstIndex(where: { $0.session_id == savedId }) {
            selectedIndex = newIdx
            rowViews[newIdx].setSelected(true)
        }

        let topFixed: CGFloat = 10 + titleLabel.intrinsicContentSize.height + 8 + 1 + 5 + 18 + 2
        let idealHeight = topFixed + max(y, 70)
        onHeightChange?(idealHeight)
    }

    func setConnected(_ connected: Bool) {
        if !connected && sessions.isEmpty {
            subtitleLabel.stringValue = "connecting"
            subtitleLabel.textColor = NSColor(white: 0.38, alpha: 1)
        } else {
            subtitleLabel.stringValue = "Sessions"
            subtitleLabel.textColor = NSColor(white: 0.28, alpha: 1)
        }
    }

    private func refreshTimes() {
        for (i, row) in rowViews.enumerated() where i < sessions.count {
            row.updateTime(for: sessions[i])
        }
    }

    // MARK: - Focus selection

    /// Selects the highest-priority session: Attention → Idle → Working.
    func selectBestSession() {
        guard !sessions.isEmpty else { return }
        func focusPriority(_ s: Status) -> Int {
            switch s {
            case .Attention: return 0
            case .Idle:      return 1
            case .Working:   return 2
            }
        }
        if let (idx, _) = sessions.enumerated().min(by: { focusPriority($0.element.status) < focusPriority($1.element.status) }) {
            setSelectedIndex(idx)
        }
    }

    // MARK: - Keyboard navigation

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }
        switch chars {
        case "j":
            selectNext()
        case "k":
            selectPrevious()
        case "q":
            clearSelection()
            onHide?()
        default:
            if event.keyCode == 36 || event.keyCode == 76 {
                activateSelected()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func selectNext() {
        guard !sessions.isEmpty else { return }
        let next = selectedIndex.map { min($0 + 1, sessions.count - 1) } ?? 0
        setSelectedIndex(next)
    }

    private func selectPrevious() {
        guard !sessions.isEmpty else { return }
        let prev = selectedIndex.map { max($0 - 1, 0) } ?? 0
        setSelectedIndex(prev)
    }

    private func activateSelected() {
        guard let idx = selectedIndex, idx < sessions.count else { return }
        let session = sessions[idx]
        clearSelection()
        onSessionClick?(session)
    }

    private func clearSelection() {
        if let old = selectedIndex, old < rowViews.count {
            rowViews[old].setSelected(false)
        }
        selectedIndex = nil
    }

    private func setSelectedIndex(_ index: Int) {
        if let old = selectedIndex, old < rowViews.count {
            rowViews[old].setSelected(false)
        }
        selectedIndex = index
        if index < rowViews.count {
            rowViews[index].setSelected(true)
        }
    }

    // MARK: - Context menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit BottyCall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Drag destination

    private func targetRowIndex(for info: NSDraggingInfo) -> Int? {
        let point = contentView.convert(info.draggingLocation, from: nil)
        for (i, row) in rowViews.enumerated() {
            if row.frame.contains(point) {
                if let sourceId = info.draggingPasteboard.pasteboardItems?.first?.string(forType: .sessionDrag),
                   row.session?.session_id == sourceId {
                    return nil
                }
                return i
            }
        }
        return nil
    }

    private func updateHighlight(_ index: Int?) {
        if let old = (selectedIndex == nil ? nil : selectedIndex), old < rowViews.count {
            // preserve keyboard selection highlight
        }
        for (i, row) in rowViews.enumerated() {
            row.setDropHighlight(i == index)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let idx = targetRowIndex(for: sender)
        updateHighlight(idx)
        return idx != nil ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let idx = targetRowIndex(for: sender)
        updateHighlight(idx)
        return idx != nil ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateHighlight(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateHighlight(nil)

        guard let sourceId = sender.draggingPasteboard.pasteboardItems?.first?.string(forType: .sessionDrag),
              let targetIdx = targetRowIndex(for: sender),
              targetIdx < sessions.count else { return false }

        let target = sessions[targetIdx]
        guard let source = sessions.first(where: { $0.session_id == sourceId }),
              source.session_id != target.session_id else { return false }

        return onSessionDrop?(source, target) ?? false
    }
}

// MARK: - Column header

private class ColumnHeaderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let color = NSColor(white: 0.55, alpha: 1)

        let session = NSTextField(labelWithString: "Session")
        session.font = font
        session.textColor = color
        session.isBezeled = false
        session.drawsBackground = false
        session.isEditable = false
        session.isSelectable = false

        let activity = NSTextField(labelWithString: "Activity")
        activity.font = font
        activity.textColor = color
        activity.isBezeled = false
        activity.drawsBackground = false
        activity.isEditable = false
        activity.isSelectable = false
        activity.alignment = .right

        for v in [session, activity] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            session.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SessionRowView.leadingPad),
            session.centerYAnchor.constraint(equalTo: centerYAnchor),

            activity.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SessionRowView.trailingPad),
            activity.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

// MARK: - Flipped scroll content

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

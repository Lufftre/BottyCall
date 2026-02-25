import AppKit
import Carbon

// References accessible from the C-compatible hotkey callback (no captures allowed).
private var _hotKeyPanel: NSPanel?
private var _hotKeySidebar: SidebarView?
private var _hotKeyAppDelegate: AppDelegate?

private let _hotKeyCallback: EventHandlerUPP = { _, _, _ -> OSStatus in
    DispatchQueue.main.async {
        _hotKeyAppDelegate?.previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        _hotKeyAppDelegate?.showCenteredAndFront()
        _hotKeySidebar?.selectBestSession()
    }
    return noErr
}

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        alphaValue = 1.0
        if firstResponder == nil || firstResponder === self {
            if let sidebar = contentView?.subviews.first {
                makeFirstResponder(sidebar)
            }
        }
    }

    override func resignKey() {
        super.resignKey()
        alphaValue = 0.75
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: KeyablePanel!
    private var sidebarView: SidebarView!
    private var sessionStore: SessionStore!
    private var connection: SessionConnection!
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var isCenteredMode = false
    var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        registerHotKey()

        sessionStore = SessionStore()
        sessionStore.onUpdate = { [weak self] in
            guard let self else { return }
            sidebarView.update(groups: sessionStore.groups)
        }

        connection = SessionConnection()
        connection.onMessage = { [weak self] msg in
            self?.sessionStore.apply(msg)
        }
        connection.onConnected = { [weak self] connected in
            self?.sidebarView.setConnected(connected)
        }
        connection.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionPanel()
        }
    }

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 250
        let initialHeight: CGFloat = 80
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width,
            y: screen.visibleFrame.maxY - initialHeight,
            width: width,
            height: initialHeight
        )

        panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.07, alpha: 0.92)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.alphaValue = 0.75

        sidebarView = SidebarView(frame: panel.contentView!.bounds)
        sidebarView.autoresizingMask = [.width, .height]
        sidebarView.onSessionClick = { session in
            guard let pane = session.tmux_pane else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["tmux", "switch-client", "-t", pane]
            try? task.run()

            if let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").first {
                ghostty.activate()
            }
        }
        sidebarView.onSessionDrop = { source, target in
            Self.handleMerge(source: source, target: target)
        }
        sidebarView.onHide = { [weak self] in
            self?.panel.orderOut(nil)
        }
        sidebarView.onEscapeKey = { [weak self] in
            guard let self else { return }
            previousApp?.activate(options: .activateIgnoringOtherApps)
            previousApp = nil
        }

        sidebarView.onHeightChange = { [weak self] height in
            self?.resizePanel(to: height)
        }

        panel.contentView!.addSubview(sidebarView)
        panel.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isCenteredMode, let screen = NSScreen.main else { return }
            let width: CGFloat = 250
            let height = min(self.sidebarView.intrinsicContentHeight, screen.visibleFrame.height)
            let frame = NSRect(
                x: screen.visibleFrame.maxX - width,
                y: screen.visibleFrame.maxY - height,
                width: width,
                height: height
            )
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                self?.isCenteredMode = false
            })
        }
    }

    func showCenteredAndFront() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let expandedWidth: CGFloat = 380
        let height = min(sidebarView.intrinsicContentHeight, visible.height)
        let frame = NSRect(
            x: visible.maxX - expandedWidth,
            y: visible.maxY - height,
            width: expandedWidth,
            height: height
        )
        isCenteredMode = true
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func registerHotKey() {
        _hotKeyPanel = panel
        _hotKeySidebar = sidebarView
        _hotKeyAppDelegate = self

        var et = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), _hotKeyCallback, 1, &et, nil, &hotKeyHandlerRef)

        var hkID = EventHotKeyID()
        hkID.signature = FourCharCode(0x42_43_55_49)  // "BCUI"
        hkID.id = 1

        // Cmd+Shift+Ö — on Swedish keyboards Ö is at the physical position of
        // the semicolon key (kVK_ANSI_Semicolon = 0x29) on a US layout.
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Semicolon),
            UInt32(cmdKey | shiftKey),
            hkID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    private func resizePanel(to height: CGFloat) {
        guard !isCenteredMode else { return }
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 250
        let clamped = min(height, screen.visibleFrame.height)
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width,
            y: screen.visibleFrame.maxY - clamped,
            width: width,
            height: clamped
        )
        panel.setFrame(frame, display: true)
    }

    private func repositionPanel() {
        guard !isCenteredMode else { return }
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 250
        let currentHeight = panel.frame.height
        let clamped = min(currentHeight, screen.visibleFrame.height)
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width,
            y: screen.visibleFrame.maxY - clamped,
            width: width,
            height: clamped
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Merge logic

    /// Returns true if merge was initiated (same repo), false otherwise.
    private static func handleMerge(source: Session, target: Session) -> Bool {
        guard let sourceRepo = source.git_repo, let targetRepo = target.git_repo,
              sourceRepo == targetRepo,
              let sourceCwd = source.cwd,
              let targetCwd = target.cwd,
              let sourcePane = source.tmux_pane, let targetPane = target.tmux_pane,
              sourcePane != targetPane else { return false }

        guard let branch = shell("git", "-C", sourceCwd, "branch", "--show-current"),
              !branch.isEmpty else { return false }

        guard let tmuxSession = shell("tmux", "display-message", "-t", targetPane, "-p", "#{session_name}") else { return false }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let newPane = shell("tmux", "new-window", "-t", tmuxSession, "-c", targetCwd, "-P", "-F", "#{pane_id}") else { return }

            let prompt = "Merge the git branch '\(branch)' into the current branch. Resolve any merge conflicts. Once the merge is complete and committed, close the source session by running: tmux kill-pane -t \(sourcePane)"

            run("tmux", "send-keys", "-t", newPane, "claude \"\(prompt)\"", "Enter")
        }

        return true
    }

    private static func run(_ args: String...) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        try? task.run()
        task.waitUntilExit()
    }
}

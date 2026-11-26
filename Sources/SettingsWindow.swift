import AppKit
import Carbon
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    private let config: ConfigStore
    private let onRecordingChanged: (Bool) -> Void
    private let onPreferencesChanged: () -> Void
    private var movePopup = NSPopUpButton()
    private var resizePopup = NSPopUpButton()
    private var gapField = NSTextField()
    private var gapStepper = NSStepper()
    private var edgeCheck = NSButton(checkboxWithTitle: "Snap at Screen Edges", target: nil, action: nil)
    private var smartCheck = NSButton(checkboxWithTitle: "Resize from Pointer Quadrant", target: nil, action: nil)
    private var focusCheck = NSButton(checkboxWithTitle: "Focus Window During Gesture", target: nil, action: nil)
    private var nearbyCheck = NSButton(checkboxWithTitle: "Snap to Nearby Windows", target: nil, action: nil)
    private var hideIconCheck = NSButton(checkboxWithTitle: "Hide Menu Bar Icon (reopen app for Settings)", target: nil, action: nil)
    private var loginCheck = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private var errorLabel = NSTextField(labelWithString: "")
    private var recorderButtons: [Layout: ShortcutRecorderButton] = [:]

    init(config: ConfigStore = .shared,
         onRecordingChanged: @escaping (Bool) -> Void,
         onPreferencesChanged: @escaping () -> Void = {}) {
        self.config = config
        self.onRecordingChanged = onRecordingChanged
        self.onPreferencesChanged = onPreferencesChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowShift Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        movePopup.selectItem(withTitle: "\(config.moveChord.rawValue)  (\(config.moveChord.configName))")
        resizePopup.selectItem(withTitle: "\(config.resizeChord.rawValue)  (\(config.resizeChord.configName))")
        let gap = Int(config.gapSize.rounded())
        gapField.stringValue = "\(gap)"
        gapStepper.integerValue = gap
        edgeCheck.state = config.edgeSnapping ? .on : .off
        smartCheck.state = config.smartResize ? .on : .off
        focusCheck.state = config.focusWindow ? .on : .off
        nearbyCheck.state = config.snapToNearbyWindows ? .on : .off
        hideIconCheck.state = config.hideMenubarIcon ? .on : .off
        if #available(macOS 13.0, *) {
            loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        if let err = config.lastError {
            errorLabel.stringValue = "Config error: \(err)"
            errorLabel.isHidden = false
        } else {
            errorLabel.stringValue = ""
            errorLabel.isHidden = true
        }
        for (layout, button) in recorderButtons {
            button.binding = config.shortcutBinding(for: layout)
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.isHidden = true
        root.addArrangedSubview(errorLabel)

        let chordTitles = Chord.allCases.map { "\($0.rawValue)  (\($0.configName))" }
        movePopup.addItems(withTitles: chordTitles)
        movePopup.target = self
        movePopup.action = #selector(moveChordChanged)
        resizePopup.addItems(withTitles: chordTitles)
        resizePopup.target = self
        resizePopup.action = #selector(resizeChordChanged)

        gapField.controlSize = .regular
        gapField.alignment = .right
        gapField.target = self
        gapField.action = #selector(gapFieldChanged)
        gapField.translatesAutoresizingMaskIntoConstraints = false
        gapField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        gapStepper.minValue = 0
        gapStepper.maxValue = 100
        gapStepper.increment = 2
        gapStepper.valueWraps = false
        gapStepper.target = self
        gapStepper.action = #selector(gapStepperChanged)

        let gapRow = NSStackView(views: [gapField, gapStepper, NSTextField(labelWithString: "px")])
        gapRow.orientation = .horizontal
        gapRow.spacing = 6

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Move Window:"), movePopup],
            [NSTextField(labelWithString: "Resize Window:"), resizePopup],
            [NSTextField(labelWithString: "Window Gap:"), gapRow]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        root.addArrangedSubview(grid)

        let toggles: [(NSButton, Selector)] = [
            (edgeCheck, #selector(toggleEdge)),
            (smartCheck, #selector(toggleSmart)),
            (focusCheck, #selector(toggleFocus)),
            (nearbyCheck, #selector(toggleNearby)),
            (hideIconCheck, #selector(toggleHideIcon)),
            (loginCheck, #selector(toggleLogin))
        ]
        let toggleStack = NSStackView()
        toggleStack.orientation = .vertical
        toggleStack.alignment = .leading
        toggleStack.spacing = 5
        for (button, action) in toggles {
            button.target = self
            button.action = action
            toggleStack.addArrangedSubview(button)
        }
        root.addArrangedSubview(toggleStack)

        let shortcutsHeader = NSTextField(labelWithString: "Keyboard Shortcuts (click to record, Esc to cancel)")
        shortcutsHeader.font = .boldSystemFont(ofSize: 12)
        root.addArrangedSubview(shortcutsHeader)

        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        listStack.translatesAutoresizingMaskIntoConstraints = false

        for layout in Layout.allCases {
            let label = NSTextField(labelWithString: layout.rawValue)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 160).isActive = true

            let recorder = ShortcutRecorderButton(
                onChange: { [weak self] binding in
                    self?.config.setShortcut(binding, for: layout)
                },
                onRecordingChanged: { [weak self] recording in
                    self?.onRecordingChanged(recording)
                }
            )
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 140).isActive = true
            recorderButtons[layout] = recorder

            let clear = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
            clear.bezelStyle = .rounded
            clear.controlSize = .small
            clear.tag = Layout.allCases.firstIndex(of: layout) ?? 0

            let row = NSStackView(views: [label, recorder, clear])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            listStack.addArrangedSubview(row)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let clip = FlippedClipView()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.documentView = listStack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            scroll.widthAnchor.constraint(equalToConstant: 424)
        ])
        root.addArrangedSubview(scroll)

        let openButton = NSButton(title: "Open config.json…", target: self, action: #selector(openConfig))
        openButton.bezelStyle = .rounded
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1"
        let versionLabel = NSTextField(labelWithString: "WindowShift \(version)")
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [openButton, spacer, versionLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.widthAnchor.constraint(equalToConstant: 424).isActive = true
        root.addArrangedSubview(footer)
    }

    @objc private func moveChordChanged() {
        let index = movePopup.indexOfSelectedItem
        guard index >= 0, index < Chord.allCases.count else { return }
        let chord = Chord.allCases[index]
        if chord == config.resizeChord { config.resizeChord = config.moveChord }
        config.moveChord = chord
        onPreferencesChanged()
        reload()
    }

    @objc private func resizeChordChanged() {
        let index = resizePopup.indexOfSelectedItem
        guard index >= 0, index < Chord.allCases.count else { return }
        let chord = Chord.allCases[index]
        if chord == config.moveChord { config.moveChord = config.resizeChord }
        config.resizeChord = chord
        onPreferencesChanged()
        reload()
    }

    @objc private func gapFieldChanged() {
        let value = max(0, min(100, Double(gapField.integerValue)))
        config.gapSize = CGFloat(value)
        reload()
    }

    @objc private func gapStepperChanged() {
        config.gapSize = CGFloat(gapStepper.integerValue)
        reload()
    }

    @objc private func toggleEdge() { config.edgeSnapping = edgeCheck.state == .on; onPreferencesChanged() }
    @objc private func toggleSmart() { config.smartResize = smartCheck.state == .on }
    @objc private func toggleFocus() { config.focusWindow = focusCheck.state == .on }
    @objc private func toggleNearby() { config.snapToNearbyWindows = nearbyCheck.state == .on }
    @objc private func toggleHideIcon() { config.hideMenubarIcon = hideIconCheck.state == .on; onPreferencesChanged() }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled { try service.unregister() }
            else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        reload()
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < Layout.allCases.count else { return }
        let layout = Layout.allCases[sender.tag]
        config.setShortcut(nil, for: layout)
        recorderButtons[layout]?.binding = nil
    }

    @objc private func openConfig() {
        _ = config.writeSnapshotIfMissing()
        NSWorkspace.shared.open(config.fileURL.resolvingSymlinksInPath())
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class ShortcutRecorderButton: NSButton {
    private let onChange: (Shortcuts.Binding?) -> Void
    private let onRecordingChanged: (Bool) -> Void
    private var monitor: Any?
    private var isRecording = false

    var binding: Shortcuts.Binding? {
        didSet { updateTitle() }
    }

    init(onChange: @escaping (Shortcuts.Binding?) -> Void, onRecordingChanged: @escaping (Bool) -> Void) {
        self.onChange = onChange
        self.onRecordingChanged = onRecordingChanged
        super.init(frame: .zero)
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func updateTitle() {
        if isRecording {
            title = "Type shortcut…"
        } else {
            title = binding?.label ?? "Unassigned"
        }
    }

    @objc private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChanged(true)
        updateTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let code = Int(event.keyCode)
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if code == kVK_Escape && flags.isEmpty {
                self.stopRecording()
                return nil
            }
            if (code == kVK_Delete || code == kVK_ForwardDelete) && flags.isEmpty {
                self.binding = nil
                self.onChange(nil)
                self.stopRecording()
                return nil
            }
            guard !flags.isEmpty else { return nil }
            let newBinding = Shortcuts.Binding(key: UInt32(code), flags: flags)
            guard newBinding.carbonFlags != 0 else { return nil }
            self.binding = newBinding
            self.onChange(newBinding)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        self.monitor = nil
        onRecordingChanged(false)
        updateTitle()
    }

    deinit { stopRecording() }
}

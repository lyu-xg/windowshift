import AppKit
import ApplicationServices
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let config = ConfigStore.shared
    private let controller = Controller()
    private let shortcuts = Shortcuts()
    private let menu = NSMenu()
    private var settingsWindow: SettingsWindowController?
    var enableLoginFromImport = false
    private var permissionCheck: Timer?
    private var missingShortcuts: [String] = []
    private var paused = false
    private var recordingShortcut = false
    private var frontmostExcluded = false
    private var menuWindow: AXUIElement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status.menu = menu
        menu.delegate = self
        shortcuts.onLayout = { [weak self] in self?.controller.perform($0) }
        config.onChange = { [weak self] in self?.reloadConfig() }
        config.startWatching()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
        updateFrontmostExclusion()

        if enableLoginFromImport && SMAppService.mainApp.status == .notRegistered {
            do { try SMAppService.mainApp.register() }
            catch { NSLog("Unable to register WindowShift at login: %@", error.localizedDescription) }
        }
        refreshPermissions()
        permissionCheck = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    private var shortcutsShouldRun: Bool {
        controller.isRunning && !recordingShortcut && !frontmostExcluded
    }

    private func syncShortcuts(forceRestart: Bool = false) {
        if shortcutsShouldRun {
            if forceRestart { shortcuts.stop() }
            missingShortcuts = shortcuts.start()
        } else {
            shortcuts.stop()
            missingShortcuts = []
        }
    }

    private func reloadConfig() {
        controller.hidePreviewIfDisabled()
        updateFrontmostExclusion()
        syncShortcuts(forceRestart: true)
        settingsWindow?.reload()
        updateStatusIcon()
    }

    private func updateFrontmostExclusion() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        frontmostExcluded = !bundleID.isEmpty && config.ignoresShortcuts(for: bundleID)
    }

    @objc private func frontmostAppChanged(_ notification: Notification) {
        let previous = frontmostExcluded
        updateFrontmostExclusion()
        if frontmostExcluded != previous {
            syncShortcuts()
        }
    }

    @objc private func keyboardLayoutChanged() {
        if shortcutsShouldRun {
            syncShortcuts(forceRestart: true)
        }
        settingsWindow?.reload()
    }

    private func refreshPermissions() {
        if AXIsProcessTrusted() && !paused {
            if !controller.isRunning, controller.start() {
                syncShortcuts(forceRestart: true)
            }
        } else if controller.isRunning {
            shortcuts.stop()
            controller.stop()
        }
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = status.button else { return }
        let trusted = AXIsProcessTrusted()
        let running = controller.isRunning
        let hasError = config.lastError != nil

        let symbolName: String
        let disabled: Bool
        let tip: String
        if !trusted {
            symbolName = "macwindow.badge.exclamationmark"
            disabled = true
            tip = "WindowShift — Accessibility permission required"
        } else if !running && !paused {
            symbolName = "macwindow.badge.exclamationmark"
            disabled = true
            tip = "WindowShift — Input Monitoring permission required"
        } else if paused {
            symbolName = "macwindow"
            disabled = true
            tip = "WindowShift — Paused"
        } else if hasError {
            symbolName = "macwindow.badge.exclamationmark"
            disabled = false
            tip = "WindowShift — Config error: \(config.lastError ?? "")"
        } else {
            symbolName = "macwindow"
            disabled = false
            tip = "WindowShift"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WindowShift")
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: "WindowShift")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = disabled
        button.toolTip = tip
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuWindow = Windows.focused()
        menu.removeAllItems()
        if !AXIsProcessTrusted() {
            add("Enable Accessibility…", #selector(requestAccessibility))
        } else if !controller.isRunning && !paused {
            add("Open Input Monitoring Settings…", #selector(openInputSettings))
        } else {
            let pause = add(paused ? "Resume WindowShift" : "Pause WindowShift", #selector(togglePause))
            pause.state = paused ? .on : .off
        }

        menu.addItem(.separator())
        let layouts = NSMenu()
        for layout in Layout.allCases {
            let suffix = Shortcuts.binding(for: layout).map { "   \($0.label)" } ?? ""
            let item = NSMenuItem(title: layout.rawValue + suffix, action: #selector(chooseLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            layouts.addItem(item)
        }
        addSubmenu(layouts, title: "Window Layouts")
        if !missingShortcuts.isEmpty && controller.isRunning {
            let item = NSMenuItem(title: "Shortcuts unavailable: \(missingShortcuts.joined(separator: " "))",
                                  action: nil, keyEquivalent: "")
            menu.addItem(item)
        }

        addSubmenu(chordMenu(resize: false), title: "Move Window: \(controller.moveChord.rawValue)")
        addSubmenu(chordMenu(resize: true), title: "Resize Window: \(controller.resizeChord.rawValue)")
        add("Resize from Pointer Quadrant", #selector(toggleSmartResize)).state = controller.smartResize ? .on : .off
        add("Focus Window During Gesture", #selector(toggleFocus)).state = controller.focusWindow ? .on : .off
        add("Snap at Screen Edges", #selector(toggleSnapping)).state = controller.edgeSnapping ? .on : .off
        add("Snap to Nearby Windows", #selector(toggleNearby)).state = controller.snapToNearbyWindows ? .on : .off
        if let configError = config.lastError {
            let item = add("Config error: \(configError)", #selector(openConfig))
            item.toolTip = "Click to open config.json"
        }
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), key: ",")
        add("Open Config…", #selector(openConfig))
        if #available(macOS 13.0, *) {
            add("Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        let versionItem = NSMenuItem(title: "WindowShift \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        add("Quit WindowShift", #selector(NSApplication.terminate(_:)), key: "q").target = NSApp
    }

    private func chordMenu(resize: Bool) -> NSMenu {
        let submenu = NSMenu()
        for chord in Chord.allCases {
            let item = NSMenuItem(title: chord.rawValue, action: #selector(chooseChord(_:)), keyEquivalent: "")
            item.target = self
            item.tag = resize ? 1 : 0
            item.representedObject = chord.rawValue
            let current = resize ? controller.resizeChord : controller.moveChord
            item.state = current == chord ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func addSubmenu(_ submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc private func chooseChord(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let chord = Chord(rawValue: raw) else { return }
        if sender.tag == 1 {
            if chord == controller.moveChord { controller.moveChord = controller.resizeChord }
            controller.resizeChord = chord
        } else {
            if chord == controller.resizeChord { controller.resizeChord = controller.moveChord }
            controller.moveChord = chord
        }
        settingsWindow?.reload()
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard !paused, AXIsProcessTrusted(), let raw = sender.representedObject as? String,
              let layout = Layout(rawValue: raw) else { return }
        controller.perform(layout, on: menuWindow)
    }

    @objc private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openInputSettings() {
        _ = CGRequestListenEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(config: config) { [weak self] recording in
                self?.recordingShortcut = recording
                self?.syncShortcuts()
            }
        }
        settingsWindow?.show()
    }

    @objc private func openConfig() {
        _ = config.writeSnapshotIfMissing()
        NSWorkspace.shared.open(config.fileURL.resolvingSymlinksInPath())
    }

    @objc private func togglePause() { paused.toggle(); refreshPermissions() }
    @objc private func toggleSmartResize() { controller.smartResize.toggle(); settingsWindow?.reload() }
    @objc private func toggleFocus() { controller.focusWindow.toggle(); settingsWindow?.reload() }
    @objc private func toggleSnapping() { controller.edgeSnapping.toggle(); settingsWindow?.reload() }
    @objc private func toggleNearby() { controller.snapToNearbyWindows.toggle(); settingsWindow?.reload() }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            let service = SMAppService.mainApp
            if service.status == .enabled { try service.unregister() }
            else { try service.register() }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        settingsWindow?.reload()
    }
}

@main
struct WindowShiftApp {
    static func main() {
        let launchAtLogin = CommandLine.arguments.contains("--import-settings") && ImportedSettings.apply()
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.windowshift.app"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard existing.isEmpty else { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.enableLoginFromImport = launchAtLogin
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

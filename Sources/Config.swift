import AppKit
import Carbon
import Foundation

struct ConfigFile: Codable, Equatable {
    var moveChord: String?
    var resizeChord: String?
    var edgeSnapping: Bool?
    var smartResize: Bool?
    var focusWindow: Bool?
    var snapToNearbyWindows: Bool?
    var ignoredGestureApps: [String]?
    var shortcuts: [String: String?]?
}

final class ConfigStore {
    static let shared = ConfigStore()

    let fileURL: URL
    private let defaults: UserDefaults
    private var file: ConfigFile?
    private var lastLoadedData: Data?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var debounceWork: DispatchWorkItem?

    private(set) var lastError: String?
    var onChange: (() -> Void)?

    var hasFile: Bool { file != nil }

    init(fileURL: URL = ConfigStore.defaultFileURL(), defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        loadIfPresent()
    }

    static func defaultFileURL() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("windowshift", isDirectory: true)
                .appendingPathComponent("config.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("windowshift", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    var moveChord: Chord {
        get {
            if let raw = file?.moveChord, let chord = Chord.parse(raw) { return chord }
            return Chord(rawValue: defaults.string(forKey: "moveChord") ?? "") ?? .controlCommand
        }
        set {
            defaults.set(newValue.rawValue, forKey: "moveChord")
            updateFile { $0.moveChord = newValue.configName }
        }
    }

    var resizeChord: Chord {
        get {
            if let raw = file?.resizeChord, let chord = Chord.parse(raw) { return chord }
            return Chord(rawValue: defaults.string(forKey: "resizeChord") ?? "") ?? .controlCommandShift
        }
        set {
            defaults.set(newValue.rawValue, forKey: "resizeChord")
            updateFile { $0.resizeChord = newValue.configName }
        }
    }

    var smartResize: Bool {
        get { file?.smartResize ?? (defaults.object(forKey: "smartResize") as? Bool ?? true) }
        set {
            defaults.set(newValue, forKey: "smartResize")
            updateFile { $0.smartResize = newValue }
        }
    }

    var focusWindow: Bool {
        get { file?.focusWindow ?? defaults.bool(forKey: "focusWindow") }
        set {
            defaults.set(newValue, forKey: "focusWindow")
            updateFile { $0.focusWindow = newValue }
        }
    }

    var snapToNearbyWindows: Bool {
        get { file?.snapToNearbyWindows ?? defaults.bool(forKey: "snapToNearbyWindows") }
        set {
            defaults.set(newValue, forKey: "snapToNearbyWindows")
            updateFile { $0.snapToNearbyWindows = newValue }
        }
    }

    var edgeSnapping: Bool {
        get { file?.edgeSnapping ?? (defaults.object(forKey: "edgeSnapping") as? Bool ?? true) }
        set {
            defaults.set(newValue, forKey: "edgeSnapping")
            updateFile { $0.edgeSnapping = newValue }
        }
    }

    var ignoredGestureApps: [String] {
        file?.ignoredGestureApps ?? (defaults.stringArray(forKey: "ignoredGestureApps") ?? [])
    }

    func shortcutBinding(for layout: Layout) -> Shortcuts.Binding? {
        if let configured = file?.shortcuts {
            for key in layout.configKeys {
                if let entry = configured[key] {
                    guard let spec = entry?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !spec.isEmpty else { return nil }
                    return Shortcuts.Binding.parse(spec)
                }
            }
            return nil
        }
        return Shortcuts.defaultsBinding(for: layout, defaults: defaults)
    }

    func snapshot() -> ConfigFile {
        var shortcuts: [String: String?] = [:]
        for layout in Layout.allCases {
            guard let name = Shortcuts.rectangleKeys[layout] else { continue }
            shortcuts[name] = shortcutBinding(for: layout)?.configString
        }
        return ConfigFile(
            moveChord: moveChord.configName,
            resizeChord: resizeChord.configName,
            edgeSnapping: edgeSnapping,
            smartResize: smartResize,
            focusWindow: focusWindow,
            snapToNearbyWindows: snapToNearbyWindows,
            ignoredGestureApps: ignoredGestureApps,
            shortcuts: shortcuts
        )
    }

    @discardableResult
    func writeSnapshotIfMissing() -> Bool {
        let resolved = fileURL.resolvingSymlinksInPath()
        guard !FileManager.default.fileExists(atPath: resolved.path) else { return true }
        return write(snapshot())
    }

    @discardableResult
    func write(_ config: ConfigFile) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard var data = try? encoder.encode(config) else { return false }
        data.append(0x0A)
        let target = resolvedWriteTarget()
        let directory = target.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            file = config
            lastLoadedData = data
            lastError = nil
            restartWatchers()
            return true
        } catch {
            NSLog("Unable to write WindowShift config: %@", error.localizedDescription)
            return false
        }
    }

    private func updateFile(_ mutate: (inout ConfigFile) -> Void) {
        guard var current = file else { return }
        mutate(&current)
        _ = write(current)
    }

    private func resolvedWriteTarget() -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            return fileURL.resolvingSymlinksInPath()
        }
        // If fileURL itself is a dangling symlink, resolve its link destination.
        if let dest = try? fm.destinationOfSymbolicLink(atPath: fileURL.path) {
            return URL(fileURLWithPath: dest, relativeTo: fileURL.deletingLastPathComponent()).standardizedFileURL
        }
        // Otherwise resolve parent directory in case ~/.config/windowshift is a directory symlink.
        let parent = fileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(fileURL.lastPathComponent)
    }

    func startWatching() {
        restartWatchers()
    }

    func stopWatching() {
        debounceWork?.cancel()
        debounceWork = nil
        for source in watchers { source.cancel() }
        watchers.removeAll()
    }

    @discardableResult
    func loadIfPresent() -> Bool {
        let resolved = fileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            let changed = file != nil || lastError != nil
            file = nil
            lastLoadedData = nil
            lastError = nil
            return changed
        }
        do {
            let data = try Data(contentsOf: resolved)
            if data == lastLoadedData && lastError == nil { return false }
            let decoded = try JSONDecoder().decode(ConfigFile.self, from: data)
            let validationError = Self.validate(decoded)
            if let validationError {
                lastError = validationError
                return false
            }
            let changed = decoded != file || lastError != nil
            file = decoded
            lastLoadedData = data
            lastError = nil
            return changed
        } catch {
            lastError = error.localizedDescription
            NSLog("Unable to load WindowShift config (%@): %@", resolved.path, error.localizedDescription)
            return false
        }
    }

    private static func validate(_ config: ConfigFile) -> String? {
        if let move = config.moveChord, Chord.parse(move) == nil {
            return "Invalid moveChord: \(move)"
        }
        if let resize = config.resizeChord, Chord.parse(resize) == nil {
            return "Invalid resizeChord: \(resize)"
        }
        if let shortcuts = config.shortcuts {
            let validKeys = Set(Layout.allCases.flatMap(\.configKeys))
            for (name, value) in shortcuts {
                if !validKeys.contains(name) {
                    return "Unknown shortcut: \(name)"
                }
                guard let spec = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !spec.isEmpty else { continue }
                if Shortcuts.Binding.parse(spec) == nil {
                    return "Invalid shortcut for \(name): \(spec)"
                }
            }
        }
        return nil
    }

    private func restartWatchers() {
        for source in watchers { source.cancel() }
        watchers.removeAll()

        var paths = Set<String>()
        let resolvedFile = fileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        if fm.fileExists(atPath: resolvedFile.path) {
            paths.insert(resolvedFile.path)
        }
        let resolvedParent = resolvedFile.deletingLastPathComponent().path
        if fm.fileExists(atPath: resolvedParent) {
            paths.insert(resolvedParent)
        }
        let configuredParent = fileURL.deletingLastPathComponent().path
        if fm.fileExists(atPath: configuredParent) {
            paths.insert(configuredParent)
        }
        let configRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent().path
        if !fm.fileExists(atPath: configuredParent), fm.fileExists(atPath: configRoot) {
            paths.insert(configRoot)
        }

        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let mask: DispatchSource.FileSystemEvent = [.write, .rename, .delete, .attrib, .extend, .link]
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
            source.setEventHandler { [weak self] in
                self?.scheduleReload()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changed = self.loadIfPresent()
            self.restartWatchers()
            if changed {
                self.onChange?()
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    deinit { stopWatching() }
}

extension Chord {
    var configName: String {
        switch self {
        case .controlCommand: return "ctrl+cmd"
        case .controlCommandShift: return "ctrl+shift+cmd"
        case .optionCommand: return "opt+cmd"
        case .shiftCommand: return "shift+cmd"
        case .optionCommandShift: return "opt+shift+cmd"
        case .controlOption: return "ctrl+opt"
        case .controlOptionShift: return "ctrl+opt+shift"
        }
    }

    static func parse(_ raw: String) -> Chord? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Chord(rawValue: trimmed) { return exact }
        let tokens = trimmed.lowercased()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: " ", with: "+")
            .split(separator: "+")
            .map(String.init)
        guard !tokens.isEmpty else { return nil }
        var flags: CGEventFlags = []
        for token in tokens {
            switch token {
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "shift", "⇧": flags.insert(.maskShift)
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            default: return nil
            }
        }
        return Chord.allCases.first { $0.flags == flags }
    }
}

extension Layout {
    var configKeys: [String] {
        var keys: [String] = []
        if let rect = Shortcuts.rectangleKeys[self] { keys.append(rect) }
        switch self {
        case .left: keys.append("left")
        case .right: keys.append("right")
        case .top: keys.append("top")
        case .bottom: keys.append("bottom")
        case .middleThird: keys.append("middleThird")
        default: break
        }
        return keys
    }
}

extension Shortcuts.Binding {
    private static let keyNameToCode: [String: Int] = [
        "a": kVK_ANSI_A, "s": kVK_ANSI_S, "d": kVK_ANSI_D, "f": kVK_ANSI_F,
        "h": kVK_ANSI_H, "g": kVK_ANSI_G, "z": kVK_ANSI_Z, "x": kVK_ANSI_X,
        "c": kVK_ANSI_C, "v": kVK_ANSI_V, "b": kVK_ANSI_B, "q": kVK_ANSI_Q,
        "w": kVK_ANSI_W, "e": kVK_ANSI_E, "r": kVK_ANSI_R, "y": kVK_ANSI_Y,
        "t": kVK_ANSI_T, "o": kVK_ANSI_O, "u": kVK_ANSI_U, "i": kVK_ANSI_I,
        "p": kVK_ANSI_P, "l": kVK_ANSI_L, "j": kVK_ANSI_J, "k": kVK_ANSI_K,
        "n": kVK_ANSI_N, "m": kVK_ANSI_M,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "=": kVK_ANSI_Equal, "equal": kVK_ANSI_Equal, "plus": kVK_ANSI_Equal,
        "-": kVK_ANSI_Minus, "minus": kVK_ANSI_Minus,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        "'": kVK_ANSI_Quote, ";": kVK_ANSI_Semicolon, "\\": kVK_ANSI_Backslash,
        ",": kVK_ANSI_Comma, "comma": kVK_ANSI_Comma,
        "/": kVK_ANSI_Slash, "slash": kVK_ANSI_Slash,
        ".": kVK_ANSI_Period, "period": kVK_ANSI_Period,
        "`": kVK_ANSI_Grave, "grave": kVK_ANSI_Grave,
        "return": kVK_Return, "enter": kVK_Return, "↩": kVK_Return,
        "delete": kVK_Delete, "backspace": kVK_Delete, "⌫": kVK_Delete,
        "escape": kVK_Escape, "esc": kVK_Escape, "⎋": kVK_Escape,
        "tab": kVK_Tab, "⇥": kVK_Tab,
        "space": kVK_Space,
        "left": kVK_LeftArrow, "←": kVK_LeftArrow,
        "right": kVK_RightArrow, "→": kVK_RightArrow,
        "up": kVK_UpArrow, "↑": kVK_UpArrow,
        "down": kVK_DownArrow, "↓": kVK_DownArrow,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
        "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
        "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12
    ]

    private static let keyCodeToName: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_S: "s", kVK_ANSI_D: "d", kVK_ANSI_F: "f",
        kVK_ANSI_H: "h", kVK_ANSI_G: "g", kVK_ANSI_Z: "z", kVK_ANSI_X: "x",
        kVK_ANSI_C: "c", kVK_ANSI_V: "v", kVK_ANSI_B: "b", kVK_ANSI_Q: "q",
        kVK_ANSI_W: "w", kVK_ANSI_E: "e", kVK_ANSI_R: "r", kVK_ANSI_Y: "y",
        kVK_ANSI_T: "t", kVK_ANSI_O: "o", kVK_ANSI_U: "u", kVK_ANSI_I: "i",
        kVK_ANSI_P: "p", kVK_ANSI_L: "l", kVK_ANSI_J: "j", kVK_ANSI_K: "k",
        kVK_ANSI_N: "n", kVK_ANSI_M: "m",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".",
        kVK_ANSI_Grave: "`",
        kVK_Return: "return", kVK_Delete: "delete", kVK_Escape: "escape",
        kVK_Tab: "tab", kVK_Space: "space",
        kVK_LeftArrow: "left", kVK_RightArrow: "right",
        kVK_UpArrow: "up", kVK_DownArrow: "down",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4",
        kVK_F5: "f5", kVK_F6: "f6", kVK_F7: "f7", kVK_F8: "f8",
        kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12"
    ]

    var configString: String? {
        guard let keyName = Self.keyCodeToName[Int(key)] else { return nil }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        guard !parts.isEmpty else { return nil }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    static func parse(_ spec: String) -> Shortcuts.Binding? {
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let parts: [String]
        if lower.hasSuffix("++") {
            let prefix = lower.dropLast(2).split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            parts = prefix + ["plus"]
        } else {
            parts = lower.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard parts.count >= 2, let keyToken = parts.last, let code = keyNameToCode[keyToken] else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for mod in parts.dropLast() {
            switch mod {
            case "ctrl", "control", "⌃": flags.insert(.control)
            case "opt", "option", "alt", "⌥": flags.insert(.option)
            case "shift", "⇧": flags.insert(.shift)
            case "cmd", "command", "⌘": flags.insert(.command)
            default: return nil
            }
        }
        let binding = Shortcuts.Binding(key: UInt32(code), flags: flags)
        return binding.carbonFlags != 0 ? binding : nil
    }
}

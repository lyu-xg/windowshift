import AppKit
import Carbon

enum KeyboardLayout {
    private static let printableKeyCodes: [Int] = [
        kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_H, kVK_ANSI_G,
        kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_Q,
        kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_Y, kVK_ANSI_T,
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_6, kVK_ANSI_5,
        kVK_ANSI_Equal, kVK_ANSI_9, kVK_ANSI_7, kVK_ANSI_Minus, kVK_ANSI_8, kVK_ANSI_0,
        kVK_ANSI_RightBracket, kVK_ANSI_O, kVK_ANSI_U, kVK_ANSI_LeftBracket, kVK_ANSI_I,
        kVK_ANSI_P, kVK_ANSI_L, kVK_ANSI_J, kVK_ANSI_Quote, kVK_ANSI_K,
        kVK_ANSI_Semicolon, kVK_ANSI_Backslash, kVK_ANSI_Comma, kVK_ANSI_Slash,
        kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Period, kVK_ANSI_Grave, kVK_ISO_Section
    ]

    static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let value = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    static func keyCode(for character: String) -> Int? {
        let target = character.lowercased()
        for code in printableKeyCodes {
            if let mapped = self.character(for: code)?.lowercased(), mapped == target {
                return code
            }
        }
        return nil
    }
}

final class Shortcuts {
    static let rectangleKeys: [Layout: String] = [
        .left: "leftHalf", .right: "rightHalf", .top: "topHalf", .bottom: "bottomHalf",
        .topLeft: "topLeft", .topRight: "topRight",
        .bottomLeft: "bottomLeft", .bottomRight: "bottomRight",
        .firstThird: "firstThird", .middleThird: "centerThird", .lastThird: "lastThird",
        .maximize: "maximize", .center: "center", .restore: "restore",
        .previousDisplay: "previousDisplay", .nextDisplay: "nextDisplay",
        .centerHalf: "centerHalf", .almostMaximize: "almostMaximize", .maximizeHeight: "maximizeHeight",
        .larger: "larger", .smaller: "smaller"
    ]

    private static let baseline: [Layout: Int] = [
        .left: kVK_LeftArrow, .right: kVK_RightArrow,
        .top: kVK_UpArrow, .bottom: kVK_DownArrow,
        .topLeft: kVK_ANSI_U, .topRight: kVK_ANSI_I,
        .bottomLeft: kVK_ANSI_J, .bottomRight: kVK_ANSI_K,
        .firstThird: kVK_ANSI_1, .middleThird: kVK_ANSI_2, .lastThird: kVK_ANSI_3,
        .maximize: kVK_Return, .center: kVK_ANSI_C, .restore: kVK_Delete,
        .previousDisplay: kVK_ANSI_LeftBracket, .nextDisplay: kVK_ANSI_RightBracket
    ]

    struct Binding {
        let key: UInt32
        let flags: NSEvent.ModifierFlags

        private static let modifiers: [(NSEvent.ModifierFlags, Int, String)] = [
            (.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
            (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")
        ]

        var carbonFlags: UInt32 {
            Self.modifiers.reduce(0) { flags.contains($1.0) ? $0 | UInt32($1.1) : $0 }
        }

        var label: String {
            let prefix = Self.modifiers.filter { flags.contains($0.0) }.map(\.2).joined()
            let special: [Int: String] = [
                kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
                kVK_DownArrow: "↓", kVK_Return: "↩", kVK_Delete: "⌫", kVK_Escape: "⎋",
                kVK_Tab: "⇥", kVK_Space: "Space",
                kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
                kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
                kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
            ]
            let dynamic = KeyboardLayout.character(for: Int(key))?.uppercased()
            let character = special[Int(key)] ?? dynamic ?? Self.ansiLabel(Int(key)) ?? "Key \(key)"
            return prefix + character
        }

        private static func ansiLabel(_ key: Int) -> String? {
            let rows: [(Int, String)] = [
                (0, "ASDFHGZXCV BQWERYT"), (18, "123465=97-80]OU[IP"),
                (37, "LJ'K;\\,/NM.")
            ]
            for (offset, row) in rows {
                let index = key - offset
                guard index >= 0, index < row.count else { continue }
                let character = row[row.index(row.startIndex, offsetBy: index)]
                return character == " " ? nil : String(character)
            }
            return nil
        }
    }

    static func binding(for layout: Layout, config: ConfigStore = .shared) -> Binding? {
        config.shortcutBinding(for: layout)
    }

    static func defaultsBinding(for layout: Layout, defaults: UserDefaults = .standard) -> Binding? {
        if let imported = defaults.dictionary(forKey: "rectangleShortcuts") {
            guard let name = rectangleKeys[layout], let entry = imported[name] as? [String: Int],
                  let key = entry["keyCode"], (0...127).contains(key),
                  let raw = entry["modifierFlags"], raw >= 0 else { return nil }
            let binding = Binding(key: UInt32(key), flags: NSEvent.ModifierFlags(rawValue: UInt(raw)))
            return binding.carbonFlags != 0 ? binding : nil
        }
        return baseline[layout].map { Binding(key: UInt32($0), flags: [.control, .option]) }
    }

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private let signature: OSType = 0x574E5348
    var onLayout: ((Layout) -> Void)?

    func start() -> [String] {
        if handler != nil { return [] }
        let configured = Layout.allCases.enumerated().compactMap { index, layout in
            Self.binding(for: layout).map { (index, $0) }
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let shortcuts = Unmanaged<Shortcuts>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let result = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == shortcuts.signature,
                  Int(id.id) < Layout.allCases.count else { return OSStatus(eventNotHandledErr) }
            shortcuts.onLayout?(Layout.allCases[Int(id.id)])
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return configured.map { $0.1.label } }

        var unavailable: [String] = []
        for (index, binding) in configured {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: UInt32(index))
            let result = RegisterEventHotKey(binding.key, binding.carbonFlags, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotKeys.append(ref) }
            else { unavailable.append(binding.label) }
        }
        return unavailable
    }

    func stop() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { stop() }
}

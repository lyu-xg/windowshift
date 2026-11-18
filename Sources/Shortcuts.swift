import AppKit
import Carbon

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
                kVK_Tab: "⇥", kVK_Space: "Space"
            ]
            let character = special[Int(key)] ?? Self.ansiLabel(Int(key)) ?? "Key \(key)"
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

    static func binding(for layout: Layout, defaults: UserDefaults = .standard) -> Binding? {
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

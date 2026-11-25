import AppKit

enum ImportedSettings {
    static let rectangleID = "com.knollsoft.Rectangle"
    static let swiftShiftID = "com.pablopunk.Swift-Shift"

    @discardableResult
    static func apply(to defaults: UserDefaults = .standard) -> Bool {
        let swiftShift = defaults.persistentDomain(forName: swiftShiftID) ?? [:]
        let rectangle = defaults.persistentDomain(forName: rectangleID) ?? [:]
        for (source, destination) in [("Move", "moveChord"), ("Resize", "resizeChord")] {
            if let data = swiftShift["\(source)_keyboardShortcut"] as? Data,
               let decoded = try? JSONDecoder().decode(GestureShortcut.self, from: data),
               let chord = Chord.allCases.first(where: { $0.flags.rawValue == decoded.modifierFlagsRawValue }) {
                defaults.set(chord.rawValue, forKey: destination)
            }
        }
        if let focus = swiftShift["focusOnApp"] as? Bool {
            defaults.set(focus, forKey: "focusWindow")
        }
        if let ignored = swiftShift["ignoredApps"] as? [String] {
            defaults.set(ignored, forKey: "ignoredGestureApps")
        }
        if !swiftShift.isEmpty {
            defaults.set(swiftShift["useQuadrants"] as? Bool ?? false, forKey: "smartResize")
        }
        if let snap = swiftShift["snapToWindows"] as? Bool {
            defaults.set(snap, forKey: "snapToNearbyWindows")
        }
        if !rectangle.isEmpty {
            let bindings = rectangle.compactMapValues { $0 as? [String: Int] }
                .filter { Shortcuts.rectangleKeys.values.contains($0.key) }
            defaults.set(bindings, forKey: "rectangleShortcuts")
            if let snapping = rectangle["windowSnapping"] as? Int, snapping != 0 {
                defaults.set(snapping == 2, forKey: "edgeSnapping")
            }
        }
        if defaults === UserDefaults.standard, (!swiftShift.isEmpty || !rectangle.isEmpty), !ConfigStore.shared.hasFile {
            _ = ConfigStore.shared.write(ConfigStore.shared.snapshot())
        }
        return rectangle["launchOnLogin"] as? Bool == true || swiftShift["launchAtLogin"] as? Bool == true
    }

    private struct GestureShortcut: Decodable {
        let modifierFlagsRawValue: UInt64
    }
}

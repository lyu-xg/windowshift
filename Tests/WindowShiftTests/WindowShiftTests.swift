import AppKit
import Carbon
import XCTest
@testable import WindowShift

final class WindowShiftTests: XCTestCase {
    func testHalfAndThirdLayoutsWithZeroGap() {
        let screen = CGRect(x: 0, y: 25, width: 1920, height: 1055)
        let window = CGRect(x: 200, y: 200, width: 800, height: 600)

        XCTAssertEqual(Layout.left.frame(in: screen, window: window, cycle: 0), CGRect(x: 0, y: 25, width: 960, height: 1055))
        XCTAssertEqual(Layout.right.frame(in: screen, window: window, cycle: 0), CGRect(x: 960, y: 25, width: 960, height: 1055))
        XCTAssertEqual(Layout.left.frame(in: screen, window: window, cycle: 1), CGRect(x: 0, y: 25, width: 640, height: 1055))
        XCTAssertEqual(Layout.left.frame(in: screen, window: window, cycle: 2), CGRect(x: 0, y: 25, width: 1280, height: 1055))
        XCTAssertEqual(Layout.maximize.frame(in: screen, window: window), screen)
    }

    func testGapSpacingBetweenAdjacentPanes() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let window = CGRect(x: 100, y: 100, width: 500, height: 400)
        let gap: CGFloat = 10

        let left = Layout.left.frame(in: screen, window: window, gap: gap)
        let right = Layout.right.frame(in: screen, window: window, gap: gap)
        XCTAssertEqual(left.minX, 10)
        XCTAssertEqual(left.minY, 10)
        XCTAssertEqual(right.maxX, 990)
        XCTAssertEqual(right.minX - left.maxX, 10, "Inner gap between halves should equal gapSize")

        let maxFrame = Layout.maximize.frame(in: screen, window: window, gap: gap)
        XCTAssertEqual(maxFrame, CGRect(x: 10, y: 10, width: 980, height: 780))
    }

    func testNegativeDisplayCoordinatesAndClamping() {
        let secondary = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let targetRight = Layout.right.frame(in: secondary, window: CGRect(x: -1000, y: 100, width: 600, height: 500))
        XCTAssertEqual(targetRight, CGRect(x: -720, y: 0, width: 720, height: 900))

        // Window whose minimum width (900) exceeds targetRight (720) must clamp left to stay on-screen.
        let oversizedActual = CGRect(x: -720, y: 0, width: 900, height: 900)
        let clamped = Layout.clamp(oversizedActual, target: targetRight, within: secondary)
        XCTAssertEqual(clamped, CGPoint(x: -900, y: 0))

        // Window wider than the entire display anchors at bounds.minX instead of going past left edge.
        let hugeActual = CGRect(x: -720, y: 0, width: 1800, height: 1100)
        XCTAssertEqual(Layout.clamp(hugeActual, target: targetRight, within: secondary), CGPoint(x: -1440, y: 0))
    }

    func testChordAndShortcutParsing() {
        XCTAssertEqual(Chord.parse("opt+cmd"), .optionCommand)
        XCTAssertEqual(Chord.parse("cmd+alt"), .optionCommand)
        XCTAssertEqual(Chord.parse("⌥⌘"), .optionCommand)
        XCTAssertEqual(Chord.parse("shift+cmd"), .shiftCommand)
        XCTAssertEqual(Chord.parse("ctrl+opt+shift"), .controlOptionShift)
        XCTAssertNil(Chord.parse("invalid+cmd"))

        let left = Shortcuts.Binding.parse("opt+cmd+h")
        XCTAssertEqual(left?.flags, [.option, .command])
        XCTAssertNotNil(left?.configString)

        let ret = Shortcuts.Binding.parse("shift+opt+cmd+return")
        XCTAssertEqual(ret?.key, UInt32(kVK_Return))
        XCTAssertEqual(ret?.flags, [.shift, .option, .command])

        let del = Shortcuts.Binding.parse("opt+cmd+delete")
        XCTAssertEqual(del?.key, UInt32(kVK_Delete))

        let plus = Shortcuts.Binding.parse("opt+cmd++")
        XCTAssertEqual(plus?.key, UInt32(kVK_ANSI_Equal))

        XCTAssertNil(Shortcuts.Binding.parse("h")) // missing modifiers
        XCTAssertNil(Shortcuts.Binding.parse("opt+cmd+notakey"))
    }

    func testConfigStoreSymlinkHotReloadAndValidation() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ws-xctest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let repoDir = tmp.appendingPathComponent("dotfiles/windowshift", isDirectory: true)
        let cfgDir = tmp.appendingPathComponent(".config/windowshift", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cfgDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cfgDir, withDestinationURL: repoDir)

        let repoFile = repoDir.appendingPathComponent("config.json")
        let cfgFile = cfgDir.appendingPathComponent("config.json")

        let initialJSON = """
        {
          "moveChord": "opt+cmd",
          "resizeChord": "shift+cmd",
          "gapSize": 8,
          "hideMenubarIcon": true,
          "edgeSnapping": true,
          "smartResize": false,
          "focusWindow": false,
          "snapToNearbyWindows": true,
          "ignoredApps": ["com.parallels.desktop.console"],
          "ignoredGestureApps": ["com.pointum.hazeover"],
          "ignoredShortcutApps": ["com.microsoft.rdc.macos"],
          "shortcuts": {
            "leftHalf": "opt+cmd+h",
            "maximize": "opt+cmd+return",
            "centerThird": null
          }
        }
        """
        try initialJSON.data(using: .utf8)!.write(to: repoFile)

        let suiteName = "ws-xctest-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = ConfigStore(fileURL: cfgFile, defaults: suite)
        XCTAssertTrue(store.hasFile)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.moveChord, .optionCommand)
        XCTAssertEqual(store.resizeChord, .shiftCommand)
        XCTAssertEqual(store.gapSize, 8)
        XCTAssertTrue(store.hideMenubarIcon)
        XCTAssertTrue(store.ignoresGestures(for: "com.parallels.desktop.console"))
        XCTAssertTrue(store.ignoresShortcuts(for: "com.parallels.desktop.console"))
        XCTAssertTrue(store.ignoresGestures(for: "com.pointum.hazeover"))
        XCTAssertFalse(store.ignoresShortcuts(for: "com.pointum.hazeover"))
        XCTAssertTrue(store.ignoresShortcuts(for: "com.microsoft.rdc.macos"))
        XCTAssertNil(store.shortcutBinding(for: .middleThird))

        var reloads = 0
        store.onChange = { reloads += 1 }
        store.startWatching()

        // Atomic rename save into dotfiles target triggers reload
        let updated = initialJSON.replacingOccurrences(of: "\"opt+cmd+h\"", with: "\"ctrl+opt+left\"")
        let staging = repoDir.appendingPathComponent(".config.json.tmp")
        try updated.data(using: .utf8)!.write(to: staging)
        _ = try FileManager.default.replaceItemAt(repoFile, withItemAt: staging)

        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(store.shortcutBinding(for: .left)?.key, UInt32(kVK_LeftArrow))

        // Invalid shortcut key reports error while keeping previous valid binding
        let invalidKey = initialJSON.replacingOccurrences(of: "\"leftHalf\"", with: "\"notARealLayout\"")
        try invalidKey.data(using: .utf8)!.write(to: repoFile, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(store.shortcutBinding(for: .left)?.key, UInt32(kVK_LeftArrow))

        // Recovering valid config clears error
        try initialJSON.data(using: .utf8)!.write(to: repoFile, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertNil(store.lastError)
        XCTAssertEqual(reloads, 2)

        // Setting a shortcut via API writes back cleanly through symlink
        store.setShortcut(Shortcuts.Binding(key: UInt32(kVK_ANSI_M), flags: [.option, .command]), for: .maximize)
        let attrs = try FileManager.default.attributesOfItem(atPath: cfgDir.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(store.shortcutBinding(for: .maximize)?.key, UInt32(kVK_ANSI_M))
    }
}

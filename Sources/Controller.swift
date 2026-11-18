import AppKit
import ApplicationServices

enum Chord: String, CaseIterable {
    case controlCommand = "⌃⌘"
    case controlCommandShift = "⌃⇧⌘"
    case optionCommand = "⌥⌘"
    case shiftCommand = "⇧⌘"
    case optionCommandShift = "⌥⇧⌘"
    case controlOption = "⌃⌥"
    case controlOptionShift = "⌃⌥⇧"

    static let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]

    var flags: CGEventFlags {
        switch self {
        case .controlCommand: return [.maskControl, .maskCommand]
        case .controlCommandShift: return [.maskControl, .maskCommand, .maskShift]
        case .shiftCommand: return [.maskShift, .maskCommand]
        case .optionCommand: return [.maskAlternate, .maskCommand]
        case .optionCommandShift: return [.maskAlternate, .maskCommand, .maskShift]
        case .controlOption: return [.maskControl, .maskAlternate]
        case .controlOptionShift: return [.maskControl, .maskAlternate, .maskShift]
        }
    }
}

final class Controller {
    private enum Mode { case move, resize }

    private struct Gesture {
        let mode: Mode
        let window: AXUIElement
        let start: CGPoint
        let frame: CGRect
        let neighbors: [CGRect]
    }

    private struct Drag {
        let window: AXUIElement
        let frame: CGRect
        var moved = false
    }

    private struct Placement {
        let window: AXUIElement
        var original: CGRect
        var applied: CGRect
        var layout: Layout
        var cycle: Int
    }

    private let preferences = UserDefaults.standard
    var moveChord: Chord {
        get { Chord(rawValue: preferences.string(forKey: "moveChord") ?? "") ?? .controlCommand }
        set { preferences.set(newValue.rawValue, forKey: "moveChord") }
    }
    var resizeChord: Chord {
        get { Chord(rawValue: preferences.string(forKey: "resizeChord") ?? "") ?? .controlCommandShift }
        set { preferences.set(newValue.rawValue, forKey: "resizeChord") }
    }
    var smartResize: Bool {
        get { preferences.object(forKey: "smartResize") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "smartResize") }
    }
    var focusWindow: Bool {
        get { preferences.bool(forKey: "focusWindow") }
        set { preferences.set(newValue, forKey: "focusWindow") }
    }
    var snapToNearbyWindows: Bool {
        get { preferences.bool(forKey: "snapToNearbyWindows") }
        set { preferences.set(newValue, forKey: "snapToNearbyWindows") }
    }
    var edgeSnapping: Bool {
        get { preferences.object(forKey: "edgeSnapping") as? Bool ?? true }
        set { preferences.set(newValue, forKey: "edgeSnapping"); if !newValue { preview.hide() } }
    }

    private func acceptsGesture(on window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return true }
        return !(preferences.stringArray(forKey: "ignoredGestureApps") ?? []).contains(bundleID)
    }

    private let preview = SnapPreview()
    private var gesture: Gesture?
    private var drag: Drag?
    private var placements: [Placement] = []
    private var mode: Mode?
    private var anchor: CGPoint?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: (CGEventType, CGPoint, CGEventFlags)?
    private var updateScheduled = false
    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if isRunning { return true }
        let types: [CGEventType] = [.flagsChanged, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, info in
            if let info {
                let controller = Unmanaged<Controller>.fromOpaque(info).takeUnretainedValue()
                controller.receive(type, at: event.location, flags: event.flags)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        reset()
    }

    private func reset() {
        pending = nil
        mode = nil
        anchor = nil
        gesture = nil
        drag = nil
        preview.hide()
    }

    private func receive(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.reset() }
            return
        }
        let modifiers = flags.intersection(Chord.modifiers)
        DispatchQueue.main.async { [weak self] in self?.enqueue(type, at: point, modifiers: modifiers) }
    }

    private func enqueue(_ type: CGEventType, at point: CGPoint, modifiers: CGEventFlags) {
        guard isRunning else { return }
        switch type {
        case .mouseMoved, .leftMouseDragged:
            if type == .leftMouseDragged, drag == nil { return }
            if type == .mouseMoved, mode == nil, modifiers != moveChord.flags, modifiers != resizeChord.flags { return }
            pending = (type, point, modifiers)
            if !updateScheduled {
                updateScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 90) { [weak self] in
                    self?.updateScheduled = false
                    self?.flush()
                }
            }
        default:
            flush()
            handle(type, at: point, modifiers: modifiers)
        }
    }

    private func flush() {
        guard let (type, point, modifiers) = pending else { return }
        pending = nil
        handle(type, at: point, modifiers: modifiers)
    }

    private func handle(_ type: CGEventType, at point: CGPoint, modifiers: CGEventFlags) {
        switch type {
        case .flagsChanged:
            updateMode(at: point, modifiers: modifiers)
        case .mouseMoved:
            updateMode(at: point, modifiers: modifiers)
            updateGesture(at: point)
        case .leftMouseDown:
            reset()
            guard edgeSnapping, let window = Windows.at(point), let frame = Windows.frame(window),
                  frame.contains(point), point.y <= frame.minY + 64,
                  Windows.prepare(window, resizing: true) else { return }
            drag = Drag(window: window, frame: frame)
        case .leftMouseDragged:
            guard var drag else { return }
            if !drag.moved {
                guard let current = Windows.frame(drag.window), current.origin != drag.frame.origin,
                      current.size == drag.frame.size else { return }
                drag.moved = true
                self.drag = drag
            }
            showSnap(at: point, for: drag.frame)
        case .leftMouseUp:
            if let drag, drag.moved { commitSnap(at: point, window: drag.window, original: drag.frame) }
            reset()
        default:
            break
        }
    }

    private func updateMode(at point: CGPoint, modifiers: CGEventFlags) {
        guard drag == nil else { return }
        let next: Mode? = modifiers == moveChord.flags ? .move : modifiers == resizeChord.flags ? .resize : nil
        guard next != mode else { return }
        if next == nil, let gesture, gesture.mode == .move {
            commitSnap(at: point, window: gesture.window, original: gesture.frame)
        }
        preview.hide()
        gesture = nil
        mode = next
        anchor = next == nil ? nil : point
    }

    private func updateGesture(at point: CGPoint) {
        guard let mode, let start = anchor else { return }
        if gesture == nil {
            guard hypot(point.x - start.x, point.y - start.y) >= 2 else { return }
            let target = Windows.at(start) ?? Windows.at(point)
            // Disarm until the chord changes if there is no eligible window at gesture start.
            guard let window = target, acceptsGesture(on: window), Windows.prepare(window, resizing: mode == .resize),
                  let frame = Windows.frame(window) else { anchor = nil; return }
            if focusWindow { Windows.focus(window) }
            let neighbors = mode == .move && snapToNearbyWindows ? Windows.nearbyFrames(excluding: window, frame: frame) : []
            gesture = Gesture(mode: mode, window: window, start: start, frame: frame, neighbors: neighbors)
        }
        guard let gesture else { return }
        let delta = CGPoint(x: point.x - gesture.start.x, y: point.y - gesture.start.y)
        switch mode {
        case .move:
            let frame = gesture.frame.offsetBy(dx: delta.x, dy: delta.y)
            let origin = Layout.align(frame, to: gesture.neighbors)
            Windows.move(gesture.window, to: origin)
            showSnap(at: point, for: gesture.frame)
        case .resize:
            let proposed = Layout.resize(gesture.frame, from: gesture.start, by: delta, smart: smartResize)
            guard Windows.resize(gesture.window, to: proposed.size), smartResize,
                  gesture.start.x < gesture.frame.midX || gesture.start.y < gesture.frame.midY,
                  let actual = Windows.frame(gesture.window) else { return }
            let x = gesture.start.x < gesture.frame.midX ? gesture.frame.maxX - actual.width : gesture.frame.minX
            let y = gesture.start.y < gesture.frame.midY ? gesture.frame.maxY - actual.height : gesture.frame.minY
            Windows.move(gesture.window, to: CGPoint(x: x, y: y))
        }
    }

    private func snapTarget(_ point: CGPoint) -> (Layout, NSScreen)? {
        guard edgeSnapping, let screen = NSScreen.containing(point),
              let layout = Layout.snap(at: point, in: screen.quartzFrame) else { return nil }
        return (layout, screen)
    }

    private func showSnap(at point: CGPoint, for original: CGRect) {
        guard let (layout, screen) = snapTarget(point) else { preview.hide(); return }
        preview.show(layout.frame(in: screen.quartzVisibleFrame, window: original))
    }

    private func commitSnap(at point: CGPoint, window: AXUIElement, original: CGRect) {
        guard let (layout, screen) = snapTarget(point), Windows.prepare(window, resizing: true) else { return }
        place(layout, window: window, target: layout.frame(in: screen.quartzVisibleFrame, window: original),
              previous: original, cycle: 0)
    }

    func perform(_ layout: Layout, on window: AXUIElement? = nil) {
        let target = window ?? Windows.focused()
        guard let target, let current = Windows.frame(target), let screen = NSScreen.best(for: current) else { return }
        let resizing = layout != .center
        guard Windows.prepare(target, resizing: resizing) else { return }
        let history = placements.first { CFEqual($0.window, target) }
        if layout == .restore {
            guard let history else { return }
            Windows.apply(history.original, to: target)
            placements.removeAll { CFEqual($0.window, target) }
            return
        }
        let screens = NSScreen.screens
        if layout == .nextDisplay || layout == .previousDisplay {
            guard screens.count > 1, let index = screens.firstIndex(of: screen) else { return }
            let step = layout == .nextDisplay ? 1 : -1
            let destination = screens[(index + step + screens.count) % screens.count].quartzVisibleFrame
            let source = screen.quartzVisibleFrame
            let width = min(current.width, destination.width)
            let height = min(current.height, destination.height)
            let fractionX = min(1, max(0, (current.minX - source.minX) / max(1, source.width - current.width)))
            let fractionY = min(1, max(0, (current.minY - source.minY) / max(1, source.height - current.height)))
            let next = CGRect(x: destination.minX + fractionX * (destination.width - width),
                              y: destination.minY + fractionY * (destination.height - height),
                              width: width, height: height)
            place(layout, window: target, target: next, previous: current, cycle: 0)
            return
        }
        var cycle = 0
        if layout.cycles, let history, history.layout == layout, close(current, history.applied) {
            cycle = (history.cycle + 1) % 3
        }
        let frame = layout.frame(in: screen.quartzVisibleFrame, window: current, cycle: cycle)
        place(layout, window: target, target: frame, previous: current, cycle: cycle)
    }

    private func place(_ layout: Layout, window: AXUIElement, target: CGRect, previous: CGRect, cycle: Int) {
        let history = placements.first { CFEqual($0.window, window) }
        let original = history.map { close(previous, $0.applied) ? $0.original : previous } ?? previous
        if layout == .center { Windows.move(window, to: target.origin) }
        else { Windows.apply(target, to: window) }
        guard let applied = Windows.frame(window) else { return }
        placements.removeAll { CFEqual($0.window, window) }
        placements.append(Placement(window: window, original: original, applied: applied, layout: layout, cycle: cycle))
        if placements.count > 64 { placements.removeFirst() }
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
            && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}

private final class SnapPreview {
    private var panel: NSPanel?
    private var shownFrame: CGRect?

    func show(_ quartzFrame: CGRect) {
        if shownFrame == quartzFrame { return }
        shownFrame = quartzFrame
        let frame = NSScreen.flipped(quartzFrame).insetBy(dx: 4, dy: 4)
        if panel == nil {
            let newPanel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.ignoresMouseEvents = true
            newPanel.level = .floating
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let fill = NSView()
            fill.wantsLayer = true
            fill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.23).cgColor
            fill.layer?.borderColor = NSColor.controlAccentColor.cgColor
            fill.layer?.borderWidth = 2
            fill.layer?.cornerRadius = 10
            newPanel.contentView = fill
            panel = newPanel
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    func hide() {
        guard shownFrame != nil else { return }
        shownFrame = nil
        panel?.orderOut(nil)
    }
}

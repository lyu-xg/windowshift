import AppKit
import ApplicationServices

enum Windows {
    static let system: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(element, 0.08)
        return element
    }()

    static func attribute<T>(_ element: AXUIElement, _ name: String, as _: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        let value: CFTypeRef? = attribute(element, name)
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func at(_ point: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        let role: String? = attribute(hit, kAXRoleAttribute)
        if role == kAXWindowRole { return hit }
        return element(hit, kAXWindowAttribute)
    }

    static func focused() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return self.element(element, kAXFocusedWindowAttribute)
    }

    static func prepare(_ window: AXUIElement, resizing: Bool) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        _ = AXUIElementSetMessagingTimeout(window, 0.08)
        let fullscreen: Bool? = attribute(window, "AXFullScreen")
        return fullscreen != true && writable(window, kAXPositionAttribute)
            && (!resizing || writable(window, kAXSizeAttribute))
    }

    static func writable(_ window: AXUIElement, _ name: String) -> Bool {
        var writable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, name as CFString, &writable) == .success
            && writable.boolValue
    }

    static func nearbyFrames(excluding window: AXUIElement, frame: CGRect) -> [CGRect] {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 64, height >= 48 else { return nil }
            let candidate = CGRect(x: x, y: y, width: width, height: height)
            let owner = info[kCGWindowOwnerPID as String] as? pid_t
            guard owner != pid || !candidate.insetBy(dx: -2, dy: -2).contains(frame)
                || !frame.insetBy(dx: -2, dy: -2).contains(candidate) else { return nil }
            return candidate
        }
    }

    static func focus(_ window: AXUIElement) {
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = axValue(window, kAXPositionAttribute),
              let s = axValue(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &origin), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ window: AXUIElement, _ name: String) -> AXValue? {
        let value: CFTypeRef? = attribute(window, name)
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    @discardableResult
    static func move(_ window: AXUIElement, to point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    static func resize(_ window: AXUIElement, to size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    static func apply(_ frame: CGRect, to window: AXUIElement) {
        move(window, to: frame.origin)
        resize(window, to: frame.size)
        move(window, to: frame.origin)
    }
}

extension NSScreen {
    static var quartzOriginY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func flipped(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: quartzOriginY - frame.maxY, width: frame.width, height: frame.height)
    }

    var quartzFrame: CGRect { Self.flipped(frame) }
    var quartzVisibleFrame: CGRect { Self.flipped(visibleFrame) }

    static func containing(_ point: CGPoint) -> NSScreen? {
        screens.first {
            let f = $0.quartzFrame
            return point.x >= f.minX && point.x <= f.maxX && point.y >= f.minY && point.y <= f.maxY
        }
    }

    static func best(for frame: CGRect) -> NSScreen? {
        func overlap(_ screen: NSScreen) -> CGFloat {
            let intersection = screen.quartzFrame.intersection(frame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let best = screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 else { return main }
        return best
    }
}

import CoreGraphics

enum Layout: String, CaseIterable {
    case left = "Left half", right = "Right half"
    case top = "Top half", bottom = "Bottom half"
    case topLeft = "Top left", topRight = "Top right"
    case bottomLeft = "Bottom left", bottomRight = "Bottom right"
    case firstThird = "Left third", middleThird = "Middle third", lastThird = "Right third"
    case centerHalf = "Center half", maximizeHeight = "Maximize height"
    case almostMaximize = "Almost maximize", larger = "Larger", smaller = "Smaller"
    case maximize = "Maximize", center = "Center", restore = "Restore"
    case nextDisplay = "Next display", previousDisplay = "Previous display"

    func frame(in screen: CGRect, window: CGRect, cycle: Int = 0) -> CGRect {
        let fraction: CGFloat = [0.5, 1.0 / 3, 2.0 / 3][cycle % 3]
        func region(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            let left = (screen.minX + screen.width * x).rounded()
            let top = (screen.minY + screen.height * y).rounded()
            let right = (screen.minX + screen.width * (x + w)).rounded()
            let bottom = (screen.minY + screen.height * (y + h)).rounded()
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        switch self {
        case .left: return region(0, 0, fraction, 1)
        case .right: return region(1 - fraction, 0, fraction, 1)
        case .top: return region(0, 0, 1, fraction)
        case .bottom: return region(0, 1 - fraction, 1, fraction)
        case .topLeft: return region(0, 0, 0.5, 0.5)
        case .topRight: return region(0.5, 0, 0.5, 0.5)
        case .bottomLeft: return region(0, 0.5, 0.5, 0.5)
        case .bottomRight: return region(0.5, 0.5, 0.5, 0.5)
        case .firstThird: return region(0, 0, 1.0 / 3, 1)
        case .middleThird: return region(1.0 / 3, 0, 1.0 / 3, 1)
        case .lastThird: return region(2.0 / 3, 0, 1.0 / 3, 1)
        case .center:
            return CGRect(x: screen.midX - window.width / 2, y: screen.midY - window.height / 2,
                          width: window.width, height: window.height)
        case .centerHalf: return region(0.25, 0, 0.5, 1)
        case .maximizeHeight:
            let width = min(window.width, screen.width)
            return CGRect(x: min(max(window.minX, screen.minX), screen.maxX - width),
                          y: screen.minY, width: width, height: screen.height)
        case .almostMaximize: return region(0.05, 0.05, 0.9, 0.9)
        case .larger, .smaller:
            let step: CGFloat = self == .larger ? 0.1 : -0.1
            let width = min(screen.width, max(64, window.width + step * screen.width))
            let height = min(screen.height, max(48, window.height + step * screen.height))
            return CGRect(x: min(max(window.midX - width / 2, screen.minX), screen.maxX - width),
                          y: min(max(window.midY - height / 2, screen.minY), screen.maxY - height),
                          width: width, height: height)
        case .maximize: return screen
        case .restore, .nextDisplay, .previousDisplay: return window
        }
    }

    var cycles: Bool {
        [.left, .right, .top, .bottom].contains(self)
    }

    static func snap(at point: CGPoint, in screen: CGRect, inset: CGFloat = 10) -> Layout? {
        let nearTop = point.y <= screen.minY + inset
        let nearBottom = point.y >= screen.maxY - inset
        if point.x <= screen.minX + inset {
            if nearTop { return .topLeft }
            if nearBottom { return .bottomLeft }
            return .left
        }
        if point.x >= screen.maxX - inset {
            if nearTop { return .topRight }
            if nearBottom { return .bottomRight }
            return .right
        }
        if nearTop { return .maximize }
        if nearBottom {
            let x = (point.x - screen.minX) / screen.width
            if x < 1.0 / 3 { return .firstThird }
            if x < 2.0 / 3 { return .middleThird }
            return .lastThird
        }
        return nil
    }

    static func resize(_ window: CGRect, from point: CGPoint, by delta: CGPoint, smart: Bool) -> CGRect {
        let left = smart && point.x < window.midX
        let top = smart && point.y < window.midY
        let width = max(64, window.width + (left ? -delta.x : delta.x))
        let height = max(48, window.height + (top ? -delta.y : delta.y))
        return CGRect(x: left ? window.maxX - width : window.minX,
                      y: top ? window.maxY - height : window.minY,
                      width: width, height: height)
    }

    static func align(_ frame: CGRect, to neighbors: [CGRect], threshold: CGFloat = 8) -> CGPoint {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var closestX = threshold
        var closestY = threshold
        for neighbor in neighbors {
            if frame.minY <= neighbor.maxY + threshold && frame.maxY >= neighbor.minY - threshold {
                for x in [frame.minX, frame.maxX] {
                    for edge in [neighbor.minX, neighbor.maxX] where abs(edge - x) < closestX {
                        dx = edge - x
                        closestX = abs(dx)
                    }
                }
            }
            if frame.minX <= neighbor.maxX + threshold && frame.maxX >= neighbor.minX - threshold {
                for y in [frame.minY, frame.maxY] {
                    for edge in [neighbor.minY, neighbor.maxY] where abs(edge - y) < closestY {
                        dy = edge - y
                        closestY = abs(dy)
                    }
                }
            }
        }
        return CGPoint(x: frame.minX + dx, y: frame.minY + dy)
    }
}

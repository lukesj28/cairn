import CoreGraphics

public enum SnapGrid {
    public static let columns = 12
    public static let rows = 8
    public static let magnetism: CGFloat = 0.02

    public static func snapMove(_ rect: CGRect, neighbours: [CGRect]) -> CGRect {
        let x = snapLeadingEdge(min: rect.minX, max: rect.maxX, length: rect.width,
                                divisions: columns, targets: targets(neighbours, vertical: false))
        let y = snapLeadingEdge(min: rect.minY, max: rect.maxY, length: rect.height,
                                divisions: rows, targets: targets(neighbours, vertical: true))
        return ScreenGeometry.clamp(CGRect(x: x, y: y, width: rect.width, height: rect.height))
    }

    public static func snapResize(_ rect: CGRect, neighbours: [CGRect]) -> CGRect {
        snapResize(rect: rect, original: rect, neighbours: neighbours)
    }

    public static func snapResize(rect: CGRect, original: CGRect, neighbours: [CGRect]) -> CGRect {
        guard isFinite(rect) else { return ScreenGeometry.clamp(rect) }
        let orig = isFinite(original) ? original : rect
        let x = snapResizeAxis(min: rect.minX, max: rect.maxX, originalMin: orig.minX, originalMax: orig.maxX,
                               divisions: columns, targets: targets(neighbours, vertical: false))
        let y = snapResizeAxis(min: rect.minY, max: rect.maxY, originalMin: orig.minY, originalMax: orig.maxY,
                               divisions: rows, targets: targets(neighbours, vertical: true))
        return CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
    }

    public static func clampResize(rect: CGRect, original: CGRect) -> CGRect {
        guard isFinite(rect) else { return ScreenGeometry.clamp(rect) }
        let orig = isFinite(original) ? original : rect
        let xIsLeading = abs(rect.minX - orig.minX) > 0.001
        let yIsLeading = abs(rect.minY - orig.minY) > 0.001
        let x = resizeAxis(edge: xIsLeading ? rect.minX : rect.maxX, isLeading: xIsLeading,
                           originalMin: orig.minX, originalMax: orig.maxX, minLength: 1 / CGFloat(columns))
        let y = resizeAxis(edge: yIsLeading ? rect.minY : rect.maxY, isLeading: yIsLeading,
                           originalMin: orig.minY, originalMax: orig.maxY, minLength: 1 / CGFloat(rows))
        return CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
    }

    private static func snapResizeAxis(min: CGFloat, max: CGFloat, originalMin: CGFloat, originalMax: CGFloat,
                                       divisions: Int, targets: [CGFloat]) -> (origin: CGFloat, length: CGFloat) {
        let isLeading = abs(min - originalMin) > 0.001
        let rawEdge = isLeading ? min : max
        let edge = magnet(rawEdge, to: targets) ?? quantise(rawEdge, divisions: divisions)
        return resizeAxis(edge: edge, isLeading: isLeading,
                          originalMin: originalMin, originalMax: originalMax,
                          minLength: 1 / CGFloat(divisions))
    }

    private static func resizeAxis(edge: CGFloat, isLeading: Bool,
                                   originalMin: CGFloat, originalMax: CGFloat,
                                   minLength: CGFloat) -> (origin: CGFloat, length: CGFloat) {
        if isLeading {
            let clampedEdge = Swift.max(0, Swift.min(originalMax - minLength, edge))
            return (origin: clampedEdge, length: originalMax - clampedEdge)
        } else {
            let clampedEdge = Swift.min(1.0, Swift.max(originalMin + minLength, edge))
            return (origin: originalMin, length: clampedEdge - originalMin)
        }
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite
    }

    public static func quantise(_ value: CGFloat, divisions: Int) -> CGFloat {
        (value * CGFloat(divisions)).rounded() / CGFloat(divisions)
    }

    public static func targets(_ neighbours: [CGRect], vertical: Bool) -> [CGFloat] {
        var values: Set<CGFloat> = [0, 1]
        for n in neighbours {
            values.insert(vertical ? n.minY : n.minX)
            values.insert(vertical ? n.maxY : n.maxX)
        }
        return values.sorted()
    }

    public static func magnet(_ value: CGFloat, to targets: [CGFloat]) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = CGFloat.infinity
        for t in targets {
            let d = abs(t - value)
            guard d <= magnetism else { continue }
            if d < bestDistance || (d == bestDistance && t < (best ?? .infinity)) {
                bestDistance = d
                best = t
            }
        }
        return best
    }

    private static func snapLeadingEdge(min minValue: CGFloat, max maxValue: CGFloat, length: CGFloat,
                                        divisions: Int, targets: [CGFloat]) -> CGFloat {
        let lead = magnet(minValue, to: targets)
        let trail = magnet(maxValue, to: targets).map { $0 - length }

        switch (lead, trail) {
        case let (l?, t?):
            return abs(t - minValue) < abs(l - minValue) ? t : l
        case let (l?, nil):
            return l
        case let (nil, t?):
            return t
        case (nil, nil):
            return quantise(minValue, divisions: divisions)
        }
    }
}

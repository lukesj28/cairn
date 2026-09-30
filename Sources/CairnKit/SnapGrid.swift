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
        let x = snapResizeAxis(min: rect.minX, max: rect.maxX, originalMin: original.minX,
                               divisions: columns, targets: targets(neighbours, vertical: false))
        let y = snapResizeAxis(min: rect.minY, max: rect.maxY, originalMin: original.minY,
                               divisions: rows, targets: targets(neighbours, vertical: true))
        return ScreenGeometry.clamp(CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length))
    }

    private static func snapResizeAxis(min: CGFloat, max: CGFloat, originalMin: CGFloat,
                                       divisions: Int, targets: [CGFloat]) -> (origin: CGFloat, length: CGFloat) {
        let minLength = 1 / CGFloat(divisions)
        if abs(min - originalMin) > 0.001 {
            let edge = magnet(min, to: targets) ?? quantise(min, divisions: divisions)
            let length = Swift.max(minLength, max - edge)
            return (origin: max - length, length: length)
        } else {
            let edge = magnet(max, to: targets) ?? quantise(max, divisions: divisions)
            let length = Swift.max(minLength, edge - min)
            return (origin: min, length: length)
        }
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

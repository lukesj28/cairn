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
        let edgeX = magnet(rect.maxX, to: targets(neighbours, vertical: false)) ?? quantise(rect.maxX, divisions: columns)
        let width = max(1 / CGFloat(columns), edgeX - rect.minX)

        let edgeY = magnet(rect.maxY, to: targets(neighbours, vertical: true)) ?? quantise(rect.maxY, divisions: rows)
        let height = max(1 / CGFloat(rows), edgeY - rect.minY)

        return ScreenGeometry.clamp(CGRect(x: rect.minX, y: rect.minY, width: width, height: height))
    }

    static func quantise(_ value: CGFloat, divisions: Int) -> CGFloat {
        (value * CGFloat(divisions)).rounded() / CGFloat(divisions)
    }

    static func targets(_ neighbours: [CGRect], vertical: Bool) -> [CGFloat] {
        var values: Set<CGFloat> = [0, 1]
        for n in neighbours {
            values.insert(vertical ? n.minY : n.minX)
            values.insert(vertical ? n.maxY : n.maxX)
        }
        return values.sorted()
    }

    static func magnet(_ value: CGFloat, to targets: [CGFloat]) -> CGFloat? {
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

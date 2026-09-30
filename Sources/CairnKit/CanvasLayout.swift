import CoreGraphics

public enum CanvasLayout {
    public static func rects(in size: CGSize, aspects: [CGFloat], spacing: CGFloat) -> [CGRect] {
        guard !aspects.isEmpty,
              size.width.isFinite, size.width > 0,
              size.height.isFinite, size.height > 0,
              aspects.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return []
        }

        let primaryAspect = aspects[0]
        let inverseSum = CGFloat(aspects.count) / primaryAspect
        let totalSpacing = spacing * CGFloat(aspects.count - 1)
        let usableHeight = max(0, size.height - totalSpacing)
        let width = max(0, min(size.width, usableHeight / inverseSum))
        let height = width / primaryAspect
        let x = (size.width - width) / 2

        var y: CGFloat = 0
        return (0..<aspects.count).map { _ in
            let rect = CGRect(x: x, y: y, width: width, height: height)
            y += height + spacing
            return rect
        }
    }
}

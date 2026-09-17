import CoreGraphics

public enum CanvasLayout {
    public static func rects(in size: CGSize, aspects: [CGFloat], spacing: CGFloat) -> [CGRect] {
        guard !aspects.isEmpty,
              size.width.isFinite, size.width > 0,
              size.height.isFinite, size.height > 0,
              aspects.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return []
        }

        let inverseSum = aspects.reduce(0) { $0 + 1 / $1 }
        let usableHeight = size.height - spacing * CGFloat(aspects.count - 1)
        let width = max(0, min(size.width, usableHeight / inverseSum))
        let x = (size.width - width) / 2

        var y: CGFloat = 0
        return aspects.map { aspect in
            let height = width / aspect
            let rect = CGRect(x: x, y: y, width: width, height: height)
            y += height + spacing
            return rect
        }
    }
}

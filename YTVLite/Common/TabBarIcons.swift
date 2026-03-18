import UIKit

enum TabBarIcons {

    static func home(size: CGFloat = 24) -> UIImage {
        return draw(size: size) { ctx, s in
            let mid = s / 2
            // Roof
            let roof = UIBezierPath()
            roof.move(to: CGPoint(x: mid, y: s * 0.08))
            roof.addLine(to: CGPoint(x: s * 0.95, y: s * 0.52))
            roof.addLine(to: CGPoint(x: s * 0.78, y: s * 0.52))
            roof.addLine(to: CGPoint(x: s * 0.78, y: s * 0.94))
            roof.addLine(to: CGPoint(x: s * 0.22, y: s * 0.94))
            roof.addLine(to: CGPoint(x: s * 0.22, y: s * 0.52))
            roof.addLine(to: CGPoint(x: s * 0.05, y: s * 0.52))
            roof.close()
            ctx.addPath(roof.cgPath)
            ctx.fillPath()
            // Door
            ctx.setFillColor(UIColor.clear.cgColor)
            ctx.setBlendMode(.clear)
            let door = CGRect(x: s * 0.37, y: s * 0.62, width: s * 0.26, height: s * 0.32)
            ctx.fill(door)
        }
    }

    static func subscriptions(size: CGFloat = 24) -> UIImage {
        return draw(size: size) { ctx, s in
            let lineH: CGFloat = s * 0.12
            let gap: CGFloat = s * 0.14
            let thumbW: CGFloat = s * 0.35
            let startY: CGFloat = s * 0.1
            for i in 0..<3 {
                let y = startY + CGFloat(i) * (lineH + gap)
                // Thumbnail rect
                let thumb = CGRect(x: s * 0.04, y: y, width: thumbW, height: lineH + gap * 0.6)
                ctx.fill(thumb)
                // Play triangle inside thumb
                ctx.setFillColor(UIColor(white: 0.3, alpha: 1).cgColor)
                let tx = thumb.midX - s * 0.04
                let ty = thumb.midY
                let tri = UIBezierPath()
                tri.move(to: CGPoint(x: tx, y: ty - s * 0.06))
                tri.addLine(to: CGPoint(x: tx + s * 0.1, y: ty))
                tri.addLine(to: CGPoint(x: tx, y: ty + s * 0.06))
                tri.close()
                ctx.addPath(tri.cgPath)
                ctx.fillPath()
                // Reset color
                ctx.setFillColor(UIColor.white.cgColor)
                // Text line
                let textRect = CGRect(x: thumbW + s * 0.1, y: y + s * 0.02,
                                      width: s * 0.5, height: lineH * 0.7)
                ctx.fill(textRect)
            }
        }
    }

    static func profile(size: CGFloat = 24) -> UIImage {
        return draw(size: size) { ctx, s in
            // Head circle
            ctx.fillEllipse(in: CGRect(x: s * 0.33, y: s * 0.06, width: s * 0.34, height: s * 0.34))
            // Shoulders — trapezoid with curved top
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: s))
            path.addLine(to: CGPoint(x: s, y: s))
            path.addLine(to: CGPoint(x: s * 0.85, y: s * 0.62))
            path.addQuadCurve(to: CGPoint(x: s * 0.15, y: s * 0.62),
                              controlPoint: CGPoint(x: s * 0.5, y: s * 0.38))
            path.close()
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
    }

    // MARK: - Private

    private static func draw(size: CGFloat, block: (CGContext, CGFloat) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            block(ctx.cgContext, size)
        }.withRenderingMode(.alwaysTemplate)
    }
}

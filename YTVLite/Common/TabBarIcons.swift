import UIKit

enum TabBarIcons {

    static func home(size: CGFloat = 24) -> UIImage {
        return draw(size: size) { ctx, s in
            let mid = s / 2
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
                let thumb = CGRect(x: s * 0.04, y: y, width: thumbW, height: lineH + gap * 0.6)
                ctx.fill(thumb)
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
                ctx.setFillColor(UIColor.white.cgColor)
                let textRect = CGRect(x: thumbW + s * 0.1, y: y + s * 0.02,
                                      width: s * 0.5, height: lineH * 0.7)
                ctx.fill(textRect)
            }
        }
    }

    static func library(size: CGFloat = 24) -> UIImage {
        return draw(size: size) { ctx, s in
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(s * 0.09)
            ctx.strokeEllipse(in: CGRect(x: s * 0.08, y: s * 0.08,
                                         width: s * 0.84, height: s * 0.84))
            ctx.setLineWidth(s * 0.08)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: s * 0.5, y: s * 0.5))
            ctx.addLine(to: CGPoint(x: s * 0.5, y: s * 0.24))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: s * 0.5, y: s * 0.5))
            ctx.addLine(to: CGPoint(x: s * 0.72, y: s * 0.62))
            ctx.strokePath()
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

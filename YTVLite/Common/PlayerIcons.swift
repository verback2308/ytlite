import UIKit

/// Player control icons drawn with UIBezierPath (iOS 12 compatible).
enum PlayerIcons {
    private struct CornerPoints {
        let corner: CGPoint
        let horizontal: CGPoint
        let vertical: CGPoint
    }

    static func play(color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: 44, height: 44)) { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 14, y: 10))
            path.addLine(to: CGPoint(x: 36, y: 22))
            path.addLine(to: CGPoint(x: 14, y: 34))
            path.close()
            color.setFill()
            path.fill()
        }
    }

    static func pause(color: UIColor = .white) -> UIImage {
        draw(size: CGSize(width: 44, height: 44)) { _ in
            color.setFill()
            let bar1 = CGRect(x: 12, y: 10, width: 7, height: 24)
            let bar2 = CGRect(x: 25, y: 10, width: 7, height: 24)
            UIBezierPath(roundedRect: bar1, cornerRadius: 2).fill()
            UIBezierPath(roundedRect: bar2, cornerRadius: 2).fill()
        }
    }

    static func rewind10() -> UIImage {
        playerIcon("icon_Gobackward_10", size: 36)
    }

    static func forward10() -> UIImage {
        playerIcon("icon_Goforward_10", size: 36)
    }

    static func settings() -> UIImage {
        playerIcon("icon_Gear", size: 26)
    }

    static func pip() -> UIImage {
        if #available(iOS 13.0, *),
           let img = UIImage(systemName: "pip.enter") {
            return img.withTintColor(
                .white,
                renderingMode: .alwaysOriginal
            )
        }
        return pipFallback()
    }

    static func pipExit() -> UIImage {
        if #available(iOS 13.0, *),
           let img = UIImage(systemName: "pip.exit") {
            return img.withTintColor(
                .white,
                renderingMode: .alwaysOriginal
            )
        }
        return pip()
    }

    static func fullscreen(isFullscreen: Bool) -> UIImage {
        draw(size: CGSize(width: 24, height: 24)) { _ in
            UIColor.white.setStroke()
            let arm: CGFloat = 5
            let lineWidth: CGFloat = 2
            let corners = isFullscreen
                ? collapsedCorners()
                : expandedCorners(arm: arm)
            drawCorners(corners, lineWidth: lineWidth)
        }
    }
}

// MARK: - Private helpers

extension PlayerIcons {
    private static func pipFallback() -> UIImage {
        draw(size: CGSize(width: 26, height: 26)) { _ in
            UIColor.white.setStroke()
            let outerRect = CGRect(x: 2, y: 5, width: 22, height: 16)
            let outer = UIBezierPath(roundedRect: outerRect, cornerRadius: 2)
            outer.lineWidth = 1.5
            outer.stroke()
            UIColor.white.setFill()
            let innerRect = CGRect(x: 12, y: 11, width: 10, height: 7)
            UIBezierPath(roundedRect: innerRect, cornerRadius: 1).fill()
        }
    }

    private static func playerIcon(_ name: String, size: CGFloat) -> UIImage {
        let iconSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: iconSize)
        let img = renderer.image { _ in
            UIColor.white.setFill()
            UIImage(named: name)?.draw(
                in: CGRect(origin: .zero, size: iconSize)
            )
        }
        return img.withRenderingMode(.alwaysOriginal)
    }

    private static func draw(size: CGSize, block: (CGContext) -> Void) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }
        block(ctx)
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }
        UIGraphicsEndImageContext()
        return image.withRenderingMode(.alwaysOriginal)
    }

    private static func expandedCorners(arm: CGFloat) -> [CornerPoints] {
        [
            CornerPoints(
                corner: CGPoint(x: 3, y: 3),
                horizontal: CGPoint(x: 3 + arm, y: 3),
                vertical: CGPoint(x: 3, y: 3 + arm)
            ),
            CornerPoints(
                corner: CGPoint(x: 21, y: 3),
                horizontal: CGPoint(x: 21 - arm, y: 3),
                vertical: CGPoint(x: 21, y: 3 + arm)
            ),
            CornerPoints(
                corner: CGPoint(x: 3, y: 21),
                horizontal: CGPoint(x: 3 + arm, y: 21),
                vertical: CGPoint(x: 3, y: 21 - arm)
            ),
            CornerPoints(
                corner: CGPoint(x: 21, y: 21),
                horizontal: CGPoint(x: 21 - arm, y: 21),
                vertical: CGPoint(x: 21, y: 21 - arm)
            )
        ]
    }

    private static func collapsedCorners() -> [CornerPoints] {
        [
            CornerPoints(
                corner: CGPoint(x: 8, y: 8),
                horizontal: CGPoint(x: 3, y: 8),
                vertical: CGPoint(x: 8, y: 3)
            ),
            CornerPoints(
                corner: CGPoint(x: 16, y: 8),
                horizontal: CGPoint(x: 21, y: 8),
                vertical: CGPoint(x: 16, y: 3)
            ),
            CornerPoints(
                corner: CGPoint(x: 8, y: 16),
                horizontal: CGPoint(x: 3, y: 16),
                vertical: CGPoint(x: 8, y: 21)
            ),
            CornerPoints(
                corner: CGPoint(x: 16, y: 16),
                horizontal: CGPoint(x: 21, y: 16),
                vertical: CGPoint(x: 16, y: 21)
            )
        ]
    }

    private static func drawCorners(_ corners: [CornerPoints], lineWidth: CGFloat) {
        for cp in corners {
            let path = UIBezierPath()
            path.move(to: cp.horizontal)
            path.addLine(to: cp.corner)
            path.addLine(to: cp.vertical)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}

// MARK: - Skip icon

extension PlayerIcons {
    private static func skipIcon(forward: Bool) -> UIImage {
        draw(size: CGSize(width: 44, height: 44)) { _ in
            let cx: CGFloat = 22
            let cy: CGFloat = 21
            let radius: CGFloat = 12
            drawSkipArc(
                cx: cx,
                cy: cy,
                radius: radius,
                forward: forward
            )
            drawSkipText(cx: cx, cy: cy)
        }
    }

    private static func drawSkipArc(
        cx: CGFloat,
        cy: CGFloat,
        radius: CGFloat,
        forward: Bool
    ) {
        let startAngle: CGFloat = forward
            ? (.pi / 6) : (.pi * 11 / 6)
        let endAngle: CGFloat = forward
            ? (.pi * 11 / 6) : (.pi / 6)
        let arc = UIBezierPath(
            arcCenter: CGPoint(x: cx, y: cy),
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: forward
        )
        arc.lineWidth = 2.2
        arc.lineCapStyle = .butt
        UIColor.white.setStroke()
        arc.stroke()
        let ex = cx + radius * cos(endAngle)
        let ey = cy + radius * sin(endAngle)
        let velX: CGFloat = forward
            ? -sin(endAngle) : sin(endAngle)
        let velY: CGFloat = forward
            ? cos(endAngle) : -cos(endAngle)
        drawSkipArrowhead(
            endpoint: CGPoint(x: ex, y: ey),
            velocityAngle: atan2(velY, velX)
        )
    }

    private static func drawSkipArrowhead(
        endpoint: CGPoint,
        velocityAngle: CGFloat
    ) {
        let armLen: CGFloat = 5.5
        let spread: CGFloat = 0.45
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(
            x: endpoint.x + armLen * cos(velocityAngle + .pi + spread),
            y: endpoint.y + armLen * sin(velocityAngle + .pi + spread)
        ))
        arrow.addLine(to: endpoint)
        arrow.addLine(to: CGPoint(
            x: endpoint.x + armLen * cos(velocityAngle + .pi - spread),
            y: endpoint.y + armLen * sin(velocityAngle + .pi - spread)
        ))
        arrow.lineWidth = 2.2
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        UIColor.white.setStroke()
        arrow.stroke()
    }

    private static func drawSkipText(cx: CGFloat, cy: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.white
        ]
        let str = NSAttributedString(
            string: "10",
            attributes: attrs
        )
        let sz = str.size()
        str.draw(at: CGPoint(
            x: cx - sz.width / 2,
            y: cy - sz.height / 2 + 1
        ))
    }
}

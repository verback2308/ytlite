import UIKit

/// Player control icons drawn with UIBezierPath (iOS 12 compatible).
enum PlayerIcons {

    static func play() -> UIImage {
        return draw(size: CGSize(width: 44, height: 44)) { ctx in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 14, y: 10))
            path.addLine(to: CGPoint(x: 36, y: 22))
            path.addLine(to: CGPoint(x: 14, y: 34))
            path.close()
            UIColor.white.setFill()
            path.fill()
        }
    }

    static func pause() -> UIImage {
        return draw(size: CGSize(width: 44, height: 44)) { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 12, y: 10, width: 7, height: 24), cornerRadius: 2).fill()
            UIBezierPath(roundedRect: CGRect(x: 25, y: 10, width: 7, height: 24), cornerRadius: 2).fill()
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
            return img.withTintColor(.white, renderingMode: .alwaysOriginal)
        }
        return draw(size: CGSize(width: 26, height: 26)) { _ in
            UIColor.white.setStroke()
            let outer = UIBezierPath(roundedRect: CGRect(x: 2, y: 5, width: 22, height: 16), cornerRadius: 2)
            outer.lineWidth = 1.5
            outer.stroke()
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 12, y: 11, width: 10, height: 7), cornerRadius: 1).fill()
        }
    }

    static func pipExit() -> UIImage {
        if #available(iOS 13.0, *),
           let img = UIImage(systemName: "pip.exit") {
            return img.withTintColor(.white, renderingMode: .alwaysOriginal)
        }
        return pip()
    }

    private static func playerIcon(_ name: String, size: CGFloat) -> UIImage {
        let s = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: s)
        let img = renderer.image { _ in
            UIColor.white.setFill()
            UIImage(named: name)?.draw(in: CGRect(origin: .zero, size: s))
        }
        return img.withRenderingMode(.alwaysOriginal)
    }

    static func fullscreen(isFullscreen: Bool) -> UIImage {
        return draw(size: CGSize(width: 24, height: 24)) { _ in
            UIColor.white.setStroke()
            let arm: CGFloat = 5
            let lw: CGFloat = 2

            let corners: [(CGPoint, CGPoint, CGPoint)]
            if !isFullscreen {
                corners = [
                    (CGPoint(x: 3, y: 3),  CGPoint(x: 3+arm, y: 3),   CGPoint(x: 3, y: 3+arm)),
                    (CGPoint(x: 21, y: 3), CGPoint(x: 21-arm, y: 3),   CGPoint(x: 21, y: 3+arm)),
                    (CGPoint(x: 3, y: 21), CGPoint(x: 3+arm, y: 21),   CGPoint(x: 3, y: 21-arm)),
                    (CGPoint(x: 21, y: 21),CGPoint(x: 21-arm, y: 21),  CGPoint(x: 21, y: 21-arm)),
                ]
            } else {
                corners = [
                    (CGPoint(x: 8, y: 8),  CGPoint(x: 3, y: 8),   CGPoint(x: 8, y: 3)),
                    (CGPoint(x: 16, y: 8), CGPoint(x: 21, y: 8),  CGPoint(x: 16, y: 3)),
                    (CGPoint(x: 8, y: 16), CGPoint(x: 3, y: 16),  CGPoint(x: 8, y: 21)),
                    (CGPoint(x: 16, y: 16),CGPoint(x: 21, y: 16), CGPoint(x: 16, y: 21)),
                ]
            }

            for (corner, h, v) in corners {
                let path = UIBezierPath()
                path.move(to: h)
                path.addLine(to: corner)
                path.addLine(to: v)
                path.lineWidth = lw
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }

    // MARK: - Private helpers

    private static func draw(size: CGSize, block: (CGContext) -> Void) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()!
        block(ctx)
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// Circular arrow with arrowhead, like YouTube's skip button.
    private static func skipIcon(forward: Bool) -> UIImage {
        return draw(size: CGSize(width: 44, height: 44)) { _ in
            let cx: CGFloat = 22
            let cy: CGFloat = 21
            let r:  CGFloat = 12

            let startAngle: CGFloat = forward ? (.pi / 6)        : (.pi * 11 / 6)
            let endAngle:   CGFloat = forward ? (.pi * 11 / 6)   : (.pi / 6)

            let arc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: r,
                                   startAngle: startAngle, endAngle: endAngle,
                                   clockwise: forward)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .butt
            UIColor.white.setStroke()
            arc.stroke()

            let ex = cx + r * cos(endAngle)
            let ey = cy + r * sin(endAngle)
            let velX: CGFloat = forward ? -sin(endAngle) :  sin(endAngle)
            let velY: CGFloat = forward ?  cos(endAngle) : -cos(endAngle)
            let velDir = atan2(velY, velX)

            let armLen: CGFloat = 5.5
            let spread: CGFloat = 0.45

            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(
                x: ex + armLen * cos(velDir + .pi + spread),
                y: ey + armLen * sin(velDir + .pi + spread)))
            arrow.addLine(to: CGPoint(x: ex, y: ey))
            arrow.addLine(to: CGPoint(
                x: ex + armLen * cos(velDir + .pi - spread),
                y: ey + armLen * sin(velDir + .pi - spread)))
            arrow.lineWidth = 2.2
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            UIColor.white.setStroke()
            arrow.stroke()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor.white,
            ]
            let str = NSAttributedString(string: "10", attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: cx - sz.width / 2, y: cy - sz.height / 2 + 1))
        }
    }
}

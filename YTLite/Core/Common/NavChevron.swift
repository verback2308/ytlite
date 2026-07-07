import UIKit

/// The single factory for navigation chevrons. Every screen builds its
/// back/minimize button here — and `RotatingNavigationController` replaces
/// the system back button on push — so the glyph and edge inset are
/// identical on every screen and iOS version.
enum NavChevron {
    enum Kind {
        case back
        case minimize
    }

    static func barButton(
        kind: Kind,
        target: Any?,
        action: Selector
    ) -> UIBarButtonItem {
        UIBarButtonItem(
            customView: NavChevronButton(kind: kind, target: target, action: action)
        )
    }

    static func image(kind: Kind) -> UIImage? {
        if #available(iOS 13.0, *) {
            let name = kind == .back ? "chevron.left" : "chevron.down"
            return ThemeManager.navChevron(systemName: name)
        }
        return drawnChevron(kind: kind)
    }

    // MARK: - Pre-iOS 13 fallback (no SF Symbols)

    private static func drawnChevron(kind: Kind) -> UIImage {
        let size: CGSize
        let points: [CGPoint]
        switch kind {
        case .back:
            size = CGSize(width: 13, height: 22)
            points = [
                CGPoint(x: 11, y: 2),
                CGPoint(x: 2, y: 11),
                CGPoint(x: 11, y: 20)
            ]
        case .minimize:
            size = CGSize(width: 22, height: 13)
            points = [
                CGPoint(x: 2, y: 2),
                CGPoint(x: 11, y: 11),
                CGPoint(x: 20, y: 2)
            ]
        }
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }
        // Template so the navigation bar tint colors it per theme.
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// Self-aligning chevron bar button. UIKit positions bar items at
/// context-dependent offsets (root vs pushed slot, tab vs child-embedded
/// bar, glass vs legacy metrics — measured 12.5pt vs 31pt for the same
/// button), so after layout the view checks where the bar actually put it
/// and shifts itself to sit exactly `edgeInset` from the screen edge.
final class NavChevronButton: UIView {
    private static let edgeInset: CGFloat = 16
    private static let side: CGFloat = 44

    private let button = UIButton(type: .system)

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.side, height: Self.side)
    }

    init(kind: NavChevron.Kind, target: Any?, action: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        button.setImage(NavChevron.image(kind: kind), for: .normal)
        // Glyph at the view's leading edge; the rest of the 44pt width
        // stays as tap area.
        button.contentHorizontalAlignment = .leading
        button.addTarget(target, action: action, for: .touchUpInside)
        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        alignToScreenEdge()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        alignToScreenEdge()
    }

    private func alignToScreenEdge() {
        guard let window else {
            transform = .identity
            return
        }
        transform = .identity
        let shift: CGFloat
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            let right = convert(CGPoint(x: bounds.width, y: 0), to: window).x
            shift = (window.bounds.width - Self.edgeInset) - right
        } else {
            shift = Self.edgeInset - convert(CGPoint.zero, to: window).x
        }
        if abs(shift) > 0.5 {
            transform = CGAffineTransform(translationX: shift, y: 0)
        }
    }
}

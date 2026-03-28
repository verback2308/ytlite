// swiftlint:disable:this file_name
import UIKit

/// Adds a shimmering skeleton overlay to any UIView.
extension UIView {
    private static let skeletonTag = 99_001

    func showSkeleton() {
        guard viewWithTag(UIView.skeletonTag) == nil
        else { return }
        let overlay = SkeletonOverlayView(frame: bounds)
        overlay.tag = UIView.skeletonTag
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
        overlay.startAnimating()
    }

    func hideSkeleton() {
        viewWithTag(UIView.skeletonTag)?.removeFromSuperview()
    }
}

// MARK: - Skeleton Overlay

private final class SkeletonOverlayView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let theme = ThemeManager.shared
        backgroundColor = theme.skeletonBase
        gradientLayer.colors = [
            theme.skeletonBase.cgColor,
            theme.skeletonShimmer.cgColor,
            theme.skeletonBase.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint   = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations  = [-1, -0.5, 0]
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    func startAnimating() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue   = [1.0, 1.5, 2.0]
        anim.duration  = 1.3
        anim.repeatCount = .infinity
        gradientLayer.add(anim, forKey: "shimmer")
    }
}

// MARK: - Skeleton placeholder shapes

/// A plain rounded rectangle used as a placeholder inside skeleton cells.
final class SkeletonBlockView: UIView {
    init(cornerRadius: CGFloat = 4) {
        super.init(frame: .zero)
        backgroundColor = ThemeManager.shared.skeletonBlock
        layer.cornerRadius = cornerRadius
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }
}

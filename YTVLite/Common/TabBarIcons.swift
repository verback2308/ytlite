import UIKit

enum TabBarIcons {
    static func home()          -> UIImage? { icon("icon_House_Fill",    size: 25) }
    static func subscriptions() -> UIImage? { icon("icon_Play_Rectangle", size: 25) }
    static func library()       -> UIImage? { icon("icon_Square_Stack",   size: 25) }
}

private func icon(_ name: String, size: CGFloat) -> UIImage? {
    guard let img = UIImage(named: name) else { return nil }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
        img.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }.withRenderingMode(.alwaysTemplate)
}

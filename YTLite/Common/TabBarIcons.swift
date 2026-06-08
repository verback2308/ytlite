import UIKit

enum TabBarIcons {
    static func home() -> UIImage? { icon("icon_House_Fill", size: 25) }
    static func subscriptions() -> UIImage? { icon("icon_Play_Rectangle", size: 25) }
    static func library() -> UIImage? { icon("icon_Square_Stack", size: 25) }
}

private func icon(_ name: String, size: CGFloat) -> UIImage? {
    guard let img = UIImage(named: name) else {
        return nil
    }
    let targetSize = CGSize(width: size, height: size)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let rendered = renderer.image { _ in
        img.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return rendered.withRenderingMode(.alwaysTemplate)
}

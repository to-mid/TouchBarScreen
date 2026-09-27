import AppKit

enum DisplayMode: String, CaseIterable {
    case stretch
    case aspectFit
    case centerCrop

    var title: String {
        switch self {
        case .stretch:
            return "完整铺满"
        case .aspectFit:
            return "保持比例"
        case .centerCrop:
            return "中间裁切"
        }
    }
}

enum ImageLayout {
    static func destinationRect(
        imageSize: CGSize,
        bounds: CGRect,
        mode: DisplayMode
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        guard mode != .stretch else {
            return bounds
        }

        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let scale = mode == .aspectFit
            ? min(widthScale, heightScale)
            : max(widthScale, heightScale)
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

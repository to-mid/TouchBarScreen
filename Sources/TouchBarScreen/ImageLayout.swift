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

    static func detailSourceRect(
        imageSize: CGSize,
        destinationSize: CGSize,
        normalizedCursorPosition: CGPoint,
        magnification: CGFloat
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              destinationSize.width > 0, destinationSize.height > 0,
              magnification > 0 else {
            return .zero
        }

        let desiredSize = CGSize(
            width: destinationSize.width / magnification,
            height: destinationSize.height / magnification
        )
        let fitScale = min(
            1,
            imageSize.width / desiredSize.width,
            imageSize.height / desiredSize.height
        )
        let sourceSize = CGSize(
            width: desiredSize.width * fitScale,
            height: desiredSize.height * fitScale
        )
        let cursorX = min(max(normalizedCursorPosition.x, 0), 1)
            * imageSize.width
        let cursorY = (1 - min(max(normalizedCursorPosition.y, 0), 1))
            * imageSize.height
        let originX = min(
            max(0, cursorX - sourceSize.width / 2),
            imageSize.width - sourceSize.width
        )
        let originY = min(
            max(0, cursorY - sourceSize.height / 2),
            imageSize.height - sourceSize.height
        )

        return CGRect(
            x: originX,
            y: originY,
            width: sourceSize.width,
            height: sourceSize.height
        )
    }
}

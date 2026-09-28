import AppKit
import TouchBarPrivateBridge

final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let displayIdentifier = NSTouchBarItem.Identifier(
        "com.local.TouchBarScreen.display"
    )

    let frameView = TouchBarFrameView(
        frame: NSRect(x: 0, y: 0, width: 600, height: 30)
    )

    private lazy var displayItem: NSCustomTouchBarItem = {
        let item = NSCustomTouchBarItem(identifier: Self.displayIdentifier)
        item.view = frameView
        frameView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        frameView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        frameView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        item.visibilityPriority = .high
        return item
    }()

    private(set) lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.displayIdentifier]
        return bar
    }()

    private(set) var isPersistent = true
    private var isInstalled = false
    private var isSystemModalPresented = false
    private var isAppTouchBarInstalled = false

    func install(persistent: Bool) {
        if isInstalled,
           persistent == isPersistent,
           isSystemModalPresented || isAppTouchBarInstalled {
            return
        }

        if isSystemModalPresented {
            dismissSystemModalTouchBar()
            isSystemModalPresented = false
        }
        if isAppTouchBarInstalled {
            NSApp.touchBar = nil
            isAppTouchBarInstalled = false
        }

        isInstalled = true
        isPersistent = persistent

        if persistent {
            isSystemModalPresented = presentSystemModalTouchBar()
        }

        if isSystemModalPresented {
            return
        }

        isPersistent = false
        NSApp.touchBar = touchBar
        isAppTouchBarInstalled = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func uninstall() {
        isInstalled = false
        if isSystemModalPresented {
            dismissSystemModalTouchBar()
            isSystemModalPresented = false
        }
        if isAppTouchBarInstalled {
            NSApp.touchBar = nil
            isAppTouchBarInstalled = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.hide(nil)
        }
    }

    func refreshPersistentPresentation() {
        guard isInstalled, isPersistent else {
            return
        }

        if isSystemModalPresented {
            dismissSystemModalTouchBar()
        }
        isSystemModalPresented = presentSystemModalTouchBar()
    }

    func setFrame(_ frame: CapturedFrame) {
        frameView.setFrameImage(
            frame.image,
            cursorPosition: frame.cursorPosition
        )
    }

    func clearFrame() {
        frameView.clearFrame()
    }

    func showStatus(_ message: String, persistent: Bool) {
        frameView.showStatus(message)
        install(persistent: persistent)
    }

    func updateCursorPosition(_ position: CGPoint) {
        frameView.updateCursorPosition(position)
    }

    func setDetailMagnification(_ magnification: CGFloat) {
        frameView.detailMagnification = magnification
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == Self.displayIdentifier else {
            return nil
        }
        return displayItem
    }

    @discardableResult
    private func presentSystemModalTouchBar() -> Bool {
        TBPresentSystemModalTouchBar(touchBar)
    }

    private func dismissSystemModalTouchBar() {
        TBDismissSystemModalTouchBar(touchBar)
    }
}

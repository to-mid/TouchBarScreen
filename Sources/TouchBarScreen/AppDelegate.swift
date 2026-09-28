import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum CaptureState: Equatable {
        case idle
        case starting
        case waitingForFrame
        case running
        case recovering
        case stopping
    }

    private let captureEngine = ScreenCaptureEngine()
    private let touchBarController = TouchBarController()
    private let hotKeyManager = GlobalHotKeyManager()
    private var statusItem: NSStatusItem!
    private var displays: [CapturableDisplay] = []
    private var selectedDisplayID: CGDirectDisplayID?
    private var captureState = CaptureState.idle
    private var captureGeneration = 0
    private var hasReceivedFrame = false
    private var framesPerSecond = 10
    private var detailMagnification: CGFloat = 1
    private var persistentTouchBar = true
    private var touchBarRestoreGeneration = 0
    private var wantsCapture = false
    private var displayRecoveryTask: Task<Void, Never>?

    private var isCapturing: Bool {
        switch captureState {
        case .starting, .waitingForFrame, .running:
            return true
        case .idle, .recovering, .stopping:
            return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadPreferences()
        configureStatusItem()
        configureCaptureCallbacks()
        configureHotKeys()
        configureWorkspaceObservers()
        Task {
            await refreshDisplays(startCaptureAfterRefresh: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        wantsCapture = false
        displayRecoveryTask?.cancel()
        touchBarController.uninstall()
        Task {
            await captureEngine.stop()
        }
    }

    private func configureWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceContextDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceContextDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc
    private func workspaceContextDidChange(_ notification: Notification) {
        schedulePersistentTouchBarRestore()
    }

    @objc
    private func displayConfigurationDidChange(
        _ notification: Notification
    ) {
        guard wantsCapture else {
            return
        }
        scheduleDisplayRecovery()
    }

    private func schedulePersistentTouchBarRestore() {
        guard isCapturing, persistentTouchBar else {
            return
        }

        touchBarRestoreGeneration += 1
        let generation = touchBarRestoreGeneration
        for delay in [0.2, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                [weak self] in
                guard let self,
                      generation == self.touchBarRestoreGeneration,
                      self.isCapturing,
                      self.persistentTouchBar else {
                    return
                }
                self.touchBarController.refreshPersistentPresentation()
            }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "Touch Bar 屏幕"
            )
        }
        rebuildMenu()
    }

    private func configureCaptureCallbacks() {
        captureEngine.onFrame = { [weak self] frame in
            guard let self, self.isCapturing else {
                return
            }
            self.touchBarController.setFrame(frame)
            if !self.hasReceivedFrame {
                self.hasReceivedFrame = true
                self.captureState = .running
                self.rebuildMenu()
            }
        }
        captureEngine.onCursorPosition = { [weak self] position in
            guard let self, self.isCapturing else {
                return
            }
            self.touchBarController.updateCursorPosition(position)
        }
        captureEngine.onStop = { [weak self] error in
            guard let self else {
                return
            }
            self.hasReceivedFrame = false
            self.touchBarController.clearFrame()
            self.touchBarController.uninstall()
            if self.wantsCapture {
                self.captureState = .recovering
                self.rebuildMenu()
                self.scheduleDisplayRecovery(error: error)
            } else {
                self.captureState = .idle
                self.rebuildMenu()
            }
        }
    }

    private func configureHotKeys() {
        hotKeyManager.onAction = { [weak self] action in
            guard let self else {
                return
            }
            switch action {
            case .toggleCapture:
                self.toggleCapture(nil)
            case .decreaseMagnification:
                self.adjustMagnification(by: -0.1)
            case .increaseMagnification:
                self.adjustMagnification(by: 0.1)
            case .setMagnification:
                self.showMagnificationPrompt()
            }
        }
    }

    private func loadPreferences() {
        let saved = UserDefaults.standard.double(
            forKey: "detailMagnification"
        )
        if saved > 0 {
            detailMagnification = clampedMagnification(CGFloat(saved))
        }
        if UserDefaults.standard.object(
            forKey: "framesPerSecond"
        ) != nil {
            let savedFrameRate = UserDefaults.standard.integer(
                forKey: "framesPerSecond"
            )
            if [5, 10, 15, 30].contains(savedFrameRate) {
                framesPerSecond = savedFrameRate
            }
        }
        if UserDefaults.standard.object(
            forKey: "persistentTouchBar"
        ) != nil {
            persistentTouchBar = UserDefaults.standard.bool(
                forKey: "persistentTouchBar"
            )
        }
        touchBarController.setDetailMagnification(detailMagnification)
    }

    @MainActor
    private func refreshDisplays(startCaptureAfterRefresh: Bool) async {
        do {
            displays = try await captureEngine.availableDisplays()

            let savedID = UserDefaults.standard.object(
                forKey: "selectedDisplayID"
            ) as? NSNumber
            if let savedID,
               displays.contains(where: { $0.id == savedID.uint32Value }) {
                selectedDisplayID = savedID.uint32Value
            } else {
                selectedDisplayID = displays.first(where: { !$0.isMain })?.id
                    ?? displays.first?.id
            }

            if let selectedDisplayID {
                UserDefaults.standard.set(
                    NSNumber(value: selectedDisplayID),
                    forKey: "selectedDisplayID"
                )
            }
            rebuildMenu()
            if startCaptureAfterRefresh, selectedDisplayID != nil {
                await startCapture()
            }
        } catch {
            let statusMessage = (error as? CaptureError)?.touchBarMessage
                ?? "无法获取显示器"
            touchBarController.showStatus(
                statusMessage,
                persistent: persistentTouchBar
            )
            showError(error)
        }
    }

    private func scheduleDisplayRecovery(error: Error? = nil) {
        guard wantsCapture else {
            return
        }

        captureState = .recovering
        rebuildMenu()
        displayRecoveryTask?.cancel()
        let previouslySelectedDisplay = displays.first(where: {
            $0.id == selectedDisplayID
        })
        let delays = [0.4, 1.2, 3.0, 6.0]
        displayRecoveryTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            var lastError = error

            for delay in delays {
                try? await Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000)
                )
                guard !Task.isCancelled, self.wantsCapture else {
                    return
                }

                do {
                    let availableDisplays =
                        try await self.captureEngine.availableDisplays()
                    guard !availableDisplays.isEmpty else {
                        lastError = CaptureError.displayUnavailable
                        continue
                    }

                    self.displays = availableDisplays
                    self.selectedDisplayID = DisplayRecovery.selectedDisplayID(
                        currentID: self.selectedDisplayID,
                        in: availableDisplays,
                        previouslySelected: previouslySelectedDisplay
                    )

                    guard let selectedDisplayID = self.selectedDisplayID else {
                        lastError = CaptureError.displayUnavailable
                        continue
                    }
                    UserDefaults.standard.set(
                        NSNumber(value: selectedDisplayID),
                        forKey: "selectedDisplayID"
                    )
                    self.rebuildMenu()

                    if let startError = await self.startCapture(
                        scheduleRecoveryOnFailure: false
                    ) {
                        lastError = startError
                        continue
                    }

                    self.displayRecoveryTask = nil
                    return
                } catch {
                    lastError = error
                }
            }

            self.displayRecoveryTask = nil
            if self.wantsCapture {
                self.showError(
                    lastError ?? CaptureError.displayUnavailable
                )
            }
        }
    }

    @MainActor
    @discardableResult
    private func startCapture(
        scheduleRecoveryOnFailure: Bool = true
    ) async -> Error? {
        guard let selectedDisplayID else {
            return CaptureError.displayUnavailable
        }

        wantsCapture = true
        captureGeneration += 1
        let generation = captureGeneration
        captureState = .starting
        touchBarController.showStatus(
            "正在启动屏幕采集",
            persistent: persistentTouchBar
        )
        rebuildMenu()
        if scheduleRecoveryOnFailure {
            displayRecoveryTask?.cancel()
            displayRecoveryTask = nil
        }
        do {
            hasReceivedFrame = false
            try await captureEngine.start(
                displayID: selectedDisplayID,
                framesPerSecond: framesPerSecond
            )
            guard generation == captureGeneration, wantsCapture else {
                return CancellationError()
            }
            captureState = .waitingForFrame
            touchBarController.install(persistent: persistentTouchBar)
            rebuildMenu()
            return nil
        } catch {
            guard generation == captureGeneration else {
                return error
            }
            if error is CancellationError {
                return error
            }
            captureState = wantsCapture ? .recovering : .idle
            let statusMessage = (error as? CaptureError)?.touchBarMessage
                ?? "屏幕采集失败"
            touchBarController.showStatus(
                statusMessage,
                persistent: persistentTouchBar
            )
            rebuildMenu()
            if scheduleRecoveryOnFailure, error is CaptureError {
                scheduleDisplayRecovery(error: error)
            } else if scheduleRecoveryOnFailure {
                showError(error)
            }
            return error
        }
    }

    @MainActor
    private func stopCapture() async {
        wantsCapture = false
        captureGeneration += 1
        let generation = captureGeneration
        captureState = .stopping
        displayRecoveryTask?.cancel()
        displayRecoveryTask = nil
        hasReceivedFrame = false
        touchBarController.clearFrame()
        touchBarController.uninstall()
        await captureEngine.stop()
        guard generation == captureGeneration else {
            return
        }
        captureState = .idle
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTitle: String
        if captureState == .recovering {
            statusTitle = "正在恢复显示器连接"
        } else if captureState == .stopping {
            statusTitle = "正在停止"
        } else if hasReceivedFrame {
            statusTitle = "正在镜像 · 已收到画面"
        } else if captureState == .starting {
            statusTitle = "正在启动采集"
        } else if captureState == .waitingForFrame {
            statusTitle = "正在镜像 · 等待画面"
        } else {
            statusTitle = "未启动"
        }
        let status = NSMenuItem(
            title: statusTitle,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if displays.isEmpty {
            let empty = NSMenuItem(
                title: "没有可用显示器",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for display in displays {
                let suffix = display.isMain ? "（主屏幕）" : ""
                let item = NSMenuItem(
                    title: "\(display.name) \(display.width)×\(display.height)\(suffix)",
                    action: #selector(selectDisplay(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: display.id)
                item.state = display.id == selectedDisplayID ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(magnificationMenuItem())
        menu.addItem(frameRateMenuItem())
        menu.addItem(shortcutsMenuItem())

        let persistentTitle: String
        if persistentTouchBar,
           isCapturing,
           !touchBarController.isPersistent {
            persistentTitle = "常驻 Touch Bar（不可用，已回退）"
        } else {
            persistentTitle = "常驻 Touch Bar（私有 API）"
        }
        let persistent = NSMenuItem(
            title: persistentTitle,
            action: #selector(togglePersistentTouchBar(_:)),
            keyEquivalent: ""
        )
        persistent.target = self
        persistent.state = persistentTouchBar ? .on : .off
        menu.addItem(persistent)

        menu.addItem(.separator())

        let toggleShortcut = hotKeyManager.shortcut(for: .toggleCapture)
        let toggle = NSMenuItem(
            title: (isCapturing ? "停止镜像" : "启动镜像")
                + "    \(toggleShortcut.displayName)",
            action: #selector(toggleCapture(_:)),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = selectedDisplayID != nil
        menu.addItem(toggle)

        let refresh = NSMenuItem(
            title: "刷新显示器",
            action: #selector(refreshDisplays(_:)),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 TouchBarScreen",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func magnificationMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "鼠标局部缩放：\(formattedMagnification)",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        let current = NSMenuItem(
            title: "当前：\(formattedMagnification)",
            action: nil,
            keyEquivalent: ""
        )
        current.isEnabled = false
        submenu.addItem(current)
        submenu.addItem(.separator())

        let decrease = NSMenuItem(
            title: "减小 0.1×    "
                + hotKeyManager.shortcut(
                    for: .decreaseMagnification
                ).displayName,
            action: #selector(decreaseMagnification(_:)),
            keyEquivalent: ""
        )
        decrease.target = self
        submenu.addItem(decrease)

        let increase = NSMenuItem(
            title: "增大 0.1×    "
                + hotKeyManager.shortcut(
                    for: .increaseMagnification
                ).displayName,
            action: #selector(increaseMagnification(_:)),
            keyEquivalent: ""
        )
        increase.target = self
        submenu.addItem(increase)

        let custom = NSMenuItem(
            title: "自定义…    "
                + hotKeyManager.shortcut(
                    for: .setMagnification
                ).displayName,
            action: #selector(setCustomMagnification(_:)),
            keyEquivalent: ""
        )
        custom.target = self
        submenu.addItem(custom)

        let reset = NSMenuItem(
            title: "重置为 1×",
            action: #selector(resetMagnification(_:)),
            keyEquivalent: ""
        )
        reset.target = self
        submenu.addItem(reset)

        parent.submenu = submenu
        return parent
    }

    private func shortcutsMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "全局快捷键",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()

        for action in GlobalHotKeyManager.Action.allCases {
            let shortcut = hotKeyManager.shortcut(for: action)
            let item = NSMenuItem(
                title: "\(action.title)    \(shortcut.displayName)",
                action: #selector(editShortcut(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: action.rawValue)
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let reset = NSMenuItem(
            title: "恢复默认快捷键",
            action: #selector(resetShortcuts(_:)),
            keyEquivalent: ""
        )
        reset.target = self
        submenu.addItem(reset)
        parent.submenu = submenu
        return parent
    }

    private func frameRateMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "帧率",
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        for value in [5, 10, 15, 30] {
            let item = NSMenuItem(
                title: "\(value) FPS",
                action: #selector(selectFrameRate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: value)
            item.state = value == framesPerSecond ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc
    private func selectDisplay(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else {
            return
        }
        let shouldRestartCapture = wantsCapture
        selectedDisplayID = number.uint32Value
        UserDefaults.standard.set(number, forKey: "selectedDisplayID")
        rebuildMenu()
        if shouldRestartCapture {
            Task {
                await startCapture()
            }
        }
    }

    private var formattedMagnification: String {
        let value = Double(detailMagnification)
        let format = value == value.rounded() ? "%.0f×" : "%.2f×"
        return String(format: format, value)
    }

    private func clampedMagnification(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.1), 20)
    }

    private func setMagnification(_ value: CGFloat) {
        detailMagnification = clampedMagnification(value)
        UserDefaults.standard.set(
            Double(detailMagnification),
            forKey: "detailMagnification"
        )
        touchBarController.setDetailMagnification(detailMagnification)
        rebuildMenu()
    }

    private func adjustMagnification(by amount: CGFloat) {
        setMagnification(detailMagnification + amount)
    }

    private func showMagnificationPrompt() {
        let alert = NSAlert()
        alert.messageText = "设置鼠标局部缩放"
        alert.informativeText = "请输入 0.1 到 20.0 之间的倍率。"
        alert.addButton(withTitle: "应用")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 180, height: 24)
        )
        input.stringValue = String(
            format: "%.2f",
            Double(detailMagnification)
        )
        input.alignment = .center
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let value = Double(input.stringValue),
              value >= 0.1,
              value <= 20 else {
            return
        }
        setMagnification(CGFloat(value))
    }

    @objc
    private func decreaseMagnification(_ sender: Any?) {
        adjustMagnification(by: -0.1)
    }

    @objc
    private func increaseMagnification(_ sender: Any?) {
        adjustMagnification(by: 0.1)
    }

    @objc
    private func setCustomMagnification(_ sender: Any?) {
        showMagnificationPrompt()
    }

    @objc
    private func resetMagnification(_ sender: Any?) {
        setMagnification(1)
    }

    @objc
    private func editShortcut(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber,
              let action = GlobalHotKeyManager.Action(
                rawValue: number.uint32Value
              ) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = action.title
        alert.informativeText = "当前快捷键："
            + hotKeyManager.shortcut(for: action).displayName
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let recorder = ShortcutRecorderView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 54)
        )
        alert.accessoryView = recorder

        hotKeyManager.suspend()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(recorder)
        let response = alert.runModal()
        hotKeyManager.resume()

        var didFail = false
        if response == .alertFirstButtonReturn {
            guard let shortcut = recorder.shortcut else {
                showShortcutError("请先按下一个新的快捷键组合。")
                return
            }
            didFail = !hotKeyManager.setShortcut(shortcut, for: action)
        }

        if didFail {
            showShortcutError(
                "该快捷键已被本应用或其他程序占用，请选择其他组合。"
            )
        }
        rebuildMenu()
    }

    @objc
    private func resetShortcuts(_ sender: Any?) {
        hotKeyManager.resetToDefaults()
        rebuildMenu()
    }

    private func showShortcutError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法设置快捷键"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc
    private func selectFrameRate(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else {
            return
        }
        framesPerSecond = number.intValue
        UserDefaults.standard.set(
            framesPerSecond,
            forKey: "framesPerSecond"
        )
        rebuildMenu()
        if isCapturing {
            Task {
                await startCapture()
            }
        }
    }

    @objc
    private func togglePersistentTouchBar(_ sender: NSMenuItem) {
        persistentTouchBar.toggle()
        UserDefaults.standard.set(
            persistentTouchBar,
            forKey: "persistentTouchBar"
        )
        if isCapturing {
            touchBarController.uninstall()
            touchBarController.install(persistent: persistentTouchBar)
        }
        rebuildMenu()
    }

    @objc
    private func toggleCapture(_ sender: Any?) {
        Task {
            if isCapturing {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    @objc
    private func refreshDisplays(_ sender: NSMenuItem) {
        let shouldRestartCapture = wantsCapture
        Task {
            await refreshDisplays(
                startCaptureAfterRefresh: shouldRestartCapture
            )
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "TouchBarScreen"
        alert.informativeText = error.localizedDescription
        let isPermissionError =
            (error as? CaptureError) == .screenRecordingPermissionDenied
        if isPermissionError {
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "好")
        } else {
            alert.addButton(withTitle: "好")
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if isPermissionError,
           response == .alertFirstButtonReturn,
           let url = URL(
               string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
           ) {
            NSWorkspace.shared.open(url)
        }
    }
}

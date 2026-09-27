import Carbon.HIToolbox
import Foundation

struct HotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }
        return result + keyLabel
    }
}

final class GlobalHotKeyManager {
    enum Action: UInt32, CaseIterable {
        case toggleCapture = 1
        case decreaseMagnification
        case increaseMagnification
        case setMagnification

        var title: String {
            switch self {
            case .toggleCapture:
                return "启动或停止镜像"
            case .decreaseMagnification:
                return "减小缩放"
            case .increaseMagnification:
                return "增大缩放"
            case .setMagnification:
                return "输入缩放倍率"
            }
        }
    }

    static let defaultShortcuts: [Action: HotKeyShortcut] = {
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        return [
            .toggleCapture: HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_T),
                modifiers: modifiers,
                keyLabel: "T"
            ),
            .decreaseMagnification: HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_Minus),
                modifiers: modifiers,
                keyLabel: "-"
            ),
            .increaseMagnification: HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_Equal),
                modifiers: modifiers,
                keyLabel: "="
            ),
            .setMagnification: HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: modifiers,
                keyLabel: "M"
            )
        ]
    }()

    var onAction: ((Action) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private(set) var shortcuts = GlobalHotKeyManager.defaultShortcuts
    private var isSuspended = false

    init() {
        installEventHandler()
        loadSavedShortcuts()
        registerAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func shortcut(for action: Action) -> HotKeyShortcut {
        shortcuts[action] ?? Self.defaultShortcuts[action]!
    }

    @discardableResult
    func setShortcut(_ shortcut: HotKeyShortcut, for action: Action) -> Bool {
        if shortcuts.contains(where: {
            $0.key != action && $0.value == shortcut
        }) {
            return false
        }

        let previous = shortcuts[action]
        unregister(action)
        shortcuts[action] = shortcut

        if !isSuspended, !register(action, shortcut: shortcut) {
            shortcuts[action] = previous
            if let previous {
                _ = register(action, shortcut: previous)
            }
            return false
        }

        save(shortcut, for: action)
        return true
    }

    func resetToDefaults() {
        unregisterAll()
        shortcuts = Self.defaultShortcuts
        for action in Action.allCases {
            UserDefaults.standard.removeObject(forKey: defaultsKey(for: action))
        }
        if !isSuspended {
            registerAll()
        }
    }

    func suspend() {
        guard !isSuspended else {
            return
        }
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        guard isSuspended else {
            return
        }
        isSuspended = false
        registerAll()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let action = Action(rawValue: hotKeyID.id) else {
                    return status
                }

                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                manager.onAction?(action)
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    private func loadSavedShortcuts() {
        let decoder = JSONDecoder()
        for action in Action.allCases {
            guard let data = UserDefaults.standard.data(
                forKey: defaultsKey(for: action)
            ), let shortcut = try? decoder.decode(
                HotKeyShortcut.self,
                from: data
            ) else {
                continue
            }
            shortcuts[action] = shortcut
        }
    }

    private func save(_ shortcut: HotKeyShortcut, for action: Action) {
        guard let data = try? JSONEncoder().encode(shortcut) else {
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey(for: action))
    }

    private func defaultsKey(for action: Action) -> String {
        "hotKey.\(action.rawValue)"
    }

    private func registerAll() {
        for action in Action.allCases {
            if let shortcut = shortcuts[action] {
                _ = register(action, shortcut: shortcut)
            }
        }
    }

    @discardableResult
    private func register(
        _ action: Action,
        shortcut: HotKeyShortcut
    ) -> Bool {
        let signature = OSType(0x54425343) // TBSC
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: signature,
            id: action.rawValue
        )
        guard RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        ) == noErr, let reference else {
            return false
        }
        hotKeys[action] = reference
        return true
    }

    private func unregister(_ action: Action) {
        guard let reference = hotKeys.removeValue(forKey: action) else {
            return
        }
        UnregisterEventHotKey(reference)
    }

    private func unregisterAll() {
        for reference in hotKeys.values {
            UnregisterEventHotKey(reference)
        }
        hotKeys.removeAll()
    }
}

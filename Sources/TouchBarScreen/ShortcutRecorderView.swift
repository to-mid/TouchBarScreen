import AppKit
import Carbon.HIToolbox

final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var shortcut: HotKeyShortcut?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.stringValue = "请按下新的快捷键"
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            super.keyDown(with: event)
            return
        }

        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0, let keyLabel = keyLabel(for: event) else {
            NSSound.beep()
            label.stringValue = "请同时按下至少一个修饰键"
            return
        }

        let shortcut = HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
        self.shortcut = shortcut
        label.stringValue = shortcut.displayName
    }

    private func carbonModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }

    private func keyLabel(for event: NSEvent) -> String? {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "Page Up",
            UInt16(kVK_PageDown): "Page Down"
        ]
        if let label = specialKeys[event.keyCode] {
            return label
        }

        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return nil
        }
        return characters.uppercased()
    }
}

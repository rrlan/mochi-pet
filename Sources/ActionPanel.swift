//
//  ActionPanel.swift
//  Mochi
//
//  A compact action picker shown when the user double-clicks the pet.
//

import AppKit

final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ActionPanel: NSPanel {
    private let field = NSTextField()

    var onOpenClaude: (() -> Void)?
    var onOpenCodex: (() -> Void)?
    var onOpenMemoFile: (() -> Void)?
    var onSubmitMemo: ((String) -> Void)?

    static let panelSize = NSSize(width: 364, height: 88)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ActionPanel.panelSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: ActionPanel.panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 16

        field.frame = NSRect(x: 14, y: 50, width: ActionPanel.panelSize.width - 28, height: 22)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .black
        field.placeholderString = "直接写入 Apple 备忘录，回车保存…"
        field.target = self
        field.action = #selector(submitMemo)
        field.delegate = self
        container.addSubview(field)

        let items: [(String, Selector)] = [
            ("Claude", #selector(openClaude)),
            ("Codex", #selector(openCodex)),
            ("备忘录", #selector(openMemoFile)),
        ]
        let buttonWidth: CGFloat = 108
        let gap: CGFloat = 8
        var x: CGFloat = 14
        for (title, action) in items {
            let button = FirstMouseButton(frame: NSRect(x: x, y: 10, width: buttonWidth, height: 30))
            button.title = title
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = action
            container.addSubview(button)
            x += buttonWidth + gap
        }

        contentView = container
    }

    override var canBecomeKey: Bool { true }

    func present(above petFrame: NSRect) {
        let origin = NSPoint(x: petFrame.midX - frame.width / 2,
                             y: petFrame.maxY - 16)
        setFrameOrigin(origin)
        field.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func openClaude() {
        orderOut(nil)
        onOpenClaude?()
    }

    @objc private func openCodex() {
        orderOut(nil)
        onOpenCodex?()
    }

    @objc private func openMemoFile() {
        orderOut(nil)
        onOpenMemoFile?()
    }

    @objc private func submitMemo() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        orderOut(nil)
        if !text.isEmpty { onSubmitMemo?(text) }
    }
}

extension ActionPanel: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }
}

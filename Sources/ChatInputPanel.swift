//
//  ChatInputPanel.swift
//  Mochi
//
//  A small floating text field for talking to Mochi, with a button to pick which
//  engine (Claude / Codex) answers *this* message. Unlike the pet window (which
//  never activates), this panel must become key to receive keyboard input, so we
//  briefly activate the app while it's open.
//

import AppKit

final class ChatInputPanel: NSPanel {
    private let field = NSTextField()
    private let engineButton = NSButton()

    /// Which engine answers — pre-set when presenting, toggled by the button.
    var engine: AIEngine = .claude {
        didSet { engineButton.title = engine.displayName }
    }
    var onSubmit: ((_ text: String, _ engine: AIEngine) -> Void)?

    static let panelSize = NSSize(width: 304, height: 46)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ChatInputPanel.panelSize),
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: ChatInputPanel.panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 13

        // Engine toggle button (left).
        engineButton.frame = NSRect(x: 8, y: 8, width: 74, height: 30)
        engineButton.bezelStyle = .rounded
        engineButton.title = engine.displayName
        engineButton.font = .systemFont(ofSize: 12)
        engineButton.toolTip = "点一下切换 Claude / Codex"
        engineButton.target = self
        engineButton.action = #selector(toggleEngine)
        container.addSubview(engineButton)

        // Text field (fills the rest).
        field.frame = NSRect(x: 90, y: 12, width: ChatInputPanel.panelSize.width - 90 - 14, height: 22)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .black
        field.placeholderString = "和 Mochi 说点什么…（回车发送）"
        field.target = self
        field.action = #selector(submit)
        field.delegate = self
        container.addSubview(field)

        contentView = container
    }

    override var canBecomeKey: Bool { true }

    /// Show the panel just above the given pet window frame and focus the field.
    func present(above petFrame: NSRect) {
        engineButton.title = engine.displayName
        let origin = NSPoint(x: petFrame.midX - frame.width / 2,
                             y: petFrame.maxY - 24)
        setFrameOrigin(origin)
        field.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func toggleEngine() {
        engine = (engine == .claude) ? .codex : .claude
        makeFirstResponder(field)   // keep typing focus on the field
    }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        orderOut(nil)
        if !text.isEmpty { onSubmit?(text, engine) }
    }
}

extension ChatInputPanel: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)   // Esc dismisses without sending
            return true
        }
        return false
    }
}

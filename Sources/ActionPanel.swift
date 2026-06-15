//
//  ActionPanel.swift
//  Mochi
//
//  A compact action picker shown when the user double-clicks the pet.
//

import AppKit

/// A soft tinted pill button — brand-colored label on a light brand-tinted
/// background, with a subtle hover. Renders consistently under .aqua.
final class PillButton: NSButton {
    private let tint: NSColor

    init(title: String, color: NSColor) {
        self.tint = color
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 9
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
        ])
        setBackground(hover: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { setBackground(hover: true) }
    override func mouseExited(with event: NSEvent) { setBackground(hover: false) }

    private func setBackground(hover: Bool) {
        layer?.backgroundColor = tint.withAlphaComponent(hover ? 0.20 : 0.11).cgColor
    }
}

final class ActionPanel: NSPanel {
    private let field = NSTextField()

    var onOpenClaude: (() -> Void)?
    var onOpenCodex: (() -> Void)?
    var onOpenMemoFile: (() -> Void)?
    var onSubmitMemo: ((String) -> Void)?

    static let panelSize = NSSize(width: 364, height: 94)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ActionPanel.panelSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        // The container is white, so pin a light appearance — otherwise in dark
        // mode the buttons' default (white) title text is invisible on white.
        appearance = NSAppearance(named: .aqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: ActionPanel.panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 16
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 0.90, alpha: 1).cgColor

        field.frame = NSRect(x: 16, y: 58, width: ActionPanel.panelSize.width - 32, height: 22)
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

        let sep = NSView(frame: NSRect(x: 16, y: 50, width: ActionPanel.panelSize.width - 32, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
        container.addSubview(sep)

        let items: [(String, Selector, NSColor)] = [
            ("Claude", #selector(openClaude),   NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)),
            ("Codex",  #selector(openCodex),    NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)),
            ("备忘录",  #selector(openMemoFile), NSColor(red: 0.17, green: 0.62, blue: 0.49, alpha: 1)),
        ]
        let gap: CGFloat = 9
        let buttonWidth = (ActionPanel.panelSize.width - 32 - gap * 2) / 3
        var x: CGFloat = 16
        for (title, action, color) in items {
            let button = PillButton(title: title, color: color)
            button.frame = NSRect(x: x, y: 12, width: buttonWidth, height: 32)
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

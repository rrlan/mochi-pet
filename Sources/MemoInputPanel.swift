//
//  MemoInputPanel.swift
//  Mochi
//
//  A small floating text field for quickly appending a local memo.
//

import AppKit

final class MemoInputPanel: NSPanel {
    private let field = NSTextField()

    var onSubmit: ((String) -> Void)?

    static let panelSize = NSSize(width: 336, height: 46)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: MemoInputPanel.panelSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(origin: .zero, size: MemoInputPanel.panelSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 13

        field.frame = NSRect(x: 14, y: 12, width: MemoInputPanel.panelSize.width - 28, height: 22)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .black
        field.placeholderString = "写入 Apple 备忘录…（回车保存）"
        field.target = self
        field.action = #selector(submit)
        field.delegate = self
        container.addSubview(field)

        contentView = container
    }

    override var canBecomeKey: Bool { true }

    func present(above petFrame: NSRect) {
        let origin = NSPoint(x: petFrame.midX - frame.width / 2,
                             y: petFrame.maxY - 24)
        setFrameOrigin(origin)
        field.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        orderOut(nil)
        if !text.isEmpty { onSubmit?(text) }
    }
}

extension MemoInputPanel: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }
}

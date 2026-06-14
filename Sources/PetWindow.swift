//
//  PetWindow.swift
//  Mochi
//
//  A borderless, transparent, non-activating floating panel that hosts the
//  pet, plus the container view that handles mouse interaction (drag + poke).
//

import AppKit

/// The content view of the pet window.
///
/// It owns mouse interaction so that the SwiftUI hosting view underneath never
/// has to fight over events. `hitTest` claims every point inside the window for
/// this view, and the responder methods translate clicks/drags into high-level
/// callbacks the controller subscribes to.
final class PetContainerView: NSView {
    var onPoke: (() -> Void)?
    var onChat: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    /// Offset between the cursor and the window origin at mouse-down time, so
    /// dragging keeps the grab point under the cursor.
    private var dragOffset: NSPoint = .zero
    private var didDrag = false

    /// The blob occupies the bottom-center of the (wider) window. Only this
    /// region is interactive — clicks elsewhere fall through to the desktop.
    private var petRect: NSRect {
        let w: CGFloat = 130, h: CGFloat = 120
        return NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return petRect.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        dragOffset = NSPoint(x: mouse.x - window.frame.origin.x,
                             y: mouse.y - window.frame.origin.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        let newOrigin = NSPoint(x: mouse.x - dragOffset.x,
                                y: mouse.y - dragOffset.y)
        if !didDrag {
            didDrag = true
            onDragStart?()
        }
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnd?()
        } else if event.clickCount >= 2 {
            onChat?()           // double-click opens the chat input
        } else {
            onPoke?()
        }
        didDrag = false
    }
}

/// Borderless, transparent, always-on-top panel that floats the pet above
/// normal windows without stealing focus from whatever app you're using.
final class PetWindow: NSPanel {
    /// Default canvas size. The pet sits at the bottom-center; the top portion
    /// is reserved for the speech / AI-reply bubble. Wider than the blob so
    /// multi-line replies have room.
    static let canvasSize = NSSize(width: 280, height: 240)

    let container = PetContainerView()

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: PetWindow.canvasSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        hidesOnDeactivate = false       // stay visible even though we never activate
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false  // we handle dragging ourselves

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                              .stationary, .ignoresCycle]

        container.frame = NSRect(origin: .zero, size: PetWindow.canvasSize)
        contentView = container
    }
}

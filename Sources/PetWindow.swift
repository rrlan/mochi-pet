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
    struct BubbleTarget {
        let source: String
        let sessionID: String
        let requiresApproval: Bool
    }

    var onPoke: (() -> Void)?
    var onChat: (() -> Void)?
    var onBubbleClick: ((BubbleTarget) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var isBubbleInteractive = false
    var bubbleTargets: [BubbleTarget] = []
    /// Full "title · activity" per bubble (same order as `bubbleTargets`), shown
    /// on hover so a truncated title is still readable.
    var bubbleTooltips: [String] = []
    private var hoveredBubble = -1
    private lazy var tooltipWindow = BubbleTooltipWindow()

    /// Offset between the cursor and the window origin at mouse-down time, so
    /// dragging keeps the grab point under the cursor.
    private var dragOffset: NSPoint = .zero
    private var didDrag = false
    private var mouseDownBubbleTarget: BubbleTarget?
    /// Screen location at mouse-down, used to ignore sub-threshold jitter so a
    /// slightly-shaky click isn't misread as a drag (which would disable the
    /// status bubbles).
    private var mouseDownAt: NSPoint = .zero

    /// The blob occupies the bottom-center of the (wider) window. Only this
    /// region is interactive — clicks elsewhere fall through to the desktop.
    private var petRect: NSRect {
        let w: CGFloat = 190, h: CGFloat = 170
        return NSRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)
    }

    /// The status bubbles sit in the top band. They become clickable only while
    /// their matching agent is active.
    private func bubbleRect(index: Int, count: Int) -> NSRect {
        let w: CGFloat = 252, h: CGFloat = 150
        let x = (bounds.width - w) / 2
        if count <= 1 {
            return NSRect(x: x, y: bounds.height - h, width: w, height: h)
        }

        let rowHeight: CGFloat = 31
        let gap: CGFloat = 6
        let totalHeight = CGFloat(count) * rowHeight + CGFloat(count - 1) * gap
        let top = bounds.height - (h - totalHeight) / 2
        let y = top - rowHeight - CGFloat(index) * (rowHeight + gap)
        return NSRect(x: x, y: y, width: w, height: rowHeight)
    }

    private func bubbleTarget(at point: NSPoint) -> BubbleTarget? {
        guard isBubbleInteractive else { return nil }
        let targets = Array(bubbleTargets.prefix(4))
        for (index, target) in targets.enumerated() {
            if bubbleRect(index: index, count: targets.count).contains(point) {
                return target
            }
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if petRect.contains(point) { return self }
        if bubbleTarget(at: point) != nil { return self }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        let local = convert(event.locationInWindow, from: nil)
        mouseDownBubbleTarget = bubbleTarget(at: local)
        let mouse = NSEvent.mouseLocation
        mouseDownAt = mouse
        dragOffset = NSPoint(x: mouse.x - window.frame.origin.x,
                             y: mouse.y - window.frame.origin.y)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        if !didDrag {
            // Ignore tiny movements so a shaky click isn't treated as a drag.
            let dx = mouse.x - mouseDownAt.x, dy = mouse.y - mouseDownAt.y
            if (dx * dx + dy * dy).squareRoot() < 4 { return }
            didDrag = true
            onDragStart?()
        }
        window.setFrameOrigin(NSPoint(x: mouse.x - dragOffset.x,
                                      y: mouse.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            onDragEnd?()
        } else if let target = mouseDownBubbleTarget {
            onBubbleClick?(target)
        } else if event.clickCount >= 2 {
            onChat?()           // double-click opens the action panel
        } else {
            onPoke?()
        }
        didDrag = false
        mouseDownBubbleTarget = nil
    }

    // MARK: - Hover tooltip

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let idx = hoveredBubbleIndex(at: convert(event.locationInWindow, from: nil))
        guard idx != hoveredBubble else { return }
        hoveredBubble = idx
        if idx >= 0, idx < bubbleTooltips.count, let window = window {
            let count = min(bubbleTargets.count, 4)
            let anchor = window.convertToScreen(bubbleRect(index: idx, count: count))
            tooltipWindow.show(bubbleTooltips[idx], anchor: anchor)
        } else {
            tooltipWindow.hide()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredBubble = -1
        tooltipWindow.hide()
    }

    private func hoveredBubbleIndex(at point: NSPoint) -> Int {
        guard isBubbleInteractive else { return -1 }
        let count = min(bubbleTargets.count, 4)
        for i in 0..<count where bubbleRect(index: i, count: count).contains(point) {
            return i
        }
        return -1
    }
}

/// A tiny dark floating label shown when the cursor hovers a status bubble, so
/// a truncated title's full text is readable.
final class BubbleTooltipWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.96).cgColor
        card.layer?.cornerRadius = 8
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byCharWrapping   // wrap CJK (no spaces to break on)
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        card.addSubview(label)
        contentView = card
    }

    override var canBecomeKey: Bool { false }

    /// Anchored beside the bubble (so it lands in the same spot every time),
    /// top-aligned; flips to the other side / clamps to stay on-screen.
    func show(_ text: String, anchor rect: NSRect) {
        label.stringValue = text
        let maxTextW: CGFloat = 360
        let textSize = label.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: maxTextW, height: 10_000)) ?? NSSize(width: 120, height: 18)
        let lw = ceil(min(textSize.width, maxTextW))
        let lh = ceil(textSize.height)
        let pad: CGFloat = 9
        let w = lw + pad * 2
        let h = lh + pad * 2
        label.frame = NSRect(x: pad, y: pad, width: lw, height: lh)
        contentView?.frame = NSRect(x: 0, y: 0, width: w, height: h)

        var x = rect.maxX + 8          // to the right of the bubble
        var y = rect.maxY - h          // top-aligned with the bubble
        if let f = (NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main)?.frame {
            if x + w > f.maxX - 8 { x = rect.minX - w - 8 }   // flip left if it'd run off the right
            x = min(max(x, f.minX + 8), f.maxX - w - 8)
            y = min(max(y, f.minY + 8), f.maxY - h - 8)
        }
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        orderFront(nil)
    }

    func hide() { orderOut(nil) }
}

/// Borderless, transparent, always-on-top panel that floats the pet above
/// normal windows without stealing focus from whatever app you're using.
final class PetWindow: NSPanel {
    /// Default canvas size. The pet sits at the bottom-center; the top portion
    /// is reserved for the speech / AI-reply bubble. Wider than the blob so
    /// multi-line replies have room.
    static let canvasSize = NSSize(width: 300, height: 324)

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
        acceptsMouseMovedEvents = true       // so bubble hover tooltips fire

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

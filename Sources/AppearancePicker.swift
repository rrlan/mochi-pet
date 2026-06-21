//
//  AppearancePicker.swift
//  Mochi
//
//  A visual library for switching the pet's look: a floating panel of thumbnail
//  tiles (default Mochi + every installed pack + an "import" tile). Click a tile
//  to switch instantly; the pet behind the panel updates live. A small ✕ removes
//  a pack. This replaces the old blind "pick a folder, clobber the slot" flow.
//

import AppKit

private enum PickerTheme {
    static let mint = NSColor(red: 0.36, green: 0.76, blue: 0.63, alpha: 1)
    static let ink = NSColor(red: 0.13, green: 0.22, blue: 0.20, alpha: 1)
    static let tileBG = NSColor(white: 0.96, alpha: 1)
    static let stroke = NSColor(white: 0.90, alpha: 1)

    static let tile = NSSize(width: 96, height: 134)   // extra height for the roam pill
    static let thumb: CGFloat = 84
    static let gap: CGFloat = 14
    static let pad: CGFloat = 20
    static let titleH: CGFloat = 30
    static let columns = 4
}

final class AppearancePicker: NSPanel {
    /// Called after the active (working) pack changes, so the host can reload it.
    var onChange: (() -> Void)?
    /// Called after the roamer set changes, so the host can re-spawn ambient cats.
    var onCastingChange: (() -> Void)?
    /// Called when the user taps the "import a folder" tile.
    var onImportPack: (() -> Void)?
    /// Called when the user taps the "new pack from images" tile.
    var onNewFromImages: (() -> Void)?
    /// Footer utilities (moved here from the menu): copy the generation prompt,
    /// open the packs folder.
    var onCopyPrompt: (() -> Void)?
    var onOpenFolder: (() -> Void)?

    private let container = NSView()
    /// While true, losing key focus (to our own alert / open panel) won't dismiss
    /// the picker — otherwise a delete confirm or import dialog would close it.
    private var suppressAutoClose = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        appearance = NSAppearance(named: .aqua)   // pin light: the card is white
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.cgColor
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 0.90, alpha: 1).cgColor
        contentView = container
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Presentation

    func present(near petFrame: NSRect) {
        rebuild()
        position(near: petFrame)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Rebuild tiles in place (e.g. after an import) while staying open.
    func reload() {
        guard isVisible else { return }
        let anchor = frame
        rebuild()
        // Keep the top-left corner steady as the height changes.
        setFrameOrigin(NSPoint(x: anchor.minX, y: anchor.maxY - frame.height))
    }

    /// Bracket a host-presented dialog (e.g. the import open-panel) so stealing
    /// key focus doesn't auto-dismiss the picker behind it.
    func beginInternalDialog() { suppressAutoClose = true }
    func endInternalDialog() { suppressAutoClose = false }

    private func position(near petFrame: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(petFrame) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = petFrame.midX - frame.width / 2
        var y = petFrame.maxY + 10
        x = min(max(vf.minX + 8, x), vf.maxX - frame.width - 8)
        if y + frame.height > vf.maxY - 8 { y = petFrame.minY - frame.height - 10 }  // flip below
        y = min(max(vf.minY + 8, y), vf.maxY - frame.height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Layout

    private func rebuild() {
        container.subviews.forEach { $0.removeFromSuperview() }

        let packs = AppearanceStore.installedPacks()
        let active = AppearanceStore.activeSlug
        let roamers = Set(AppearanceStore.roamerSlugs)
        let atCap = roamers.count >= AppearanceStore.maxRoamers

        // Tile descriptors: default Mochi, each pack, then the two add tiles.
        var tiles: [PackTile] = []
        tiles.append(PackTile(thumbnail: AppearancePicker.defaultThumbnail(),
                              title: "默认 Mochi", selected: active.isEmpty,
                              roaming: false, showRoam: false, roamEnabled: false, deletable: false,
                              onClick: { [weak self] in self?.activate("") }, onToggleRoam: nil, onDelete: nil))
        for pack in packs {
            let slug = pack.slug
            let isRoaming = roamers.contains(slug)
            tiles.append(PackTile(thumbnail: pack.thumbnail, title: pack.name,
                                  selected: slug == active,
                                  roaming: isRoaming,
                                  showRoam: slug != active,       // the worker can't also roam (MVP)
                                  roamEnabled: isRoaming || !atCap,
                                  deletable: true,
                                  onClick: { [weak self] in self?.activate(slug) },
                                  onToggleRoam: { [weak self] in self?.toggleRoam(slug) },
                                  onDelete: { [weak self] in self?.delete(pack) }))
        }
        tiles.append(PackTile.add(symbol: "plus", title: "导入文件夹",
                                  onClick: { [weak self] in self?.onImportPack?() }))
        tiles.append(PackTile.add(symbol: "photo.on.rectangle", title: "图片做包",
                                  onClick: { [weak self] in self?.onNewFromImages?() }))

        let cols = min(PickerTheme.columns, max(1, tiles.count))
        let rows = Int(ceil(Double(tiles.count) / Double(cols)))
        let gridH = CGFloat(rows) * PickerTheme.tile.height + CGFloat(rows - 1) * PickerTheme.gap
        let footerH: CGFloat = 34
        let width = PickerTheme.pad * 2 + CGFloat(cols) * PickerTheme.tile.width + CGFloat(cols - 1) * PickerTheme.gap
        let height = PickerTheme.pad * 2 + PickerTheme.titleH + gridH + 12 + footerH

        setContentSize(NSSize(width: width, height: height))
        container.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))

        let titleLabel = NSTextField(labelWithString: "选择形象")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = PickerTheme.ink
        titleLabel.frame = NSRect(x: PickerTheme.pad, y: height - PickerTheme.pad - 22,
                                  width: width - PickerTheme.pad * 2, height: 22)
        container.addSubview(titleLabel)

        if !packs.isEmpty {
            let counter = NSTextField(labelWithString: "🐾 出来逛 \(roamers.count)/\(AppearanceStore.maxRoamers)")
            counter.font = .systemFont(ofSize: 12, weight: .medium)
            counter.textColor = PickerTheme.mint
            counter.alignment = .right
            counter.frame = NSRect(x: width - PickerTheme.pad - 160, y: height - PickerTheme.pad - 21,
                                   width: 160, height: 20)
            container.addSubview(counter)
        }

        let gridTop = height - PickerTheme.pad - PickerTheme.titleH
        for (i, tile) in tiles.enumerated() {
            let col = i % cols, row = i / cols
            let x = PickerTheme.pad + CGFloat(col) * (PickerTheme.tile.width + PickerTheme.gap)
            let y = gridTop - PickerTheme.tile.height - CGFloat(row) * (PickerTheme.tile.height + PickerTheme.gap)
            tile.frame = NSRect(x: x, y: y, width: PickerTheme.tile.width, height: PickerTheme.tile.height)
            container.addSubview(tile)
        }

        // Footer: a thin divider + the two utility actions that used to be in the menu.
        let sep = NSView(frame: NSRect(x: PickerTheme.pad, y: PickerTheme.pad + footerH + 6,
                                       width: width - PickerTheme.pad * 2, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = PickerTheme.stroke.cgColor
        container.addSubview(sep)

        let copyBtn = footerButton("复制生图 Prompt", symbol: "doc.on.clipboard", action: #selector(copyPromptTapped))
        copyBtn.frame.origin = NSPoint(x: PickerTheme.pad, y: PickerTheme.pad + (footerH - copyBtn.frame.height) / 2)
        container.addSubview(copyBtn)

        let folderBtn = footerButton("打开文件夹", symbol: "folder", action: #selector(openFolderTapped))
        folderBtn.frame.origin = NSPoint(x: width - PickerTheme.pad - folderBtn.frame.width,
                                         y: PickerTheme.pad + (footerH - folderBtn.frame.height) / 2)
        container.addSubview(folderBtn)
    }

    private func footerButton(_ title: String, symbol: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.imagePosition = .imageLeading
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        b.imageScaling = .scaleProportionallyDown
        b.contentTintColor = PickerTheme.mint
        b.attributedTitle = NSAttributedString(string: "  " + title, attributes: [
            .foregroundColor: PickerTheme.mint,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ])
        b.sizeToFit()
        return b
    }

    @objc private func copyPromptTapped() { onCopyPrompt?() }
    @objc private func openFolderTapped() { onOpenFolder?() }

    // MARK: - Actions

    private func activate(_ slug: String) {
        guard AppearanceStore.activeSlug != slug else { return }
        AppearanceStore.activeSlug = slug
        // The working cat is never also an ambient roamer — drop it from that set.
        if !slug.isEmpty, AppearanceStore.isRoamer(slug) { AppearanceStore.toggleRoamer(slug) }
        onChange?()
        reload()   // refresh rings / roam state
    }

    private func toggleRoam(_ slug: String) {
        guard AppearanceStore.toggleRoamer(slug) else {
            NSSound.beep()   // at the roamer cap
            return
        }
        onCastingChange?()
        reload()
    }

    private func delete(_ pack: AppearancePack) {
        let alert = NSAlert()
        alert.messageText = "删除形象包「\(pack.name)」？"
        alert.informativeText = "会从本地删除这套图片，无法撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        suppressAutoClose = true
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        suppressAutoClose = false
        guard confirmed else { return }

        let wasActive = AppearanceStore.activeSlug == pack.slug
        let wasRoaming = AppearanceStore.isRoamer(pack.slug)
        AppearanceStore.deletePack(slug: pack.slug)
        if wasActive {
            onChange?()                 // working cat gone → reload the avatar
        } else if wasRoaming {
            onCastingChange?()          // a roaming cat gone → tear down its window
        }
        reload()
    }

    override func resignKey() {
        super.resignKey()
        if !suppressAutoClose { orderOut(nil) }
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    // MARK: - Default thumbnail (the vector Mochi has no image to show)

    static func defaultThumbnail(size: CGFloat = PickerTheme.thumb) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let inset = size * 0.14
        let body = NSRect(x: inset, y: inset * 0.7, width: size - inset * 2, height: size - inset * 1.7)
        let blob = NSBezierPath(roundedRect: body, xRadius: body.width * 0.46, yRadius: body.height * 0.44)

        if let grad = NSGradient(colors: [NSColor(red: 0.62, green: 0.90, blue: 0.76, alpha: 1),
                                          NSColor(red: 0.36, green: 0.76, blue: 0.63, alpha: 1)]) {
            grad.draw(in: blob, angle: -90)
        }
        NSColor(red: 0.20, green: 0.56, blue: 0.47, alpha: 0.6).setStroke()
        blob.lineWidth = 2
        blob.stroke()

        let ink = PickerTheme.ink
        ink.setFill()
        let eyeW = size * 0.075, eyeH = size * 0.14
        let eyeY = body.midY + size * 0.02
        for dx in [-size * 0.13, size * 0.13] {
            NSBezierPath(roundedRect: NSRect(x: body.midX + dx - eyeW / 2, y: eyeY, width: eyeW, height: eyeH),
                         xRadius: eyeW / 2, yRadius: eyeW / 2).fill()
        }
        let smile = NSBezierPath()
        let sy = eyeY - size * 0.04
        smile.move(to: NSPoint(x: body.midX - size * 0.1, y: sy))
        smile.curve(to: NSPoint(x: body.midX + size * 0.1, y: sy),
                    controlPoint1: NSPoint(x: body.midX - size * 0.04, y: sy - size * 0.07),
                    controlPoint2: NSPoint(x: body.midX + size * 0.04, y: sy - size * 0.07))
        ink.setStroke()
        smile.lineWidth = 2
        smile.lineCapStyle = .round
        smile.stroke()

        image.unlockFocus()
        return image
    }
}

// MARK: - Tile

private final class PackTile: NSView {
    private let onClick: () -> Void
    private let onToggleRoam: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let thumbView = NSView()
    private var deleteButton: NSButton?
    private var roamButton: NSButton?

    init(thumbnail: NSImage?, title: String, selected: Bool,
         roaming: Bool, showRoam: Bool, roamEnabled: Bool, deletable: Bool,
         onClick: @escaping () -> Void, onToggleRoam: (() -> Void)?, onDelete: (() -> Void)?) {
        self.onClick = onClick
        self.onToggleRoam = onToggleRoam
        self.onDelete = onDelete
        super.init(frame: .zero)
        wantsLayer = true

        // Thumbnail card (top of the tile).
        thumbView.wantsLayer = true
        thumbView.layer?.backgroundColor = PickerTheme.tileBG.cgColor
        thumbView.layer?.cornerRadius = 14
        thumbView.layer?.borderWidth = selected ? 2.5 : 1
        thumbView.layer?.borderColor = (selected ? PickerTheme.mint : PickerTheme.stroke).cgColor
        thumbView.layer?.masksToBounds = true
        thumbView.frame = NSRect(x: (PickerTheme.tile.width - PickerTheme.thumb) / 2,
                                 y: PickerTheme.tile.height - PickerTheme.thumb,
                                 width: PickerTheme.thumb, height: PickerTheme.thumb)
        addSubview(thumbView)

        if let thumbnail = thumbnail {
            let iv = NSImageView(frame: thumbView.bounds.insetBy(dx: 6, dy: 6))
            iv.image = thumbnail
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.autoresizingMask = [.width, .height]
            thumbView.addSubview(iv)
        }

        // Crown badge — marks the working cat.
        if selected {
            let crown = NSImageView(frame: NSRect(x: thumbView.frame.minX + 4, y: thumbView.frame.maxY - 24, width: 20, height: 20))
            crown.wantsLayer = true
            crown.layer?.backgroundColor = PickerTheme.mint.cgColor
            crown.layer?.cornerRadius = 10
            crown.image = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: "干活的猫")?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
            crown.contentTintColor = .white
            crown.imageScaling = .scaleNone
            addSubview(crown)
        }

        // Title.
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: selected ? .semibold : .regular)
        label.textColor = selected ? PickerTheme.mint : PickerTheme.ink
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 0, y: thumbView.frame.minY - 4 - 18, width: PickerTheme.tile.width, height: 18)
        addSubview(label)

        // Roam pill — "出来逛 / 逛街中" toggle for ambient cats.
        if showRoam, onToggleRoam != nil {
            let pill = NSButton(frame: NSRect(x: (PickerTheme.tile.width - 74) / 2, y: 0, width: 74, height: 22))
            pill.isBordered = false
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 11
            pill.imagePosition = .imageLeading
            pill.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            pill.imageScaling = .scaleProportionallyDown
            pill.target = self
            pill.action = #selector(roamTapped)
            styleRoamPill(pill, roaming: roaming, enabled: roamEnabled)
            addSubview(pill)
            roamButton = pill
        }

        // Delete ✕ (shown on hover).
        if deletable, onDelete != nil {
            let b = NSButton(frame: NSRect(x: thumbView.frame.maxX - 20, y: thumbView.frame.maxY - 20, width: 20, height: 20))
            b.bezelStyle = .circular
            b.isBordered = false
            b.title = "✕"
            b.font = .systemFont(ofSize: 11, weight: .bold)
            b.contentTintColor = .white
            b.wantsLayer = true
            b.layer?.backgroundColor = NSColor(white: 0, alpha: 0.45).cgColor
            b.layer?.cornerRadius = 10
            b.target = self
            b.action = #selector(deleteTapped)
            b.isHidden = true
            addSubview(b)
            deleteButton = b
        }
    }

    private func styleRoamPill(_ pill: NSButton, roaming: Bool, enabled: Bool) {
        let title = roaming ? "逛街中" : "出来逛"
        let textColor: NSColor = roaming ? .white : (enabled ? PickerTheme.mint : NSColor(white: 0.6, alpha: 1))
        pill.attributedTitle = NSAttributedString(string: " " + title, attributes: [
            .foregroundColor: textColor,
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        ])
        pill.contentTintColor = textColor
        if roaming {
            pill.layer?.backgroundColor = PickerTheme.mint.cgColor
            pill.layer?.borderWidth = 0
        } else {
            pill.layer?.backgroundColor = NSColor.clear.cgColor
            pill.layer?.borderWidth = 1
            pill.layer?.borderColor = (enabled ? PickerTheme.mint : NSColor(white: 0.8, alpha: 1)).cgColor
        }
        pill.alphaValue = (roaming || enabled) ? 1.0 : 0.55
    }

    /// A dashed "add" tile (import folder / new from images).
    static func add(symbol: String, title: String, onClick: @escaping () -> Void) -> PackTile {
        let tile = PackTile(thumbnail: nil, title: title, selected: false,
                            roaming: false, showRoam: false, roamEnabled: false, deletable: false,
                            onClick: onClick, onToggleRoam: nil, onDelete: nil)
        tile.thumbView.layer?.backgroundColor = NSColor.clear.cgColor
        tile.thumbView.layer?.borderColor = PickerTheme.mint.withAlphaComponent(0.5).cgColor
        let glyph = NSImageView(frame: tile.thumbView.bounds)
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        glyph.contentTintColor = PickerTheme.mint
        glyph.imageScaling = .scaleNone
        glyph.autoresizingMask = [.width, .height]
        tile.thumbView.addSubview(glyph)
        return tile
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        // Let the child buttons handle their own hits; only the thumbnail/name
        // area selects this pack as the working cat.
        let p = convert(event.locationInWindow, from: nil)
        if let b = deleteButton, !b.isHidden, b.frame.contains(p) { super.mouseDown(with: event); return }
        if let r = roamButton, r.frame.contains(p) { super.mouseDown(with: event); return }
        onClick()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { deleteButton?.isHidden = false }
    override func mouseExited(with event: NSEvent) { deleteButton?.isHidden = true }

    @objc private func roamTapped() { onToggleRoam?() }
    @objc private func deleteTapped() { onDelete?() }
}

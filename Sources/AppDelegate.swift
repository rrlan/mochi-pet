//
//  AppDelegate.swift
//  Mochi
//
//  Wires everything together: creates the floating pet window, hosts the
//  SwiftUI view inside it, builds the status-bar menu, and starts the brain.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The working cat. The rest of the file refers to its window/state/brain
    /// through the computed accessors below, so existing logic is unchanged.
    private var avatar: PetUnit!
    /// Ambient roaming cats, keyed by their pack slug.
    private var ambients: [String: PetUnit] = [:]
    private var colonyHidden = false

    private var state: PetState { avatar.state }
    private var window: PetWindow { avatar.window }
    private var controller: PetController { avatar.controller }

    private var statusItem: NSStatusItem!
    private var actionPanel: ActionPanel!
    private var appearancePicker: AppearancePicker!
    private var bridge: MochiBridge!
    private var monitor: AgentMonitor!

    private var updateMenuItem: NSMenuItem?
    private var latestReleaseURL: String?

    private let monitorDefaultsKey = "MochiSenseAgents"

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceStore.prepareLibrary()   // migrate legacy slot + seed bundled packs
        buildAvatar()
        applyActiveAppearance()

        // Double-click action picker.
        actionPanel = ActionPanel()
        actionPanel.onOpenClaude = { [weak self] in self?.openClaude() }
        actionPanel.onOpenCodex = { [weak self] in self?.openCodex() }
        actionPanel.onOpenMemoFile = { [weak self] in self?.openMemoFile() }
        actionPanel.onSubmitMemo = { [weak self] text in self?.saveMemo(text) }

        // Visual appearance "casting" panel (opened from the menu).
        appearancePicker = AppearancePicker()
        appearancePicker.onChange = { [weak self] in
            self?.applyActiveAppearance()
            self?.reconcileColony()       // worker change shifts who roams
        }
        appearancePicker.onCastingChange = { [weak self] in self?.reconcileColony() }
        appearancePicker.onImportPack = { [weak self] in self?.importPackAction() }
        appearancePicker.onNewFromImages = { [weak self] in self?.importAppearancesAction() }
        appearancePicker.onCopyPrompt = { [weak self] in self?.copyImagePromptAction() }
        appearancePicker.onOpenFolder = { [weak self] in self?.openAppearancesFolderAction() }

        controller.onDoubleClick = { [weak self] in self?.openActionPanel() }

        // Listen for events from the `mochi` CLI / Claude Code / Codex hooks.
        bridge = MochiBridge { [weak self] type, text in
            self?.controller.handleBridgeEvent(type: type, text: text)
        }
        bridge.start()

        // Auto-detect working agents by watching their transcript files. Covers
        // CLI, ACP, and the desktop apps (which don't fire shell hooks).
        monitor = AgentMonitor { [weak self] source, sessionID, active, detail, task in
            self?.controller.handleBridgeEvent(type: active ? "busy" : "done",
                                               text: source,
                                               detail: detail,
                                               sessionID: sessionID,
                                               task: task)
        }
        if UserDefaults.standard.object(forKey: monitorDefaultsKey) as? Bool ?? true {
            monitor.start()
        }

        controller.start()
        reconcileColony()   // spawn ambient roaming cats from the roamer set
        setupStatusItem()
        controller.say("双击我选动作", duration: 4.0)
        checkForUpdates(manual: false)
    }

    private func openActionPanel() {
        actionPanel.present(above: window.frame)
    }

    private func openAppearancePicker() {
        appearancePicker.present(near: window.frame)
    }

    /// Load the active pack's images into the state so the pet re-renders.
    private func applyActiveAppearance() {
        let loaded = AppearanceStore.loadActive()
        state.customAppearances = loaded.appearances
        state.customWalkFrames = loaded.walk
    }

    private func saveMemo(_ text: String) {
        do {
            try MemoStore.append(text)
            controller.say("记下啦", duration: 2.5)
        } catch {
            controller.say("备忘录写入失败，请看权限", duration: 4)
        }
    }

    private func openClaude() {
        controller.openAgentApp(.claude)
    }

    private func openCodex() {
        controller.openAgentApp(.codex)
    }

    private func openMemoFile() {
        MemoStore.open()
    }

    /// Last saved origin, but only if it's visible on a currently-connected
    /// screen (so unplugging a display doesn't strand the pet off-screen).
    private func restoredOrigin() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: "MochiPosX") != nil, d.object(forKey: "MochiPosY") != nil else {
            return nil
        }
        let p = NSPoint(x: d.double(forKey: "MochiPosX"), y: d.double(forKey: "MochiPosY"))
        let anchor = NSPoint(x: p.x + PetWindow.canvasSize.width / 2, y: p.y + 40)
        let onScreen = NSScreen.screens.contains { $0.frame.contains(anchor) }
        return onScreen ? p : nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.savePosition()
    }

    // MARK: - Window / colony

    private func buildAvatar() {
        avatar = PetUnit(role: .avatar)

        // Restore the last position if it's still on-screen; otherwise start
        // centered near the bottom of whichever screen the cursor is on.
        if let restored = restoredOrigin() {
            window.setFrameOrigin(restored)
        } else {
            let mouse = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                ?? NSScreen.main
            let screen = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            window.setFrameOrigin(NSPoint(x: screen.midX - PetWindow.canvasSize.width / 2,
                                          y: screen.minY + 80))
        }

        window.orderFrontRegardless()
    }

    /// Match the live ambient cats to the roamer set (≤ maxRoamers, excluding the
    /// working cat so it isn't duplicated). Adds/removes windows as casting changes.
    private func reconcileColony() {
        let active = AppearanceStore.activeSlug
        let installed = Set(AppearanceStore.installedPacks().map { $0.slug })
        let desired = Array(AppearanceStore.roamerSlugs
            .filter { $0 != active && installed.contains($0) }   // skip the worker + stale/deleted slugs
            .prefix(AppearanceStore.maxRoamers))
        let desiredSet = Set(desired)

        for (slug, unit) in ambients where !desiredSet.contains(slug) {
            unit.teardown()
            ambients.removeValue(forKey: slug)
        }
        for slug in desired where ambients[slug] == nil {
            let unit = PetUnit(role: .ambient)
            unit.applyAppearance(slug: slug)
            placeAmbient(unit.window)
            if !colonyHidden { unit.window.orderFrontRegardless() }
            unit.controller.start()
            ambients[slug] = unit
        }
    }

    /// Drop a new ambient cat at a random spot along the bottom of the cursor's
    /// screen; from there its own brain takes over and it roams.
    private func placeAmbient(_ window: PetWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?
            .visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxX = max(screen.minX, screen.maxX - PetWindow.canvasSize.width)
        let x = CGFloat.random(in: screen.minX...maxX)
        let y = screen.minY + CGFloat.random(in: 40...160)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍡"

        // Opening Claude/Codex and memos live on the double-click action panel
        // (and clicking a session bubble), so the menu stays focused on the pet.
        let menu = NSMenu()
        // Per-pet actions live on the pet itself now: single-click = 戳一下,
        // right-click = 跟随鼠标 / 睡觉·起床. The menu keeps only app-level items.

        // Everything appearance-related lives in the picker now (tiles for switch/
        // import/default + footer for prompt/folder), so this is just one item.
        let appearanceItem = NSMenuItem(title: "形象…", action: #selector(openPickerAction), keyEquivalent: "")
        appearanceItem.target = self
        menu.addItem(appearanceItem)

        let senseItem = NSMenuItem(title: "感知 AI 工作", action: #selector(toggleSenseAction(_:)), keyEquivalent: "")
        senseItem.state = (UserDefaults.standard.object(forKey: monitorDefaultsKey) as? Bool ?? true) ? .on : .off
        senseItem.target = self
        menu.addItem(senseItem)
        // 睡觉/起床 moved to the pet's right-click menu (per cat).
        menu.addItem(withTitle: "隐藏 / 显示", action: #selector(toggleVisibleAction), keyEquivalent: "")
        menu.addItem(withTitle: "检查更新…", action: #selector(checkUpdateAction), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Mochi", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { if $0.target == nil { $0.target = self } }

        statusItem.menu = menu
    }

    @objc private func toggleSenseAction(_ sender: NSMenuItem) {
        let on = sender.state != .on
        sender.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: monitorDefaultsKey)
        if on { monitor.start() } else { monitor.stop() }
        controller.say(on ? "我会盯着你的 AI 啦 👀" : "好，不盯了", duration: 2.5)
    }

    @objc private func openPickerAction() { openAppearancePicker() }

    @objc private func importPackAction() {
        let panel = NSOpenPanel()
        panel.title = "选择形象包文件夹"
        panel.message = "选一个形象包目录（含 companion/work/rest/slack/drag.png，以及可选的 walk/ 文件夹）。"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        NSApp.activate(ignoringOtherApps: true)
        appearancePicker.beginInternalDialog()
        defer { appearancePicker.endInternalDialog() }
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            let pack = try AppearanceStore.importPack(from: folder)   // adds + activates
            applyActiveAppearance()
            reconcileColony()
            appearancePicker.reload()
            controller.say("「\(pack.name)」装好啦~", duration: 2.5)
        } catch {
            controller.say("这个文件夹里没找到形象图 😣", duration: 3)
        }
    }

    @objc private func importAppearancesAction() {
        let panel = NSOpenPanel()
        panel.title = "选择形态图片做一套形象包"
        panel.message = "可多选；文件名含 工作/休息/摸鱼/陪伴 会自动匹配，否则按顺序填入。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .tiff, .gif]

        NSApp.activate(ignoringOtherApps: true)
        appearancePicker.beginInternalDialog()
        defer { appearancePicker.endInternalDialog() }
        guard panel.runModal() == .OK else { return }

        do {
            try AppearanceStore.newPack(fromImages: panel.urls)   // creates + activates
            applyActiveAppearance()
            reconcileColony()
            appearancePicker.reload()
            controller.say("形象包做好啦~", duration: 2.5)
        } catch {
            controller.say("这些图我读不了 😣", duration: 3)
        }
    }

    @objc private func copyImagePromptAction() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(AppearancePrompt.imageGen, forType: .string)
        controller.say("生图 Prompt 已复制，粘到生图模型就行~", duration: 3)
    }

    @objc private func openAppearancesFolderAction() {
        try? FileManager.default.createDirectory(at: AppearanceStore.packsDir,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppearanceStore.packsDir)
    }

    @objc private func toggleVisibleAction() {
        colonyHidden.toggle()
        let windows = [avatar.window] + ambients.values.map { $0.window }
        for w in windows {
            if colonyHidden { w.orderOut(nil) } else { w.orderFrontRegardless() }
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Update check

    @objc private func checkUpdateAction() { checkForUpdates(manual: true) }

    private func checkForUpdates(manual: Bool) {
        UpdateChecker.checkLatest { [weak self] release in
            guard let self = self else { return }
            if let release = release {
                self.presentUpdate(release)
            } else if manual {
                self.controller.say("已是最新版 v\(UpdateChecker.currentVersion)", duration: 3)
            }
        }
    }

    private func presentUpdate(_ release: UpdateChecker.Release) {
        latestReleaseURL = release.url
        let title = "🔔 有新版 v\(release.version)（点此下载）"
        if let item = updateMenuItem {
            item.title = title
        } else if let menu = statusItem.menu {
            let item = NSMenuItem(title: title, action: #selector(openLatestRelease), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            updateMenuItem = item
        }
        controller.say("有新版 v\(release.version)，菜单可下载 🔔", duration: 5)
    }

    @objc private func openLatestRelease() {
        if let s = latestReleaseURL, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
    }
}

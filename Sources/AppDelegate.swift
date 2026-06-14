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
    private let state = PetState()
    private var window: PetWindow!
    private var controller: PetController!
    private var statusItem: NSStatusItem!
    private var actionPanel: ActionPanel!
    private var bridge: MochiBridge!
    private var monitor: AgentMonitor!

    private let monitorDefaultsKey = "MochiSenseAgents"

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.customAppearances = AppearanceStore.loadAll()
        state.customWalkFrames = AppearanceStore.loadWalkFrames()
        setupWindow()
        controller = PetController(window: window, state: state)

        // Double-click action picker.
        actionPanel = ActionPanel()
        actionPanel.onOpenClaude = { [weak self] in self?.openClaude() }
        actionPanel.onOpenCodex = { [weak self] in self?.openCodex() }
        actionPanel.onOpenMemoFile = { [weak self] in self?.openMemoFile() }
        actionPanel.onSubmitMemo = { [weak self] text in self?.saveMemo(text) }

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
        setupStatusItem()
        controller.say("双击我选动作", duration: 4.0)
    }

    private func openActionPanel() {
        actionPanel.present(above: window.frame)
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

    // MARK: - Window

    private func setupWindow() {
        window = PetWindow()

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

        let host = NSHostingView(rootView: PetView(state: state))
        host.frame = window.container.bounds
        host.autoresizingMask = [.width, .height]
        window.container.addSubview(host)

        window.orderFrontRegardless()
    }

    // MARK: - Status bar menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🍡"

        // Opening Claude/Codex and memos live on the double-click action panel
        // (and clicking a session bubble), so the menu stays focused on the pet.
        let menu = NSMenu()
        menu.addItem(withTitle: "戳一下 Mochi", action: #selector(pokeAction), keyEquivalent: "")
        menu.addItem(withTitle: "跟随鼠标", action: #selector(toggleFollowAction(_:)), keyEquivalent: "")

        let appearanceItem = NSMenuItem(title: "形象", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        appearanceMenu.addItem(withTitle: "导入形态图片…", action: #selector(importAppearancesAction), keyEquivalent: "")
        appearanceMenu.addItem(withTitle: "打开形态文件夹", action: #selector(openAppearancesFolderAction), keyEquivalent: "")
        appearanceMenu.addItem(withTitle: "恢复默认 Mochi", action: #selector(resetAppearanceAction), keyEquivalent: "")
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        let senseItem = NSMenuItem(title: "感知 AI 工作", action: #selector(toggleSenseAction(_:)), keyEquivalent: "")
        senseItem.state = (UserDefaults.standard.object(forKey: monitorDefaultsKey) as? Bool ?? true) ? .on : .off
        senseItem.target = self
        menu.addItem(senseItem)
        menu.addItem(withTitle: "睡觉 / 起床", action: #selector(sleepAction), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏 / 显示", action: #selector(toggleVisibleAction), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Mochi", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { if $0.target == nil { $0.target = self } }

        statusItem.menu = menu
    }

    @objc private func toggleFollowAction(_ sender: NSMenuItem) {
        let on = !controller.isFollowing
        controller.setFollowing(on)
        sender.state = on ? .on : .off
    }

    @objc private func toggleSenseAction(_ sender: NSMenuItem) {
        let on = sender.state != .on
        sender.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: monitorDefaultsKey)
        if on { monitor.start() } else { monitor.stop() }
        controller.say(on ? "我会盯着你的 AI 啦 👀" : "好，不盯了", duration: 2.5)
    }

    @objc private func importAppearancesAction() {
        let panel = NSOpenPanel()
        panel.title = "选择 Mochi 的形态图片"
        panel.message = "可多选；文件名含 工作/休息/摸鱼/陪伴 会自动匹配，否则按顺序填入。"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .tiff, .gif]

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        do {
            let saved = try AppearanceStore.saveMany(from: panel.urls)
            state.customAppearances.merge(saved) { _, new in new }
            controller.say("形态包导入好啦~", duration: 2.5)
        } catch {
            controller.say("这些图我读不了 😣", duration: 3)
        }
    }

    @objc private func openAppearancesFolderAction() {
        try? FileManager.default.createDirectory(at: AppearanceStore.appearancesDir,
                                                 withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppearanceStore.appearancesDir)
    }

    @objc private func resetAppearanceAction() {
        AppearanceStore.clear()
        state.customAppearances = [:]
        state.customWalkFrames = []
        controller.say("恢复默认 Mochi 啦", duration: 2.5)
    }

    @objc private func pokeAction() {
        controller.poke()
    }

    @objc private func sleepAction() {
        controller.toggleSleep()
    }

    @objc private func toggleVisibleAction() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

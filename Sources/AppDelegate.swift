//
//  AppDelegate.swift
//  Mochi
//
//  Wires everything together: creates the floating pet window, hosts the
//  SwiftUI view inside it, builds the status-bar menu, and starts the brain.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = PetState()
    private var window: PetWindow!
    private var controller: PetController!
    private var statusItem: NSStatusItem!
    private var chatPanel: ChatInputPanel!
    private var bridge: MochiBridge!
    private var monitor: AgentMonitor!

    private let engineDefaultsKey = "MochiAIEngine"
    private let monitorDefaultsKey = "MochiSenseAgents"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        controller = PetController(window: window, state: state)

        // Restore the saved AI engine choice.
        if let raw = UserDefaults.standard.string(forKey: engineDefaultsKey),
           let saved = AIEngine(rawValue: raw) {
            controller.engine = saved
        }

        // Talking to Mochi.
        chatPanel = ChatInputPanel()
        chatPanel.onSubmit = { [weak self] text in self?.controller.ask(text) }
        controller.onRequestChat = { [weak self] in self?.openChat() }

        // Listen for events from the `mochi` CLI / Claude Code / Codex hooks.
        bridge = MochiBridge { [weak self] type, text in
            self?.controller.handleBridgeEvent(type: type, text: text)
        }
        bridge.start()

        // Auto-detect working agents by watching their transcript files. Covers
        // CLI, ACP, and the desktop apps (which don't fire shell hooks).
        monitor = AgentMonitor { [weak self] source, active in
            self?.controller.handleBridgeEvent(type: active ? "busy" : "done", text: source)
        }
        if UserDefaults.standard.object(forKey: monitorDefaultsKey) as? Bool ?? true {
            monitor.start()
        }

        controller.start()
        setupStatusItem()
        controller.say("你好! 我是 Mochi 🍡 双击我聊天", duration: 4.0)
    }

    private func openChat() {
        chatPanel.present(above: window.frame)
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

        let menu = NSMenu()
        menu.addItem(withTitle: "跟 Mochi 说话…", action: #selector(chatAction), keyEquivalent: "")
        menu.addItem(withTitle: "忘掉刚才的对话", action: #selector(clearHistoryAction), keyEquivalent: "")
        menu.addItem(withTitle: "戳一下 Mochi", action: #selector(pokeAction), keyEquivalent: "")
        menu.addItem(withTitle: "跟随鼠标", action: #selector(toggleFollowAction(_:)), keyEquivalent: "")

        let senseItem = NSMenuItem(title: "感知 AI 工作", action: #selector(toggleSenseAction(_:)), keyEquivalent: "")
        senseItem.state = (UserDefaults.standard.object(forKey: monitorDefaultsKey) as? Bool ?? true) ? .on : .off
        senseItem.target = self
        menu.addItem(senseItem)
        menu.addItem(withTitle: "睡觉 / 起床", action: #selector(sleepAction), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏 / 显示", action: #selector(toggleVisibleAction), keyEquivalent: "")

        // AI engine submenu.
        let engineItem = NSMenuItem(title: "AI 引擎", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for engine in AIEngine.allCases {
            let item = NSMenuItem(title: engine.displayName,
                                  action: #selector(selectEngineAction(_:)), keyEquivalent: "")
            item.representedObject = engine.rawValue
            item.state = (controller.engine == engine) ? .on : .off
            item.target = self
            engineMenu.addItem(item)
        }
        engineItem.submenu = engineMenu
        menu.addItem(.separator())
        menu.addItem(engineItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Mochi", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { if $0.target == nil { $0.target = self } }

        statusItem.menu = menu
    }

    @objc private func chatAction() {
        openChat()
    }

    @objc private func clearHistoryAction() {
        controller.clearHistory()
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

    @objc private func selectEngineAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = AIEngine(rawValue: raw) else { return }
        controller.engine = engine
        UserDefaults.standard.set(raw, forKey: engineDefaultsKey)
        // Refresh checkmarks.
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        controller.say("好的，改用 \(engine.displayName) 啦", duration: 2.5)
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

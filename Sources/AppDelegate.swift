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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        controller = PetController(window: window, state: state)
        controller.start()
        setupStatusItem()
        controller.say("你好! 我是 Mochi 🍡", duration: 3.5)
    }

    // MARK: - Window

    private func setupWindow() {
        window = PetWindow()

        // Start centered horizontally, sitting near the bottom of whichever
        // screen the cursor is currently on (falls back to the main screen).
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        let screen = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.midX - PetWindow.canvasSize.width / 2,
                             y: screen.minY + 80)
        window.setFrameOrigin(origin)

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
        menu.addItem(withTitle: "戳一下 Mochi", action: #selector(pokeAction), keyEquivalent: "")
        menu.addItem(withTitle: "睡觉 / 起床", action: #selector(sleepAction), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏 / 显示", action: #selector(toggleVisibleAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Mochi", action: #selector(quitAction), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
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

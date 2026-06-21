//
//  PetColony.swift
//  Mochi
//
//  One cat = one `PetUnit`: its window, its render state, and its brain bundled
//  together. The app runs a single `avatar` unit (the working cat that senses
//  agents and shows status bubbles) plus zero or more `ambient` units that just
//  roam the screen. The colony is reconciled in AppDelegate from the appearance
//  library's active pack (the worker) and roamer set (the ambient cats).
//

import AppKit
import SwiftUI

final class PetUnit {
    let state = PetState()
    let window = PetWindow()
    let controller: PetController

    init(role: PetController.Role) {
        let host = NSHostingView(rootView: PetView(state: state))
        host.frame = window.container.bounds
        host.autoresizingMask = [.width, .height]
        window.container.addSubview(host)
        controller = PetController(window: window, state: state, role: role)
    }

    /// Load a pack's images into this cat (empty slug → built-in vector Mochi).
    func applyAppearance(slug: String) {
        let loaded = AppearanceStore.load(slug: slug)
        state.customAppearances = loaded.appearances
        state.customWalkFrames = loaded.walk
    }

    /// Stop the brain and hide the window — used when an ambient cat is removed.
    func teardown() {
        controller.stop()
        window.orderOut(nil)
    }
}

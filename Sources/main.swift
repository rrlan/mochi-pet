//
//  main.swift
//  Mochi — a tiny desktop pet for macOS
//
//  Application entry point. We drive the app with the AppKit lifecycle
//  (NSApplication) rather than the SwiftUI App lifecycle, because we need
//  fine-grained control over a borderless, transparent, click-through-aware
//  floating window — which is far easier with AppKit.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// `.accessory` => no Dock icon, no menu bar app menu; the pet lives as a
// floating companion controlled from a status-bar item.
app.setActivationPolicy(.accessory)
app.run()

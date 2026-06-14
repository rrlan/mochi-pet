//
//  MochiBridge.swift
//  Mochi
//
//  A tiny one-way IPC channel so external tools — Claude Code / Codex hooks,
//  scripts, or the `mochi` CLI — can make the pet react to what you're doing.
//
//  Protocol: append one event per line to ~/.mochi/inbox.log. The first token
//  is the event type, the rest is free text:
//
//      busy                 → Mochi enters "working" mode
//      done [message]       → Mochi celebrates + posts a notification
//      say <text>           → Mochi says something
//      alert <text>         → Mochi warns + posts a notification
//
//  Mochi polls the file (cheap, rock-solid, no entitlements) and only reads
//  bytes appended after launch.
//

import Foundation

final class MochiBridge {
    /// ~/.mochi (override with MOCHI_HOME).
    static var homeDir: URL {
        if let env = ProcessInfo.processInfo.environment["MOCHI_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mochi")
    }

    private var inboxURL: URL { MochiBridge.homeDir.appendingPathComponent("inbox.log") }

    private let onEvent: (_ type: String, _ text: String) -> Void
    private var timer: Timer?
    private var offset: UInt64 = 0

    init(onEvent: @escaping (_ type: String, _ text: String) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        try? FileManager.default.createDirectory(at: MochiBridge.homeDir,
                                                 withIntermediateDirectories: true)
        offset = currentSize()   // ignore anything already in the log
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func currentSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: inboxURL.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func poll() {
        let size = currentSize()
        if size < offset { offset = 0 }          // file truncated/rotated
        guard size > offset, let handle = try? FileHandle(forReadingFrom: inboxURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = size
        guard let text = String(data: data, encoding: .utf8) else { return }

        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            onEvent(parts[0], parts.count > 1 ? parts[1] : "")
        }
    }
}

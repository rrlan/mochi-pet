//
//  AgentMonitor.swift
//  Mochi
//
//  Detects when AI coding agents are actively working by watching the session
//  transcript files they write. This is the only signal that works uniformly
//  across ALL surfaces — CLI, ACP, and crucially the desktop apps (Claude Code
//  desktop, Codex App) which do NOT fire shell hooks:
//
//      claude → ~/.claude/projects/**/*.jsonl
//      codex  → ~/.codex/sessions/**/*.jsonl
//
//  A transcript that's actively growing = that agent is mid-turn. When it stops
//  growing for `quietWindow` seconds, the turn is considered finished. (CPU is
//  useless here — LLM generation is network-bound, near-zero CPU.)
//
//  All scanning runs on a background serial queue; callbacks fire on main.
//

import Foundation

final class AgentMonitor {
    private struct Watch {
        let label: String
        let root: URL
    }

    private let watches: [Watch]
    private let onChange: (_ source: String, _ active: Bool) -> Void
    /// How long a transcript must be quiet before we call the turn finished.
    /// Generous, to ride over long no-tool "thinking" gaps within a turn.
    private let quietWindow: TimeInterval = 15

    private let queue = DispatchQueue(label: "com.yangran.mochi.agentmonitor", qos: .utility)
    private var running = false

    private var newestSeen: [String: TimeInterval] = [:]
    private var lastGrowth: [String: TimeInterval] = [:]
    private var active: Set<String> = []

    init(onChange: @escaping (_ source: String, _ active: Bool) -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.watches = [
            Watch(label: "claude", root: home.appendingPathComponent(".claude/projects")),
            Watch(label: "codex", root: home.appendingPathComponent(".codex/sessions")),
        ]
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Seed baselines so pre-existing transcripts don't count as activity.
            for w in self.watches { self.newestSeen[w.label] = self.newestMtime(under: w.root) }
            self.running = true
            self.scheduleTick()
        }
    }

    func stop() {
        queue.async { [weak self] in self?.running = false }
    }

    private func scheduleTick() {
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.running else { return }
            self.tick()
            self.scheduleTick()
        }
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        for w in watches {
            let newest = newestMtime(under: w.root)
            let prev = newestSeen[w.label] ?? 0
            if newest > prev + 0.001 {
                newestSeen[w.label] = newest
                lastGrowth[w.label] = now
                if !active.contains(w.label) {
                    active.insert(w.label)
                    emit(w.label, true)
                }
            } else if active.contains(w.label) {
                if now - (lastGrowth[w.label] ?? 0) > quietWindow {
                    active.remove(w.label)
                    emit(w.label, false)
                }
            }
        }
    }

    private func emit(_ source: String, _ isActive: Bool) {
        DispatchQueue.main.async { [onChange] in onChange(source, isActive) }
    }

    /// Newest modification time among *.jsonl files under `root` (0 if none).
    private func newestMtime(under root: URL) -> TimeInterval {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var maxT: TimeInterval = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  vals.isRegularFile == true,
                  let date = vals.contentModificationDate else { continue }
            let t = date.timeIntervalSince1970
            if t > maxT { maxT = t }
        }
        return maxT
    }
}

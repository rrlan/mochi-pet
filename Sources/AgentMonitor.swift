//
//  AgentMonitor.swift
//  Mochi
//
//  Detects when AI coding agents are actively working — and *what* they're
//  doing — by watching the session transcript files they write. This is the
//  only signal that works uniformly across ALL surfaces: CLI, ACP, and the
//  desktop apps (Claude Code desktop, Codex App), which do NOT fire shell hooks.
//
//      claude → ~/.claude/projects/**/*.jsonl
//      codex  → ~/.codex/sessions/**/*.jsonl
//
//  A transcript that's actively growing = that agent is mid-turn. We tail the
//  newest file and parse the latest entry into a short "current activity" line
//  (e.g. "运行 npm test", "编辑 PetView.swift", "💬 …"). When the file stays
//  quiet for `quietWindow` seconds, the turn is considered finished.
//
//  All scanning/parsing runs on a background serial queue; callbacks fire on main.
//

import Foundation

final class AgentMonitor {
    private struct Watch {
        let label: String
        let root: URL
    }

    /// (source, isActive, detail) — detail is the current activity line, or nil.
    private let onChange: (_ source: String, _ active: Bool, _ detail: String?) -> Void
    private let watches: [Watch]
    private let quietWindow: TimeInterval = 15

    private let queue = DispatchQueue(label: "com.yangran.mochi.agentmonitor", qos: .utility)
    private var running = false

    private var newestSeen: [String: TimeInterval] = [:]
    private var lastGrowth: [String: TimeInterval] = [:]
    private var active: Set<String> = []

    init(onChange: @escaping (_ source: String, _ active: Bool, _ detail: String?) -> Void) {
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
            for w in self.watches { self.newestSeen[w.label] = self.newestFile(under: w.root).1 }
            self.running = true
            self.scheduleTick()
        }
    }

    func stop() { queue.async { [weak self] in self?.running = false } }

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
            let (url, mtime) = newestFile(under: w.root)
            let prev = newestSeen[w.label] ?? 0
            if mtime > prev + 0.001 {
                newestSeen[w.label] = mtime
                lastGrowth[w.label] = now
                active.insert(w.label)
                let detail = url.flatMap { activity(in: $0, label: w.label) }
                emit(w.label, true, detail)        // emit on every growth → live detail
            } else if active.contains(w.label),
                      now - (lastGrowth[w.label] ?? 0) > quietWindow {
                active.remove(w.label)
                emit(w.label, false, nil)
            }
        }
    }

    private func emit(_ source: String, _ isActive: Bool, _ detail: String?) {
        DispatchQueue.main.async { [onChange] in onChange(source, isActive, detail) }
    }

    // MARK: - Finding the newest transcript

    private func newestFile(under root: URL) -> (URL?, TimeInterval) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return (nil, 0) }
        var best: URL?
        var bestT: TimeInterval = 0
        for case let url as URL in en {
            guard url.pathExtension == "jsonl",
                  let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  v.isRegularFile == true, let d = v.contentModificationDate else { continue }
            let t = d.timeIntervalSince1970
            if t > bestT { bestT = t; best = url }
        }
        return (best, bestT)
    }

    // MARK: - Activity parsing

    /// Read the tail of a transcript and describe the latest action.
    private func activity(in url: URL, label: String) -> String? {
        let lines = tailLines(of: url)
        return label == "codex" ? parseCodex(lines) : parseClaude(lines)
    }

    private func tailLines(of url: URL, maxBytes: UInt64 = 48_000) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > maxBytes ? size - maxBytes : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        guard let s = String(data: data, encoding: .utf8) else { return [] }
        var lines = s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // drop partial first line
        return lines
    }

    private func obj(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private func parseClaude(_ lines: [String]) -> String? {
        for line in lines.reversed() {
            guard let o = obj(line), o["type"] as? String == "assistant",
                  let msg = o["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            for c in content where c["type"] as? String == "tool_use" {
                return describeClaudeTool(c["name"] as? String ?? "工具",
                                          c["input"] as? [String: Any] ?? [:])
            }
            for c in content where c["type"] as? String == "text" {
                if let t = c["text"] as? String, !t.isEmpty { return "💬 " + snippet(t) }
            }
        }
        return nil
    }

    private func describeClaudeTool(_ name: String, _ input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { base($0) }
        switch name {
        case "Bash":            return "运行 " + snippet(input["command"] as? String ?? "")
        case "Edit", "Write", "NotebookEdit":
            return "编辑 " + (file ?? "文件")
        case "Read":            return "读取 " + (file ?? "文件")
        case "Grep":            return "搜索 " + snippet(input["pattern"] as? String ?? "")
        case "Glob":            return "查找文件…"
        case "Task", "Agent":   return "调度子任务…"
        case "WebFetch", "WebSearch": return "上网查资料…"
        case "AskUserQuestion": return "等你回答…"
        case "TodoWrite":       return "整理任务清单…"
        default:                return name
        }
    }

    private func parseCodex(_ lines: [String]) -> String? {
        for line in lines.reversed() {
            guard let o = obj(line) else { continue }
            let payload = o["payload"] as? [String: Any] ?? o
            let pt = payload["type"] as? String
            switch pt {
            case "function_call":
                let name = payload["name"] as? String ?? "工具"
                let cmd = codexCmd(payload["arguments"])
                if name == "exec_command" || name == "shell" || name == "local_shell_call" {
                    return "运行 " + snippet(cmd)
                }
                if name.contains("patch") || name.contains("apply") { return "编辑文件…" }
                return name + (cmd.isEmpty ? "" : " " + snippet(cmd))
            case "message":
                if let content = payload["content"] as? [[String: Any]] {
                    for c in content { if let t = c["text"] as? String, !t.isEmpty { return "💬 " + snippet(t) } }
                }
            case "agent_message":
                if let m = payload["message"] as? String, !m.isEmpty { return "💬 " + snippet(m) }
            case "reasoning":
                return "🤔 思考中…"
            default:
                continue
            }
        }
        return nil
    }

    private func codexCmd(_ arguments: Any?) -> String {
        guard let s = arguments as? String, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "" }
        if let cmd = o["cmd"] as? String { return cmd }
        if let cmd = o["command"] as? String { return cmd }
        if let arr = o["command"] as? [Any] { return arr.map { "\($0)" }.joined(separator: " ") }
        return ""
    }

    // MARK: - Helpers

    private func base(_ path: String) -> String { (path as NSString).lastPathComponent }

    private func snippet(_ text: String, _ limit: Int = 30) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return oneLine.count <= limit ? oneLine : String(oneLine.prefix(limit)) + "…"
    }
}

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

    private struct Candidate {
        let url: URL
        let modifiedAt: TimeInterval
    }

    /// (source, sessionID, isActive, detail, task) — one visible bubble per
    /// session; `task` is a short name for the session (its project folder).
    private let onChange: (_ source: String, _ sessionID: String, _ active: Bool, _ detail: String?, _ task: String?) -> Void
    private let watches: [Watch]
    private let quietWindow: TimeInterval = 15

    private let queue = DispatchQueue(label: "com.yangran.mochi.agentmonitor", qos: .utility)
    private var running = false

    private var seenModifiedAt: [String: TimeInterval] = [:]
    private var lastGrowth: [String: TimeInterval] = [:]
    private var sessionFiles: [String: URL] = [:]
    private var active: Set<String> = []
    /// Cache of resolved "label:id" by file path — the id never changes, and
    /// re-reading a multi-KB Codex meta line every tick would be wasteful.
    private var sessionIDCache: [String: String] = [:]
    /// Cache of a session's task name (project folder) by file path.
    private var taskNameCache: [String: String] = [:]
    private var projectCache: [String: String] = [:]
    /// Claude desktop session titles by uuid (refreshed from its log), and when.
    private var sessionTitles: [String: (title: String, userRenamed: Bool)] = [:]
    private var sessionTitlesCheckedAt: TimeInterval = 0

    init(onChange: @escaping (_ source: String, _ sessionID: String, _ active: Bool, _ detail: String?, _ task: String?) -> Void) {
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
            for w in self.watches {
                for candidate in self.recentFiles(under: w.root) {
                    self.seenModifiedAt[self.fileID(label: w.label, url: candidate.url)] = candidate.modifiedAt
                }
            }
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
            for candidate in recentFiles(under: w.root) {
                let fileID = fileID(label: w.label, url: candidate.url)
                let sessionID = sessionID(label: w.label, url: candidate.url)
                sessionFiles[sessionID] = candidate.url
                let prev = seenModifiedAt[fileID] ?? 0
                if candidate.modifiedAt > prev + 0.001 {
                    seenModifiedAt[fileID] = candidate.modifiedAt
                    lastGrowth[sessionID] = now
                    active.insert(sessionID)
                    let detail = activity(in: candidate.url, label: w.label)
                    let task = taskName(label: w.label, url: candidate.url)
                    emit(w.label, sessionID, true, detail, task)   // every growth → live detail
                }
            }

            for sessionID in Array(active) where sessionID.hasPrefix(w.label + ":") {
                if now - (lastGrowth[sessionID] ?? 0) > quietWindow {
                    if let url = sessionFiles[sessionID],
                       isProbablyWaitingForPermission(in: url, label: w.label) {
                        emit(w.label, sessionID, true, "等你允许…", taskName(label: w.label, url: url))
                        continue
                    }
                    active.remove(sessionID)
                    emit(w.label, sessionID, false, nil, nil)
                }
            }
        }
    }

    private func emit(_ source: String, _ sessionID: String, _ isActive: Bool, _ detail: String?, _ task: String?) {
        DispatchQueue.main.async { [onChange] in onChange(source, sessionID, isActive, detail, task) }
    }

    // MARK: - Finding active transcripts

    private func recentFiles(under root: URL) -> [Candidate] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = Date().timeIntervalSince1970 - 120
        var files: [Candidate] = []
        for case let url as URL in en {
            guard url.pathExtension == "jsonl",
                  let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  v.isRegularFile == true, let d = v.contentModificationDate else { continue }
            let t = d.timeIntervalSince1970
            if t >= cutoff {
                files.append(Candidate(url: url, modifiedAt: t))
            }
        }
        return files.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8).map { $0 }
    }

    private func fileID(label: String, url: URL) -> String {
        label + ":" + url.path
    }

    private func sessionID(label: String, url: URL) -> String {
        if let cached = sessionIDCache[url.path] { return cached }
        if let id = transcriptSessionID(in: url, label: label) {
            let sid = label + ":" + id
            sessionIDCache[url.path] = sid          // immutable → cache it
            return sid
        }
        return fileID(label: label, url: url)        // meta not ready yet; retry next tick
    }

    private func transcriptSessionID(in url: URL, label: String) -> String? {
        // Both Claude and Codex put the id on the very first line. We must read
        // the *whole* first line: Codex's `session_meta` (with base_instructions
        // + dynamic_tools) can exceed 34 KB, so a fixed-size head read would
        // truncate it mid-JSON and silently fail to parse.
        guard let line = firstLine(of: url), let o = obj(line) else { return nil }
        if label == "claude", let id = o["sessionId"] as? String, !id.isEmpty {
            return id
        }
        if label == "codex",
           o["type"] as? String == "session_meta",
           let payload = o["payload"] as? [String: Any],
           let id = payload["id"] as? String,
           !id.isEmpty {
            return id
        }
        return nil
    }

    /// A short title for a session to tell apart sibling sessions in the same
    /// folder: the session's first *real* user prompt (e.g. "整体review代码"),
    /// falling back to the project folder name. Cached once a prompt is found.
    private func taskName(label: String, url: URL) -> String? {
        // A user-renamed Claude-desktop title wins, shown as "<project> - <title>".
        // Re-checked every tick since the user can rename at any time.
        if let renamed = renamedTitle(label: label, url: url) {
            if let project = projectName(label: label, url: url) { return "\(project) - \(renamed)" }
            return renamed
        }
        if let cached = taskNameCache[url.path] { return cached }
        if let prompt = firstPrompt(label: label, url: url) {
            taskNameCache[url.path] = prompt
            return prompt
        }
        return projectName(label: label, url: url)   // not cached → keep trying for the prompt
    }

    /// The working-directory's folder name (e.g. "desk-pet"). Cached.
    private func projectName(label: String, url: URL) -> String? {
        if let cached = projectCache[url.path] { return cached }
        let cwd: String?
        if label == "codex" {
            cwd = firstLine(of: url).flatMap { obj($0) }
                .flatMap { ($0["payload"] as? [String: Any])?["cwd"] as? String }
        } else {
            cwd = headLines(of: url).lazy.compactMap { self.obj($0)?["cwd"] as? String }.first
        }
        guard let cwd = cwd, !cwd.isEmpty else { return nil }
        let name = (cwd as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        projectCache[url.path] = name
        return name
    }

    /// A user-renamed Claude-desktop session title (`titleSource:user`). The
    /// title isn't in the transcript, so we read it from the desktop app's log.
    /// nil for Codex or sessions the user hasn't renamed.
    private func renamedTitle(label: String, url: URL) -> String? {
        guard label == "claude" else { return nil }
        refreshClaudeTitlesIfStale()
        let uuid = url.deletingPathExtension().lastPathComponent
        if let entry = sessionTitles[uuid], entry.userRenamed { return entry.title }
        return nil
    }

    private func refreshClaudeTitlesIfStale() {
        let now = Date().timeIntervalSince1970
        guard now - sessionTitlesCheckedAt > 15 else { return }
        sessionTitlesCheckedAt = now
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude/main.log")
        guard let h = try? FileHandle(forReadingFrom: log) else { return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let cap: UInt64 = 800_000
        try? h.seek(toOffset: size > cap ? size - cap : 0)
        let data = (try? h.readToEnd()) ?? Data()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n")
        where line.contains("Updated session local_") && line.contains("titleSource:") {
            parseTitleLine(String(line))
        }
    }

    // Parses: `Updated session local_<uuid>: { title: '<title>', titleSource: '<source>' }`
    private func parseTitleLine(_ line: String) {
        guard let idStart = line.range(of: "local_"),
              let titleStart = line.range(of: "title: '"),
              let titleEnd = line.range(of: "', titleSource: '", range: titleStart.upperBound..<line.endIndex),
              let srcEnd = line.range(of: "'", range: titleEnd.upperBound..<line.endIndex) else { return }
        let uuid = String(line[idStart.upperBound...].prefix(36))
        let title = String(line[titleStart.upperBound..<titleEnd.lowerBound])
        let source = String(line[titleEnd.upperBound..<srcEnd.lowerBound])
        guard !uuid.isEmpty, !title.isEmpty else { return }
        sessionTitles[uuid] = (title, source == "user")
    }

    /// The first user message that's an actual prompt — skipping injected
    /// context (system reminders, the Codex AGENTS.md/<INSTRUCTIONS> block).
    private func firstPrompt(label: String, url: URL) -> String? {
        for line in headLines(of: url) {
            guard let o = obj(line), let raw = userMessageText(o, label: label),
                  let cleaned = cleanedPrompt(raw) else { continue }
            // The bubble truncates it to fit; the hover tooltip shows the whole
            // ~28-char snippet — enough to tell sessions apart.
            return snippet(cleaned, 28)
        }
        return nil
    }

    private func userMessageText(_ o: [String: Any], label: String) -> String? {
        if label == "claude" {
            guard o["type"] as? String == "user",
                  let msg = o["message"] as? [String: Any] else { return nil }
            if let s = msg["content"] as? String { return s }
            if let arr = msg["content"] as? [[String: Any]] {
                for b in arr where b["type"] as? String == "text" {
                    if let t = b["text"] as? String { return t }
                }
            }
            return nil
        }
        let p = o["payload"] as? [String: Any] ?? o
        guard p["role"] as? String == "user" else { return nil }
        if let s = p["content"] as? String { return s }
        if let arr = p["content"] as? [[String: Any]] {
            for b in arr { if let t = b["text"] as? String { return t } }
        }
        return nil
    }

    private func cleanedPrompt(_ text: String) -> String? {
        var t = text
        if let r = t.range(of: "</system-reminder>", options: .backwards) {
            t = String(t[r.upperBound...])               // reminders are prepended; keep what follows
        }
        if t.contains("<INSTRUCTIONS>") || t.contains("AGENTS.md instructions for") { return nil }
        let collapsed = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.count >= 2 ? collapsed : nil
    }

    /// Read the head of a transcript as complete lines. Generous byte cap so the
    /// Codex meta line + injected instructions don't crowd out the real prompt.
    private func headLines(of url: URL, byteCap: Int = 400_000, maxLines: Int = 50) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: byteCap)) ?? Data()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(maxLines)
            .map(String.init)
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

    /// Read the first complete line (up to the first newline), reading in chunks
    /// so an arbitrarily large first line — e.g. Codex's session_meta — is never
    /// truncated mid-JSON. `hardCap` bounds the read if a file has no newline.
    private func firstLine(of url: URL, hardCap: Int = 1_048_576) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var buffer = Data()
        while buffer.count < hardCap {
            guard let chunk = try? h.read(upToCount: 65_536), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let nl = buffer.firstIndex(of: 0x0A) {            // 0x0A == "\n"
                return String(data: buffer[..<nl], encoding: .utf8)
            }
        }
        return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
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
                if let t = c["text"] as? String, !t.isEmpty { return messageSnippet(t) }
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
                    for c in content { if let t = c["text"] as? String, !t.isEmpty { return messageSnippet(t) } }
                }
            case "agent_message":
                if let m = payload["message"] as? String, !m.isEmpty { return messageSnippet(m) }
            case "reasoning":
                return "🤔 思考中…"
            default:
                continue
            }
        }
        return nil
    }

    /// If a transcript went quiet immediately after an agent requested a tool,
    /// the desktop app is often waiting for the user's permission. We keep the
    /// bubble visible so Mochi can act as the approval target.
    private func isProbablyWaitingForPermission(in url: URL, label: String) -> Bool {
        let lines = tailLines(of: url)
        return label == "codex"
            ? codexHasPendingPermission(lines)
            : claudeHasPendingPermission(lines)
    }

    private func codexHasPendingPermission(_ lines: [String]) -> Bool {
        for line in lines.reversed() {
            guard let o = obj(line) else { continue }
            let payload = o["payload"] as? [String: Any] ?? o
            guard let type = payload["type"] as? String else { continue }
            switch type {
            case "function_call", "custom_tool_call":
                let name = payload["name"] as? String ?? ""
                return codexToolNeedsPermission(name)
            case "function_call_output", "custom_tool_call_output", "patch_apply_end":
                return false
            case "message", "agent_message":
                return false
            default:
                continue
            }
        }
        return false
    }

    private func codexToolNeedsPermission(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "exec_command"
            || lower == "shell"
            || lower == "local_shell_call"
            || lower.contains("patch")
            || lower.contains("apply")
    }

    private func claudeHasPendingPermission(_ lines: [String]) -> Bool {
        for line in lines.reversed() {
            guard let o = obj(line), let type = o["type"] as? String else { continue }
            if type == "user", claudeUserHasToolResult(o) { return false }
            guard type == "assistant",
                  let msg = o["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            for c in content where c["type"] as? String == "tool_use" {
                return claudeToolNeedsPermission(c["name"] as? String ?? "")
            }
            return false
        }
        return false
    }

    private func claudeUserHasToolResult(_ object: [String: Any]) -> Bool {
        guard let msg = object["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "tool_result" }
    }

    private func claudeToolNeedsPermission(_ name: String) -> Bool {
        switch name {
        case "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "WebSearch":
            return true
        default:
            return false
        }
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

    /// A 💬 chat-message line with light markdown stripped (so `**x**` etc. don't
    /// show raw in the bubble).
    private func messageSnippet(_ text: String) -> String {
        var t = text
        for token in ["**", "__", "*", "`", "#"] { t = t.replacingOccurrences(of: token, with: "") }
        return "💬 " + snippet(t)
    }
}

//
//  PetController.swift
//  Mochi
//
//  The pet's "brain". Owns the autonomy state machine (idle ↔ walk ↔ sleep),
//  responds to user interaction (poke/drag), and animates window movement when
//  the pet decides to stroll across the screen.
//

import AppKit
import ApplicationServices

final class PetController {
    private struct WorkSession {
        let id: String
        let source: String
        var detail: String?
        var taskName: String?
        let startedAt: Date
        /// nil while actively working; set when the session goes idle. The bubble
        /// is then kept (dimmed, still clickable) until the grace period lapses.
        var finishedAt: Date? = nil
    }

    /// How long a finished session's bubble stays clickable before it vanishes.
    private let finishedGrace: TimeInterval = 180

    private weak var window: PetWindow?
    private let state: PetState

    private var brainTimer: Timer?
    private var walkTimer: Timer?
    private var blinkTimer: Timer?
    private var followTimer: Timer?

    private(set) var isFollowing = false
    private let posKeyX = "MochiPosX"
    private let posKeyY = "MochiPosY"

    /// Called when the user double-clicks the pet.
    var onDoubleClick: (() -> Void)?

    /// True while waiting on an AI reply (suppresses autonomy).
    private var isBusy = false

    /// Horizontal target the pet is walking toward (in screen coordinates).
    private var targetX: CGFloat = 0
    /// Walk speed in points per tick (~60 ticks/sec).
    private let speed: CGFloat = 1.4

    private(set) var isSleeping = false

    /// Last time anything happened — an agent ran, or the user interacted. After
    /// `restAfterIdle` of nothing, the pet naps (sleep state → `rest.png`).
    private var lastActivityAt = Date()
    private let restAfterIdle: TimeInterval = 900   // 15 minutes

    init(window: PetWindow, state: PetState) {
        self.window = window
        self.state = state
    }

    // MARK: - Lifecycle

    func start() {
        window?.container.onPoke = { [weak self] in self?.poke() }
        window?.container.onChat = { [weak self] in self?.onDoubleClick?() }
        window?.container.onBubbleClick = { [weak self] target in
            if target.requiresApproval {
                self?.approveAgentSession(source: target.source, sessionID: target.sessionID)
            } else {
                self?.openAgentSession(source: target.source, sessionID: target.sessionID)
            }
        }
        window?.container.onDragStart = { [weak self] in self?.beginDrag() }
        window?.container.onDragEnd = { [weak self] in self?.endDrag() }
        scheduleBrain()
        scheduleBlink()
    }

    // MARK: - Idle "brain" loop

    private func scheduleBrain() {
        let interval = Double.random(in: 3.0...7.0)
        brainTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.decide()
        }
    }

    /// Pick the next idle behavior. Only acts when the pet is genuinely idle so
    /// we never interrupt a drag, poke reaction, nap, or follow.
    private func decide() {
        defer { scheduleBrain() }
        guard !isSleeping, !isBusy, !isFollowing, state.action == .idle else { return }
        // No agent activity (or user interaction) for a while → nap (rest.png).
        if Date().timeIntervalSince(lastActivityAt) > restAfterIdle {
            napFromIdle()
            return
        }
        let r = Double.random(in: 0...1)
        if r < 0.38 {
            startWalk()
        } else if r < 0.54 {
            hop()
        } else if r < 0.70 {
            lookAround()
        } else if r < 0.82 {
            relax()
        }
        // otherwise: just keep idling
    }

    /// Drift off to sleep after a long idle stretch. Poking or any agent
    /// activity wakes it again.
    private func napFromIdle() {
        isSleeping = true
        stopWalk()
        state.action = .sleep
        state.speech = "Zzz..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.isSleeping else { return }
            if self.state.speech == "Zzz..." { self.state.speech = nil }
        }
    }

    /// Mark "something happened" so the idle-nap timer resets.
    private func markActivity() { lastActivityAt = Date() }

    /// A little jump in place.
    func hop() {
        guard state.action == .idle else { return }
        state.hopTrigger += 1
    }

    /// Briefly glance the other way, then back.
    private func lookAround() {
        guard state.action == .idle else { return }
        let original = state.facing
        state.facing = (original == .right) ? .left : .right
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self = self, self.state.action == .idle else { return }
            self.state.facing = original
        }
    }

    /// A short "slacking off" pose for custom appearance packs.
    private func relax() {
        guard state.action == .idle else { return }
        state.action = .relax
        state.speech = ["摸会儿鱼~", "陪你发呆", "偷懒 3 秒"].randomElement()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard let self = self, self.state.action == .relax else { return }
            self.state.speech = nil
            self.state.action = .idle
        }
    }

    // MARK: - Follow the cursor

    func setFollowing(_ on: Bool) {
        isFollowing = on
        stopWalk()
        if on {
            markActivity()
            wakeIfNeeded()
            say("追你啦~ 🏃", duration: 1.8)
            followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.followStep()
            }
        } else {
            followTimer?.invalidate()
            followTimer = nil
            if state.action == .walk || state.action == .relax { state.action = .idle }
            savePosition()
        }
    }

    private func followStep() {
        guard let window = window else { return }
        let cursor = NSEvent.mouseLocation
        let targetX = cursor.x - window.frame.width / 2
        let targetY = cursor.y - window.frame.height + 36   // sit just below the cursor
        var origin = window.frame.origin
        let dx = targetX - origin.x
        let dy = targetY - origin.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist < 4 {
            if state.action != .idle { state.action = .idle }
            return
        }
        let stepLen = min(9, dist)
        origin.x += dx / dist * stepLen
        origin.y += dy / dist * stepLen
        window.setFrameOrigin(origin)
        state.facing = dx < 0 ? .left : .right
        if state.action != .walk { state.action = .walk }
    }

    // MARK: - Position persistence

    func savePosition() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(Double(frame.origin.x), forKey: posKeyX)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: posKeyY)
    }

    // MARK: - Blinking

    private func scheduleBlink() {
        let interval = Double.random(in: 2.5...6.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.blink()
        }
    }

    private func blink() {
        guard !isSleeping else { scheduleBlink(); return }
        state.isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.state.isBlinking = false
            self?.scheduleBlink()
        }
    }

    // MARK: - Walking

    private func startWalk() {
        guard let window = window else { return }
        let screen = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let minX = screen.minX
        let maxX = screen.maxX - window.frame.width
        guard maxX > minX else { return }

        targetX = CGFloat.random(in: minX...maxX)
        let dx = targetX - window.frame.origin.x
        guard abs(dx) > 24 else { return }   // not worth walking such a short hop

        state.facing = dx < 0 ? .left : .right
        state.action = .walk

        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepWalk()
        }
    }

    private func stepWalk() {
        guard let window = window else { return }
        var origin = window.frame.origin
        let dx = targetX - origin.x
        if abs(dx) <= speed {
            origin.x = targetX
            window.setFrameOrigin(origin)
            stopWalk()
            return
        }
        origin.x += dx > 0 ? speed : -speed
        window.setFrameOrigin(origin)
    }

    private func stopWalk() {
        let wasWalking = walkTimer != nil
        walkTimer?.invalidate()
        walkTimer = nil
        if state.action == .walk || state.action == .relax {
            state.action = isSleeping ? .sleep : .idle
        }
        if wasWalking { savePosition() }
    }

    // MARK: - User interaction

    func poke() {
        stopWalk()
        markActivity()
        // While agents are working, the status bubbles are the jump-to-session
        // affordance — a body click must NOT jump or steal focus here. It also
        // fires on the first click of a double-click, and stealing focus would
        // break double-click → action panel. So just give a gentle bounce.
        if isBusy {
            state.pokeTrigger += 1
            return
        }
        if isSleeping {
            // Poking a sleeping pet wakes it up gently.
            toggleSleep()
            return
        }
        state.pokeTrigger += 1
        state.action = .poke
        state.speech = ["❤️", "嗯？", "嘿!", "呀!", "✨"].randomElement()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self else { return }
            self.state.speech = nil
            if self.state.action == .poke {
                self.state.action = .idle
            }
        }
    }

    private func beginDrag() {
        stopWalk()
        markActivity()
        state.action = .drag
        state.speech = nil
        setSpeechActionable(false)
    }

    private func endDrag() {
        state.action = isSleeping ? .sleep : .idle
        savePosition()
        // beginDrag() disabled bubble interactivity; re-enable it if status
        // bubbles are still showing. Otherwise a quiet session's bubble stays
        // permanently un-clickable after one drag (no tick comes to restore it).
        setSpeechActionable(!state.workBubbles.isEmpty)
    }

    // MARK: - Sleep

    func toggleSleep() {
        isSleeping.toggle()
        stopWalk()
        state.action = isSleeping ? .sleep : .idle
        let line = isSleeping ? "Zzz..." : "早!"
        state.speech = line
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self = self else { return }
            if self.state.speech == line {
                self.state.speech = self.isSleeping ? "Zzz..." : nil
            }
        }
    }

    // MARK: - External agent awareness (bridge events)

    /// Active coding sessions, keyed by a stable session id. Monitor events use
    /// the app's session id; legacy CLI hook events use the source name.
    private var activeSessions: [String: WorkSession] = [:]
    private var workStartedAt: Date?
    /// Most recently active source — clicking the busy pet jumps to its app.
    private var lastActiveSource: String?
    private var lastActiveSessionID: String?

    /// Dispatch an event from the AgentMonitor, the `mochi` CLI, or hooks.
    /// `detail` is the current activity line (from the monitor), if any.
    func handleBridgeEvent(type: String, text: String, detail: String? = nil, sessionID: String? = nil, task: String? = nil) {
        markActivity()   // any agent signal keeps the pet awake
        switch type {
        case "busy":
            enterWork(source: text.isEmpty ? "agent" : text, detail: detail, sessionID: sessionID, task: task)
        case "done":
            finishWork(source: text.isEmpty ? "agent" : text, sessionID: sessionID)
        case "say":
            guard !text.isEmpty else { return }
            wakeIfNeeded()
            say(text, duration: 6)
        case "alert":
            guard !text.isEmpty else { return }
            wakeIfNeeded()
            say("⚠️ " + text, duration: 8)
            notify(title: "Mochi", body: text)
        default:
            break
        }
    }

    private func enterWork(source: String, detail: String?, sessionID: String?, task: String? = nil) {
        wakeIfNeeded()
        stopWalk()
        let wasWorking = activeSessions.values.contains { $0.finishedAt == nil }
        if !wasWorking { workStartedAt = Date() }
        let id = sessionID ?? source
        let existingStart = activeSessions[id]?.startedAt ?? Date()
        // Keep a previously-resolved task name if this event didn't carry one.
        let resolvedTask = task ?? activeSessions[id]?.taskName
        // finishedAt: nil — (re)activating clears any pending grace-period removal.
        activeSessions[id] = WorkSession(id: id, source: source, detail: detail,
                                         taskName: resolvedTask, startedAt: existingStart)
        lastActiveSource = source
        lastActiveSessionID = id
        isBusy = true
        state.action = .work
        updateWorkBubbles()
    }

    /// Bring the given agent's desktop app to the front.
    enum AgentApp {
        case claude
        case codex
    }

    func openAgentApp(_ app: AgentApp) {
        let path: String
        let label: String
        let bundleID: String
        let appName: String
        switch app {
        case .codex:
            path = "/Applications/Codex.app"
            label = "Codex"
            bundleID = "com.openai.codex"
            appName = "Codex"
        case .claude:
            path = "/Applications/Claude.app"
            label = "Claude"
            bundleID = "com.anthropic.claudefordesktop"
            appName = "Claude"
        }
        guard FileManager.default.fileExists(atPath: path) else {
            say("找不到 \(label)", duration: 2)
            return
        }

        if activeSessions.isEmpty {
            say("正在打开 \(label)", duration: 1.2)
        }
        if !openWithSystemOpen(appName: appName) {
            openWithWorkspace(path: path, bundleID: bundleID, label: label)
        }
    }

    private func openWithSystemOpen(appName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func openWithWorkspace(path: String, bundleID: String, label: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { running in
            running.bundleIdentifier == bundleID
                || running.bundleURL?.path == path
                || running.localizedName == label
        }) {
            running.activate(options: [.activateAllWindows])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: configuration) { app, _ in
            app?.activate(options: [.activateAllWindows])
        }
    }

    private func openAgentApp(_ source: String) {
        guard let app = agentApp(for: source) else {
            say("找不到 \(source) 的窗口 🤷", duration: 2)
            return
        }
        openAgentApp(app)
    }

    private func openAgentSession(source: String, sessionID: String?) {
        guard let app = agentApp(for: source) else {
            say("找不到 \(source) 的窗口 🤷", duration: 2)
            return
        }

        if let rawSessionID = rawSessionID(sessionID),
           let url = sessionURL(for: app, rawSessionID: rawSessionID) {
            // Deliver the deep link so the app navigates to this session, then
            // pull the app in front. From an accessory (LSUIElement) process,
            // NSRunningApplication.activate() and NSWorkspace.open(url,
            // activates:) are BOTH ignored for an already-running app — only an
            // `open -a`-style application open foregrounds it. So we navigate
            // first, then foreground a beat later (last word on focus).
            NSWorkspace.shared.open(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.bringToFront(app)
            }
            return
        }
        openAgentApp(app)
    }

    private func approveAgentSession(source: String, sessionID: String?) {
        guard let app = agentApp(for: source) else {
            say("找不到 \(source) 的窗口 🤷", duration: 2)
            return
        }
        openAgentSession(source: source, sessionID: sessionID)
        // Synthesizing the confirm keystroke needs Accessibility permission;
        // without it the keystroke is silently dropped. Tell the user and jump
        // straight to the right settings pane instead of failing quietly.
        guard AXIsProcessTrusted() else {
            say("替你点「允许」需要 Mochi 的「辅助功能」权限，去设置里打开它", duration: 5)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
            self?.sendApprovalKeystroke(to: app)
        }
    }

    private func agentApp(for source: String) -> AgentApp? {
        switch source {
        case "codex":  return .codex
        case "claude": return .claude
        default:       return nil
        }
    }

    private func appName(for app: AgentApp) -> String {
        switch app {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }

    /// Foreground an already-running agent app. This is the one foregrounding
    /// path that works from an accessory app; `NSRunningApplication.activate`
    /// is silently ignored for other apps under macOS' cooperative activation.
    private func bringToFront(_ app: AgentApp) {
        if !openWithSystemOpen(appName: appName(for: app)) {
            openWithWorkspace(path: appPath(for: app),
                              bundleID: bundleID(for: app),
                              label: appName(for: app))
        }
    }

    private func appPath(for app: AgentApp) -> String {
        switch app {
        case .codex:  return "/Applications/Codex.app"
        case .claude: return "/Applications/Claude.app"
        }
    }

    private func bundleID(for app: AgentApp) -> String {
        switch app {
        case .codex:  return "com.openai.codex"
        case .claude: return "com.anthropic.claudefordesktop"
        }
    }

    private func sendApprovalKeystroke(to app: AgentApp) {
        let appName = appName(for: app)
        let script = """
        tell application "\(appName)" to activate
        delay 0.15
        tell application "System Events" to key code 36
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                notify(title: "Mochi", body: "需要给 Mochi 辅助功能权限，才能替你点允许")
            }
        } catch {
            notify(title: "Mochi", body: "需要给 Mochi 辅助功能权限，才能替你点允许")
        }
    }

    private func rawSessionID(_ sessionID: String?) -> String? {
        guard let sessionID, !sessionID.isEmpty else { return nil }
        if let colon = sessionID.firstIndex(of: ":") {
            let raw = sessionID[sessionID.index(after: colon)...]
            return raw.isEmpty ? nil : String(raw)
        }
        return sessionID
    }

    private func sessionURL(for app: AgentApp, rawSessionID: String) -> URL? {
        switch app {
        case .codex:
            // Codex Desktop opens a conversation via `codex://threads/<id>`
            // (confirmed against the app's own URL builder: `codex://threads/${e}`
            // where e is the conversationId). The id is the rollout/session UUID
            // from session_meta. If we only have the file-path fallback (meta not
            // yet parsed), bail so the caller just foregrounds the app.
            guard UUID(uuidString: rawSessionID) != nil else { return nil }
            return URL(string: "codex://threads/\(rawSessionID)")
        case .claude:
            // Claude Desktop registers `claude://resume?session=<uuid>`, whose
            // handler imports the CLI/cowork session and navigates straight to
            // it (confirmed against the app's own URL handler + main.log). The
            // handler validates the id as a canonical UUID and silently drops
            // anything else, so only build the link when we actually parsed a
            // session id — otherwise fall back to just opening the app.
            guard UUID(uuidString: rawSessionID) != nil else { return nil }
            var components = URLComponents()
            components.scheme = "claude"
            components.host = "resume"
            components.queryItems = [URLQueryItem(name: "session", value: rawSessionID)]
            return components.url
        }
    }

    private func finishWork(source: String, sessionID: String?) {
        let now = Date()
        let label = (source == "agent") ? "" : "\(source) "
        let elapsed = workStartedAt.map { now.timeIntervalSince($0) } ?? 999
        let substantial = elapsed > 12

        // Which session(s) does this "done" apply to?
        let keys: [String]
        if let sessionID, activeSessions[sessionID] != nil {
            keys = [sessionID]
        } else {
            keys = activeSessions.values
                .filter { $0.source == source || $0.id == source }
                .map { $0.id }
        }

        for key in keys {
            guard var s = activeSessions[key], s.finishedAt == nil else { continue }
            if substantial {
                // Keep it as a dimmed, clickable bubble for the grace period.
                s.finishedAt = now
                activeSessions[key] = s
                scheduleFinishedSweep(key)
            } else {
                // Quick back-and-forth turn — don't leave a lingering bubble.
                activeSessions.removeValue(forKey: key)
            }
        }

        if substantial {
            notify(title: "Mochi 🍡", body: "\(label)跑完啦 ✅")
        }

        // "All done" now means nothing is actively working (finished bubbles may
        // still linger). Drop out of work mode and give a little bounce.
        let stillWorking = activeSessions.values.contains { $0.finishedAt == nil }
        if !stillWorking {
            isBusy = false
            workStartedAt = nil
            state.action = isSleeping ? .sleep : .idle
            state.pokeTrigger += 1
            if activeSessions.isEmpty {
                lastActiveSource = nil
                lastActiveSessionID = nil
            }
        }
        updateWorkBubbles()
        if !substantial, state.workBubbles.isEmpty {
            say("好啦~", duration: 2)
        }
    }

    /// Remove a finished session once its grace period lapses — unless it was
    /// reactivated (finishedAt cleared) or re-finished more recently.
    private func scheduleFinishedSweep(_ key: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + finishedGrace) { [weak self] in
            guard let self = self,
                  let finishedAt = self.activeSessions[key]?.finishedAt,
                  Date().timeIntervalSince(finishedAt) >= self.finishedGrace - 0.5 else { return }
            self.activeSessions.removeValue(forKey: key)
            if self.activeSessions.isEmpty {
                self.lastActiveSource = nil
                self.lastActiveSessionID = nil
            }
            self.updateWorkBubbles()
        }
    }

    /// One visible bubble per active session, capped so Mochi stays compact.
    private func updateWorkBubbles() {
        // One bubble per conversation. When a source has a real session-id entry
        // (e.g. "codex:<uuid>" from the transcript monitor), drop the bare
        // source-level entry (e.g. "codex" from a `mochi busy` hook) so the same
        // conversation isn't shown twice. Distinct real sessions still each get
        // their own bubble.
        let sourcesWithSession = Set(activeSessions.values
            .filter { $0.id != $0.source }
            .map { $0.source })
        let bubbles = activeSessions.values
            .filter { !($0.id == $0.source && sourcesWithSession.contains($0.source)) }
            .sorted { a, b in
                // Actively-working sessions first, then by source, then start time.
                if (a.finishedAt == nil) != (b.finishedAt == nil) { return a.finishedAt == nil }
                if a.source == b.source { return a.startedAt < b.startedAt }
                return a.source < b.source
            }
            .prefix(4)
            .map { task -> AgentBubble in
                let finished = task.finishedAt != nil
                let detail = finished ? "已跑完 · 点我回会话" : (task.detail ?? "干活中…")
                return AgentBubble(source: task.source,
                                   title: task.taskName ?? displayName(for: task.source),
                                   detail: detail,
                                   sessionID: task.id,
                                   requiresApproval: !finished && isApprovalDetail(detail),
                                   finished: finished)
            }
        state.speech = nil
        state.workBubbles = Array(bubbles)
        setSpeechActionable(!state.workBubbles.isEmpty)
    }

    private func isApprovalDetail(_ detail: String) -> Bool {
        detail.contains("等你允许")
    }

    private func wakeIfNeeded() {
        if isSleeping {
            isSleeping = false
            if state.action == .sleep { state.action = .idle }
        }
    }

    /// Post a macOS notification via osascript (no entitlements required).
    private func notify(title: String, body: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "display notification \(body.appleScriptQuoted) with title \(title.appleScriptQuoted)"]
        try? process.run()
    }

    /// Make the pet say something for a few seconds.
    func say(_ text: String, duration: TimeInterval = 3.0) {
        state.speech = text
        state.workBubbles = []
        setSpeechActionable(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.state.speech == text {
                self?.state.speech = self?.isSleeping == true ? "Zzz..." : nil
                self?.setSpeechActionable(false)
            }
        }
    }

    private func setSpeechActionable(_ actionable: Bool) {
        state.speechIsActionable = actionable
        window?.container.isBubbleInteractive = actionable
        window?.container.bubbleTargets = state.workBubbles.map {
            PetContainerView.BubbleTarget(source: $0.source,
                                          sessionID: $0.sessionID,
                                          requiresApproval: $0.requiresApproval)
        }
    }

    private func displayName(for source: String) -> String {
        switch source {
        case "codex": return "Codex"
        case "claude": return "Claude"
        default: return source
        }
    }
}

private extension String {
    /// Wrap + escape this string as an AppleScript string literal.
    var appleScriptQuoted: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

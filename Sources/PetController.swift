//
//  PetController.swift
//  Mochi
//
//  The pet's "brain". Owns the autonomy state machine (idle ↔ walk ↔ sleep),
//  responds to user interaction (poke/drag), and animates window movement when
//  the pet decides to stroll across the screen.
//

import AppKit

final class PetController {
    private weak var window: PetWindow?
    private let state: PetState

    private var brainTimer: Timer?
    private var walkTimer: Timer?
    private var blinkTimer: Timer?
    private var thinkTimer: Timer?
    private var followTimer: Timer?

    private(set) var isFollowing = false
    private let posKeyX = "MochiPosX"
    private let posKeyY = "MochiPosY"

    /// Which AI CLI to talk to. Toggled from the menu, persisted by AppDelegate.
    var engine: AIEngine = .claude

    /// Called when the user double-clicks the pet; AppDelegate opens the chat input.
    var onRequestChat: (() -> Void)?

    /// True while waiting on an AI reply (suppresses autonomy).
    private var isBusy = false

    /// Horizontal target the pet is walking toward (in screen coordinates).
    private var targetX: CGFloat = 0
    /// Walk speed in points per tick (~60 ticks/sec).
    private let speed: CGFloat = 1.4

    private(set) var isSleeping = false

    init(window: PetWindow, state: PetState) {
        self.window = window
        self.state = state
    }

    // MARK: - Lifecycle

    func start() {
        window?.container.onPoke = { [weak self] in self?.poke() }
        window?.container.onChat = { [weak self] in self?.onRequestChat?() }
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
        let r = Double.random(in: 0...1)
        if r < 0.45 {
            startWalk()
        } else if r < 0.62 {
            hop()
        } else if r < 0.78 {
            lookAround()
        }
        // otherwise: just keep idling
    }

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

    // MARK: - Follow the cursor

    func setFollowing(_ on: Bool) {
        isFollowing = on
        stopWalk()
        if on {
            wakeIfNeeded()
            say("追你啦~ 🏃", duration: 1.8)
            followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.followStep()
            }
        } else {
            followTimer?.invalidate()
            followTimer = nil
            if state.action == .walk { state.action = .idle }
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
        if state.action == .walk {
            state.action = isSleeping ? .sleep : .idle
        }
        if wasWalking { savePosition() }
    }

    // MARK: - User interaction

    func poke() {
        stopWalk()
        // While an agent is working, a click jumps to that agent's app/window.
        if isBusy, let source = lastActiveSource {
            openAgentApp(source)
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
        state.action = .drag
        state.speech = nil
    }

    private func endDrag() {
        state.action = isSleeping ? .sleep : .idle
        savePosition()
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

    /// Coding agents currently working, by source label (e.g. "claude", "codex").
    /// Mochi stays in "working" mode until this is empty — handling concurrent
    /// Claude Code + Codex sessions.
    private var activeAgents: Set<String> = []
    /// The latest "what is it doing" line per source (e.g. "运行 npm test").
    private var agentDetail: [String: String] = [:]
    private var workStartedAt: Date?
    /// Most recently active source — clicking the busy pet jumps to its app.
    private var lastActiveSource: String?

    /// Dispatch an event from the AgentMonitor, the `mochi` CLI, or hooks.
    /// `detail` is the current activity line (from the monitor), if any.
    func handleBridgeEvent(type: String, text: String, detail: String? = nil) {
        switch type {
        case "busy":
            enterWork(source: text.isEmpty ? "agent" : text, detail: detail)
        case "done":
            finishWork(source: text.isEmpty ? "agent" : text)
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

    private func enterWork(source: String, detail: String?) {
        wakeIfNeeded()
        stopWalk()
        if activeAgents.isEmpty { workStartedAt = Date() }
        activeAgents.insert(source)
        lastActiveSource = source
        if let detail = detail, !detail.isEmpty { agentDetail[source] = detail }
        isBusy = true
        state.action = .work
        state.speech = composeWorkBubble()
    }

    /// Bring the given agent's desktop app to the front.
    private func openAgentApp(_ source: String) {
        let path: String?
        switch source {
        case "codex":  path = "/Applications/Codex.app"
        case "claude": path = "/Applications/Claude.app"
        default:       path = nil
        }
        guard let path = path, FileManager.default.fileExists(atPath: path) else {
            say("找不到 \(source) 的窗口 🤷", duration: 2)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func finishWork(source: String) {
        activeAgents.remove(source)
        agentDetail[source] = nil
        let label = (source == "agent") ? "" : "\(source) "

        // Only make noise for substantial work — skip quick back-and-forth turns.
        let elapsed = workStartedAt.map { Date().timeIntervalSince($0) } ?? 999
        let substantial = elapsed > 12

        if substantial {
            notify(title: "Mochi 🍡", body: "\(label)跑完啦 ✅")
        }

        if activeAgents.isEmpty {
            isBusy = false
            workStartedAt = nil
            state.action = .idle
            state.pokeTrigger += 1                  // little celebratory bounce
            say(substantial ? "\(label)搞定！✅" : "好啦~", duration: substantial ? 6 : 2)
        } else {
            // Others still working — refresh the bubble.
            state.speech = composeWorkBubble()
        }
    }

    /// One line per active agent: "<dot> <source> · <what it's doing>".
    private func composeWorkBubble() -> String {
        guard !activeAgents.isEmpty else { return "干活中…" }
        let dot = ["claude": "🟣", "codex": "🟢"]
        return activeAgents.sorted().map { src in
            "\(dot[src] ?? "🤖") \(src) · \(agentDetail[src] ?? "干活中…")"
        }.joined(separator: "\n")
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

    // MARK: - AI conversation (P4 + multi-turn memory)

    private var history: [(user: String, mochi: String)] = []
    private var lastChatAt: Date?
    private let maxTurns = 8
    private let conversationTTL: TimeInterval = 600   // forget after 10 min idle

    /// Send the user's message to the AI CLI (with recent context) and show the
    /// reply in a bubble.
    func ask(_ text: String) {
        stopWalk()
        if isSleeping { isSleeping = false }

        // Start a fresh conversation if the last one went stale.
        if let last = lastChatAt, Date().timeIntervalSince(last) > conversationTTL {
            history.removeAll()
        }

        isBusy = true
        startThinking()

        AIService(engine: engine).ask(buildPrompt(for: text)) { [weak self] result in
            guard let self = self else { return }
            self.stopThinking()
            self.isBusy = false
            self.state.action = .idle
            switch result {
            case .success(let reply):
                self.history.append((user: text, mochi: reply))
                if self.history.count > self.maxTurns {
                    self.history.removeFirst(self.history.count - self.maxTurns)
                }
                self.lastChatAt = Date()
                self.say(self.shorten(reply), duration: 10)
            case .failure(let err):
                self.say(self.message(for: err), duration: 6)
            }
        }
    }

    /// Clear the conversation so Mochi starts fresh.
    func clearHistory() {
        history.removeAll()
        lastChatAt = nil
        say("好的，刚才的都忘啦~ 🧹", duration: 2.5)
    }

    private static let persona = "你是用户 macOS 桌面上一只叫 Mochi 的可爱小宠物。"
        + "请用中文、1 到 2 句话、简短俏皮地回应，可以用一点 emoji。"
        + "不要用列表、不要长篇大论、不要解释你是 AI。"

    private func buildPrompt(for text: String) -> String {
        guard !history.isEmpty else {
            return PetController.persona + "\n用户说：\(text)"
        }
        var convo = PetController.persona + "\n以下是你和主人最近的对话：\n"
        for turn in history {
            convo += "用户：\(turn.user)\nMochi：\(turn.mochi)\n"
        }
        convo += "用户现在说：\(text)\n请作为 Mochi 简短回应："
        return convo
    }

    private func startThinking() {
        state.action = .think
        var dots = 0
        state.speech = "思考中"
        thinkTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            dots = (dots + 1) % 4
            self?.state.speech = "思考中" + String(repeating: ".", count: dots)
        }
    }

    private func stopThinking() {
        thinkTimer?.invalidate()
        thinkTimer = nil
    }

    /// Keep bubbles bite-sized even if the model gets chatty.
    private func shorten(_ text: String, limit: Int = 120) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        if oneLine.count <= limit { return text }
        return String(oneLine.prefix(limit)) + "…"
    }

    private func message(for error: AIError) -> String {
        switch error {
        case .notInstalled(let engine):
            return "找不到 \(engine.displayName) 命令行 😣"
        case .timedOut:
            return "想太久了，我先歇会儿 😮‍💨"
        case .launchFailed, .failed:
            return "我有点没听清，再说一次？🥺"
        }
    }

    /// Make the pet say something for a few seconds.
    func say(_ text: String, duration: TimeInterval = 3.0) {
        state.speech = text
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.state.speech == text {
                self?.state.speech = self?.isSleeping == true ? "Zzz..." : nil
            }
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

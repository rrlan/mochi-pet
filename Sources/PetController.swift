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
    /// we never interrupt a drag, poke reaction, or nap.
    private func decide() {
        defer { scheduleBrain() }
        guard !isSleeping, !isBusy, state.action == .idle else { return }
        if Double.random(in: 0...1) < 0.55 {
            startWalk()
        }
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
        walkTimer?.invalidate()
        walkTimer = nil
        if state.action == .walk {
            state.action = isSleeping ? .sleep : .idle
        }
    }

    // MARK: - User interaction

    func poke() {
        stopWalk()
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

    private var workTimer: Timer?

    /// Dispatch a one-line event from the `mochi` CLI / Claude Code / Codex hooks.
    func handleBridgeEvent(type: String, text: String) {
        switch type {
        case "busy":
            beginWork()
        case "done":
            endWork(text.isEmpty ? "搞定啦！✅" : text)
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

    private func beginWork() {
        stopWalk()
        wakeIfNeeded()
        isBusy = true
        state.action = .work
        let bubbles = ["码字中…", "🔨 干活中", "🤔 想想…", "👀 看代码", "⌨️ ……"]
        var i = 0
        state.speech = bubbles[0]
        workTimer?.invalidate()
        workTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            i = (i + 1) % bubbles.count
            self?.state.speech = bubbles[i]
        }
    }

    private func endWork(_ message: String) {
        workTimer?.invalidate()
        workTimer = nil
        isBusy = false
        state.action = .idle
        state.pokeTrigger += 1          // little celebratory bounce
        say(message, duration: 6)
        notify(title: "Mochi 🍡", body: message)
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

    // MARK: - AI conversation (P4)

    /// Send the user's message to the AI CLI and show the reply in a bubble.
    func ask(_ text: String) {
        stopWalk()
        if isSleeping { isSleeping = false }
        isBusy = true
        startThinking()

        AIService(engine: engine).ask(text) { [weak self] result in
            guard let self = self else { return }
            self.stopThinking()
            self.isBusy = false
            self.state.action = .idle
            switch result {
            case .success(let reply):
                self.say(self.shorten(reply), duration: 10)
            case .failure(let err):
                self.say(self.message(for: err), duration: 6)
            }
        }
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

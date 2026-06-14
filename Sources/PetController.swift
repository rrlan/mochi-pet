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
        guard !isSleeping, state.action == .idle else { return }
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

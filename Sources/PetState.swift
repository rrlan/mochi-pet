//
//  PetState.swift
//  Mochi
//
//  The observable model that the SwiftUI view renders from. The controller
//  mutates these properties; the view reacts. Keeping all visual state here
//  means the rendering layer stays a pure function of state.
//

import SwiftUI
import AppKit

/// What the pet is currently doing. Drives both autonomy and rendering.
enum PetAction: Equatable {
    case idle      // standing around, breathing
    case walk      // strolling toward a target x
    case relax     // taking a short lazy break
    case sleep     // napping (eyes closed, Zzz)
    case drag      // being dragged by the user
    case poke      // reacting to a poke/click
    case think     // waiting on an AI reply
    case work      // an external coding agent is busy
}

/// Which way the pet faces. Used to mirror the sprite horizontally.
enum Facing {
    case left
    case right
}

/// Custom image slots that can be mapped from the pet's current behavior.
enum AppearanceRole: String, CaseIterable {
    case companion
    case work
    case rest
    case slack
    case drag
}

/// A clickable status bubble for one coding agent's session. Stays clickable
/// for a grace period after the session finishes (`finished == true`) so you can
/// still jump back to it.
struct AgentBubble: Identifiable, Equatable {
    let source: String
    let title: String
    let detail: String
    let sessionID: String
    let requiresApproval: Bool
    let finished: Bool

    var id: String { sessionID }
}

/// Single source of truth for everything the view needs to draw.
final class PetState: ObservableObject {
    @Published var action: PetAction = .idle
    @Published var facing: Facing = .right

    /// Briefly true to render a blink.
    @Published var isBlinking: Bool = false

    /// Optional speech-bubble text shown above the pet.
    @Published var speech: String? = nil

    /// True when the visible speech bubble should behave like a jump-to-agent
    /// button instead of passive status text.
    @Published var speechIsActionable: Bool = false

    /// Separate clickable bubbles for active Codex / Claude work.
    @Published var workBubbles: [AgentBubble] = []

    /// Incremented to trigger a one-shot "squash" reaction animation.
    @Published var pokeTrigger: Int = 0

    /// Incremented to trigger a one-shot hop (jump) animation.
    @Published var hopTrigger: Int = 0

    /// Optional user-chosen appearance images. When set, these replace the
    /// built-in Mochi body while keeping the same window, speech, and gestures.
    @Published var customAppearances: [AppearanceRole: NSImage] = [:]

    /// Optional user-chosen walking frames, rendered as a looping animation
    /// whenever the pet is in the walk state.
    @Published var customWalkFrames: [NSImage] = []
}

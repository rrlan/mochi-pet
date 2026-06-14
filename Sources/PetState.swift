//
//  PetState.swift
//  Mochi
//
//  The observable model that the SwiftUI view renders from. The controller
//  mutates these properties; the view reacts. Keeping all visual state here
//  means the rendering layer stays a pure function of state.
//

import SwiftUI

/// What the pet is currently doing. Drives both autonomy and rendering.
enum PetAction: Equatable {
    case idle      // standing around, breathing
    case walk      // strolling toward a target x
    case sleep     // napping (eyes closed, Zzz)
    case drag      // being dragged by the user
    case poke      // reacting to a poke/click
    case think     // waiting on an AI reply
}

/// Which way the pet faces. Used to mirror the sprite horizontally.
enum Facing {
    case left
    case right
}

/// Single source of truth for everything the view needs to draw.
final class PetState: ObservableObject {
    @Published var action: PetAction = .idle
    @Published var facing: Facing = .right

    /// Briefly true to render a blink.
    @Published var isBlinking: Bool = false

    /// Optional speech-bubble text shown above the pet.
    @Published var speech: String? = nil

    /// Incremented to trigger a one-shot "squash" reaction animation.
    @Published var pokeTrigger: Int = 0
}

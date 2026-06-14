//
//  PetView.swift
//  Mochi
//
//  The pet is drawn entirely in code (no image assets) so it stays tiny and
//  easy to restyle. "Mochi" is a soft mint blob with squash-and-stretch
//  breathing, blinking eyes, and a few expressions.
//

import SwiftUI

// MARK: - Palette

private enum Palette {
    static let bodyTop = Color(red: 0.62, green: 0.90, blue: 0.76)
    static let bodyBottom = Color(red: 0.36, green: 0.76, blue: 0.63)
    static let outline = Color(red: 0.20, green: 0.56, blue: 0.47)
    static let ink = Color(red: 0.13, green: 0.22, blue: 0.20)
    static let cheek = Color(red: 1.0, green: 0.55, blue: 0.55)
}

// MARK: - Main view

struct PetView: View {
    @ObservedObject var state: PetState

    @State private var breathe = false
    @State private var walkBob = false
    /// 0 = rest, 1 = fully squashed; drives the poke reaction.
    @State private var squash: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            speechBubbleArea
            Spacer(minLength: 0)
            petBody
        }
        .frame(width: PetWindow.canvasSize.width,
               height: PetWindow.canvasSize.height)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onChange(of: state.pokeTrigger) { _, _ in
            squash = 1
            withAnimation(.spring(response: 0.38, dampingFraction: 0.42)) {
                squash = 0
            }
        }
        .onChange(of: state.action) { _, newValue in
            if newValue == .walk {
                walkBob = false
                withAnimation(.easeInOut(duration: 0.30).repeatForever(autoreverses: true)) {
                    walkBob = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { walkBob = false }
            }
        }
    }

    // MARK: Speech bubble

    private var speechBubbleArea: some View {
        ZStack {
            if let text = state.speech {
                SpeechBubble(text: text)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: state.speech)
    }

    // MARK: Body

    private var petBody: some View {
        ZStack(alignment: .bottom) {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.16))
                .frame(width: 78, height: 15)
                .offset(y: 4)
                .blur(radius: 3)
                .scaleEffect(x: breathe ? 1.05 : 0.95, anchor: .center)

            ZStack {
                BlobShape()
                    .fill(LinearGradient(colors: [Palette.bodyTop, Palette.bodyBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(BlobShape().stroke(Palette.outline.opacity(0.6), lineWidth: 2))
                    .frame(width: 106, height: 92)
                    .overlay(highlight, alignment: .topLeading)

                face
            }
            .scaleEffect(x: state.facing == .left ? -1 : 1, y: 1)   // mirror to face
            .scaleEffect(
                x: 1 + (breathe ? 0.03 : -0.03) + squash * 0.20,
                y: 1 - (breathe ? 0.03 : -0.03) - squash * 0.22,
                anchor: .bottom
            )
            .offset(y: walkBob ? -4 : 0)
        }
        .frame(width: 112, height: 100)
        .padding(.bottom, 8)
    }

    /// Glossy highlight on the upper-left of the blob.
    private var highlight: some View {
        Ellipse()
            .fill(Color.white.opacity(0.35))
            .frame(width: 26, height: 16)
            .rotationEffect(.degrees(-20))
            .offset(x: 18, y: 16)
            .blur(radius: 1)
    }

    // MARK: Face

    private var face: some View {
        VStack(spacing: 5) {
            HStack(spacing: 20) {
                eye
                eye
            }
            mouth
        }
        .offset(y: 2)
    }

    private var eyesClosed: Bool {
        state.isBlinking || state.action == .sleep
    }

    private var eye: some View {
        ZStack {
            Capsule()
                .fill(Palette.ink)
                .frame(width: 11, height: eyesClosed ? 2 : 14)
            if !eyesClosed {
                Circle()
                    .fill(.white)
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: 2, y: -3.5)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch state.action {
        case .sleep:
            Text("z").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        case .poke:
            Circle()
                .stroke(Palette.ink, lineWidth: 2)
                .frame(width: 9, height: 9)
        case .think:
            Capsule()
                .fill(Palette.ink)
                .frame(width: 8, height: 2)   // neutral, focused little mouth
        default:
            SmileArc()
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 8)
        }
    }
}

// MARK: - Shapes

/// A soft "mochi" blob: wide rounded body with a slightly squashed bottom.
struct BlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let by = rect.maxY
        p.move(to: CGPoint(x: rect.minX, y: by))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: by),
                       control: CGPoint(x: rect.midX, y: by + h * 0.07))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.16),
                   control2: CGPoint(x: rect.midX + w * 0.36, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.minX, y: by),
                   control1: CGPoint(x: rect.midX - w * 0.36, y: rect.minY),
                   control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.16))
        p.closeSubpath()
        return p
    }
}

/// A gentle upward smile arc.
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY + 2))
        return p
    }
}

// MARK: - Speech bubble

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.ink)
            .lineLimit(6)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
            )
            .frame(maxWidth: 252)
            .fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import SwiftUI

// ─────────────────────────────────────────────
// MARK: - SplashOverlay
//
// Fullscreen cinematic launch reveal shown once, before the onboarding tour,
// on first launch. Borderless screen-saver-level panel that fades itself in,
// plays a short logo/title reveal, then fades out and hands off via onComplete.
// ─────────────────────────────────────────────

@MainActor
final class SplashOverlay: NSPanel {
    /// Retains the live overlay until it finishes; a plain panel would deallocate.
    private static var live: SplashOverlay?

    private var onComplete: (() -> Void)?

    /// Present the splash on the main screen, then call `onComplete` once it fades out.
    static func present(onComplete: @escaping () -> Void) {
        guard let screen = NSScreen.main else { onComplete(); return }
        let overlay = SplashOverlay(screen: screen, onComplete: onComplete)
        live = overlay
        overlay.orderFrontRegardless()
        overlay.fadeIn()
    }

    private init(screen: NSScreen, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        alphaValue = 0

        let view = SplashView { [weak self] in self?.fadeOutAndComplete() }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = contentRect(forFrameRect: frame)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    private func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    private func fadeOutAndComplete() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.onComplete?()
                self?.close()
                SplashOverlay.live = nil
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - SplashView
// ─────────────────────────────────────────────

private struct SplashView: View {
    let onComplete: () -> Void

    @State private var backgroundOpacity: CGFloat = 0
    @State private var ambientOpacity: CGFloat = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: CGFloat = 0
    @State private var titleOpacity: CGFloat = 0
    @State private var taglineOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.75)
                DriftingGradient()
                    .opacity(0.22)
            }
            .opacity(backgroundOpacity)

            ZStack {
                ambientGlow
                    .opacity(ambientOpacity)

                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)

                    Text("Glide")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .opacity(titleOpacity)

                    Text("Your trackpad, but with superpowers.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(taglineOpacity)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { runReveal() }
    }

    private var ambientGlow: some View {
        ZStack {
            glowCircle(diameter: 560, blur: 60, inner: 0.08, mid: 0.02, start: 40, end: 280)
            glowCircle(diameter: 320, blur: 40, inner: 0.12, mid: 0.04, start: 20, end: 160)
            glowCircle(diameter: 200, blur: 25, inner: 0.15, mid: 0.05, start: 10, end: 100)
        }
    }

    private func glowCircle(diameter: CGFloat, blur: CGFloat,
                            inner: Double, mid: Double,
                            start: CGFloat, end: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [.white.opacity(inner), .white.opacity(mid), .clear],
                center: .center, startRadius: start, endRadius: end))
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
    }

    private func runReveal() {
        withAnimation(.easeOut(duration: 0.5)) { backgroundOpacity = 1 }
        after(0.3) { withAnimation(.easeOut(duration: 0.8)) { ambientOpacity = 1 } }
        after(0.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                logoScale = 1; logoOpacity = 1
            }
        }
        after(1.0) { withAnimation(.easeOut(duration: 0.4)) { titleOpacity = 1 } }
        after(1.4) { withAnimation(.easeOut(duration: 0.4)) { taglineOpacity = 1 } }
        after(3.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                ambientOpacity = 0; logoOpacity = 0
                titleOpacity = 0; taglineOpacity = 0; backgroundOpacity = 0
            }
            after(0.35) { onComplete() }
        }
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

// ─────────────────────────────────────────────
// MARK: - DriftingGradient
//
// Lightweight self-contained animated color wash: a few tinted blobs that
// drift on autoreversing loops. Sits at low opacity behind the black scrim.
// ─────────────────────────────────────────────

private struct DriftingGradient: View {
    private struct Blob {
        let color: Color
        let size: CGFloat
        let from: UnitPoint
        let to: UnitPoint
        let duration: Double
    }

    private let blobs: [Blob] = [
        Blob(color: .blue,   size: 620, from: .topLeading,     to: .bottomTrailing, duration: 9),
        Blob(color: .purple, size: 540, from: .bottomLeading,  to: .topTrailing,    duration: 11),
        Blob(color: .teal,   size: 480, from: .trailing,       to: .leading,        duration: 13),
    ]

    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(blobs.indices, id: \.self) { i in
                    let b = blobs[i]
                    Circle()
                        .fill(RadialGradient(
                            colors: [b.color.opacity(0.9), b.color.opacity(0.0)],
                            center: .center, startRadius: 0, endRadius: b.size / 2))
                        .frame(width: b.size, height: b.size)
                        .position(pos(animate ? b.to : b.from, in: geo.size))
                        .animation(.easeInOut(duration: b.duration).repeatForever(autoreverses: true), value: animate)
                }
            }
            .blur(radius: 60)
        }
        .onAppear { animate = true }
    }

    private func pos(_ p: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }
}

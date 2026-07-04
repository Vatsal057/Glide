import SwiftUI
import Cocoa
import ApplicationServices

// ─────────────────────────────────────────────
// MARK: - OnboardingController
//
// Hosts the welcome tour in a plain NSWindow so it can be shown from the
// AppKit app delegate at first launch (the app is LSUIElement — there is no
// SwiftUI scene visible at startup to hang an openWindow call on).
// ─────────────────────────────────────────────

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private static let completedKey = "GlideHasCompletedOnboarding"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.close()
        })
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.setContentSize(NSSize(width: 540, height: 600))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w

        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() {
        window?.close()   // triggers windowWillClose for the shared teardown
    }

    func windowWillClose(_ notification: Notification) {
        // Closing counts as done either way — don't nag on every launch.
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
        NSApp.setActivationPolicy(.accessory)
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - OnboardingView
// ─────────────────────────────────────────────

private struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0:  welcomePage
                case 1:  permissionPage
                case 2:  gesturesPage
                default: finishPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            footer
        }
        .frame(width: 540, height: 600)
        .background(.regularMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: page)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 110, height: 110)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            Text("Welcome to Glide")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Your trackpad, but with superpowers.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "hand.draw.fill", color: .blue,
                           title: "Custom gestures",
                           detail: "Swipe, click, or force-click with 3, 4, or 5 fingers.")
                featureRow(icon: "bolt.fill", color: .orange,
                           title: "Instant actions",
                           detail: "Snap windows, switch apps, take screenshots, and more.")
                featureRow(icon: "slider.horizontal.3", color: .purple,
                           title: "Fully tunable",
                           detail: "Per-app rules, modifier keys, speed, and sensitivity.")
            }
            .padding(.top, 12)
            .padding(.horizontal, 60)
            Spacer()
        }
    }

    private var permissionPage: some View {
        PermissionStepView()
    }

    private var gesturesPage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            Text("Learn the moves")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("These starter gestures are set up for you.\nEvery one of them can be changed in Preferences.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            TrackpadDemoView()
                .padding(.top, 4)
            Spacer(minLength: 16)
        }
        .padding(.horizontal, 40)
    }

    private var finishPage: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .frame(width: 220, height: 34)
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75")
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.blue)
                        .padding(5)
                        .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    Image(systemName: "magnifyingglass")
                }
                .font(.system(size: 13))
            }

            Text("Glide lives in your menu bar")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Click the hand icon any time to open Preferences,\npause gestures, or quit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                tipRow("Try it now: swipe up with 3 fingers for Mission Control.")
                tipRow("Add your own gestures in Preferences → Gestures.")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 50)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(page < pageCount - 1 ? 1 : 0)

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            Button(page < pageCount - 1 ? "Continue" : "Get Started") {
                if page < pageCount - 1 { page += 1 } else { onFinish() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }

    // MARK: Bits

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(.yellow)
                .font(.caption)
                .padding(.top, 3)
            Text(text).font(.callout)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Permission step
// ─────────────────────────────────────────────

private struct PermissionStepView: View {
    @State private var granted = AXIsProcessTrusted()
    private let poll = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: granted ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(granted ? .green : .orange)

            Text(granted ? "You're all set" : "One permission needed")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text(granted
                 ? "Glide can now see your trackpad gestures.\nHit Continue to learn the moves."
                 : "Glide reads trackpad touches and controls windows through macOS Accessibility. Nothing leaves your Mac — there's no network access, no analytics.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            if !granted {
                VStack(alignment: .leading, spacing: 12) {
                    stepRow(1, "Click the button below.")
                    stepRow(2, "Find **Glide** in the list and switch it on.")
                    stepRow(3, "Come back here — this page updates by itself.")
                }
                .padding(.vertical, 4)

                Button {
                    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Accessibility Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .onReceive(poll) { _ in
            let now = AXIsProcessTrusted()
            if now != granted {
                withAnimation { granted = now }
                if now { PreferencesStore.shared.refreshAccessibilityStatus() }
            }
        }
    }

    private func stepRow(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Trackpad demo (animated)
// ─────────────────────────────────────────────

private struct GestureDemo {
    let caption: String
    let fingers: Int
    /// Finger travel over one loop, in trackpad-relative units.
    let travel: CGSize
    /// Click-style gestures pulse instead of sliding.
    let isClick: Bool
}

struct TrackpadDemoView: View {
    private let demos: [GestureDemo] = [
        GestureDemo(caption: "3-finger swipe up — Mission Control", fingers: 3,
                    travel: CGSize(width: 0, height: -0.42), isClick: false),
        GestureDemo(caption: "3-finger click — quit app under cursor", fingers: 3,
                    travel: .zero, isClick: true),
        GestureDemo(caption: "3-finger swipe left or right — app switcher", fingers: 3,
                    travel: CGSize(width: 0.42, height: 0), isClick: false),
        GestureDemo(caption: "4-finger swipe left — snap window left", fingers: 4,
                    travel: CGSize(width: -0.42, height: 0), isClick: false),
        GestureDemo(caption: "5-finger swipe up — enter fullscreen", fingers: 5,
                    travel: CGSize(width: 0, height: -0.42), isClick: false),
    ]

    @State private var demoIndex = 0
    @State private var progress: CGFloat = 0   // 0 → 1 finger travel
    @State private var pressed = false
    private let tick = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()

    var body: some View {
        let demo = demos[demoIndex]

        VStack(spacing: 18) {
            ZStack {
                // Trackpad
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.tertiary, lineWidth: 1)
                    )

                // Fingers
                fingerDots(for: demo)
            }
            .frame(width: 320, height: 230)

            Text(demo.caption)
                .font(.headline)
                .contentTransition(.opacity)
                .frame(height: 22)

            HStack(spacing: 6) {
                ForEach(0..<demos.count, id: \.self) { i in
                    Capsule()
                        .fill(i == demoIndex ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: i == demoIndex ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: demoIndex)
        }
        .onAppear { runCurrentDemo() }
        .onReceive(tick) { _ in
            demoIndex = (demoIndex + 1) % demos.count
            runCurrentDemo()
        }
    }

    private func fingerDots(for demo: GestureDemo) -> some View {
        let spacing: CGFloat = 34
        let baseOffset = CGFloat(demo.fingers - 1) / 2
        return ZStack {
            ForEach(0..<demo.fingers, id: \.self) { i in
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 26, height: 26)
                    .scaleEffect(pressed ? 0.78 : 1.0)
                    .shadow(color: .accentColor.opacity(0.45), radius: pressed ? 2 : 7)
                    .offset(x: (CGFloat(i) - baseOffset) * spacing)
            }
        }
        .offset(x: demo.travel.width * 160 * progress + (demo.travel.width == 0 ? 0 : -demo.travel.width * 80),
                y: demo.travel.height * 160 * progress + (demo.travel.height == 0 ? 0 : -demo.travel.height * 80))
    }

    private func runCurrentDemo() {
        let demo = demos[demoIndex]
        progress = 0
        pressed = false
        if demo.isClick {
            withAnimation(.easeInOut(duration: 0.28).delay(0.5)) { pressed = true }
            withAnimation(.easeInOut(duration: 0.28).delay(1.1)) { pressed = false }
        } else {
            withAnimation(.easeInOut(duration: 1.5).delay(0.35)) { progress = 1 }
        }
    }
}

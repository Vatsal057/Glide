import SwiftUI

// ─────────────────────────────────────────────
// MARK: - Material pill
// ─────────────────────────────────────────────

private struct MaterialPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps the view in a frosted capsule — good for version tags and status chips.
    func materialPill() -> some View { modifier(MaterialPill()) }
}

// ─────────────────────────────────────────────
// MARK: - Squiggle divider
//
// A small hand-drawn-looking sine divider. Drawn as a Path so it needs no
// bundled asset.
// ─────────────────────────────────────────────

struct SquiggleDivider: View {
    var color: Color = .primary
    var width: CGFloat = 51
    var height: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let midY = size.height / 2
            let amplitude = size.height / 2
            let waves: CGFloat = 3
            path.move(to: CGPoint(x: 0, y: midY))
            let steps = 60
            for i in 1 ... steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                let phase = CGFloat(i) / CGFloat(steps) * waves * 2 * .pi
                path.addLine(to: CGPoint(x: x, y: midY - sin(phase) * amplitude))
            }
            context.stroke(path, with: .color(color.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// ─────────────────────────────────────────────
// MARK: - Shimmer
//
// Sweeping highlight for "look here" chips (e.g. an available update). A moving
// linear gradient masked to the content — no dependency on the fluid gradient.
// ─────────────────────────────────────────────

private struct Shimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: phase * w * 1.6)
                    .blendMode(.plusLighter)
                }
                .mask(content)
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
    }
}

extension View {
    /// Sweeps a soft highlight across the view while `active` is true.
    func shimmer(active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

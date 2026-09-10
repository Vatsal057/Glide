import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EdgeControlsTab
//
// Interactive preferences tab for Trackpad Edge Controls.
// Features an interactive trackpad diagram and per-edge action pickers.
// ─────────────────────────────────────────────────────────────────────────────

struct EdgeControlsTab: View {
    @EnvironmentObject var store: PreferencesStore
    @ObservedObject private var controller = EdgeControlsController.shared
    @State private var selectedEdge: TrackpadPhysicalEdge = .right

    private var settings: EdgeControlsSettings { store.edgeControls }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introCard

                if settings.enabled {
                    diagramCard
                    edgeAssignmentsCard
                    tuningCard

                    HStack {
                        Spacer()
                        Button("Reset Edge Controls to Defaults") {
                            withAnimation { store.resetEdgeControls() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: settings.enabled)
        }
    }

    // MARK: - Intro Card

    private var introCard: some View {
        TuningSection(title: "Edge Controls", icon: "rectangle.inset.filled") {
            Toggle("Enable trackpad edge sliding controls", isOn: Binding(
                get: { settings.enabled },
                set: { val in store.updateEdgeControls { $0.enabled = val } }
            ))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            explainer("Slide a single finger along any outer edge of your trackpad to smoothly adjust volume, display brightness, or scrub through open apps.\n\nVolume and brightness use the native macOS bezel overlays with zero idle CPU overhead.")
        }
    }

    // MARK: - Interactive Trackpad Diagram Card

    private var diagramCard: some View {
        TuningSection(title: "Trackpad Surface", icon: "aspectratio") {
            VStack(spacing: 12) {
                Text("Click an edge or slide on your trackpad to highlight it:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                InteractiveEdgeDiagram(
                    settings: settings,
                    selectedEdge: $selectedEdge,
                    activeEdge: controller.activeEdge
                )
                .frame(height: 180)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Edge Assignments Card

    private var edgeAssignmentsCard: some View {
        TuningSection(title: "Edge Actions", icon: "slider.horizontal.below.rectangle") {
            VStack(spacing: 0) {
                edgeRow(for: .top, action: binding(\.topEdge))
                Divider().padding(.leading, 36)
                edgeRow(for: .bottom, action: binding(\.bottomEdge))
                Divider().padding(.leading, 36)
                edgeRow(for: .left, action: binding(\.leftEdge))
                Divider().padding(.leading, 36)
                edgeRow(for: .right, action: binding(\.rightEdge))
            }
        }
    }

    private func edgeRow(for edge: TrackpadPhysicalEdge, action: Binding<EdgeAction>) -> some View {
        let isSelected = selectedEdge == edge
        let isActive = controller.activeEdge == edge

        return HStack(spacing: 12) {
            Image(systemName: action.wrappedValue.iconName)
                .foregroundColor(action.wrappedValue == .none ? .secondary : .accentColor)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(edge.displayName)
                        .font(.body)
                        .fontWeight(isSelected ? .semibold : .regular)

                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Active")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                Text(edge.isHorizontal ? "Slide horizontally (left ⇄ right)" : "Slide vertically (up ⇄ down)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Picker("", selection: action) {
                ForEach(EdgeAction.allCases) { item in
                    Label(item.displayName, systemImage: item.iconName)
                        .tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEdge = edge
        }
    }

    // MARK: - Tuning Card

    private var tuningCard: some View {
        TuningSection(title: "Sensitivity & Margin", icon: "ruler") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Edge Margin Depth")
                            .font(.body)
                        Spacer()
                        Text("\(String(format: "%.1f", settings.marginMm)) mm")
                            .font(.body.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { settings.marginMm },
                            set: { val in store.updateEdgeControls { $0.marginMm = val } }
                        ),
                        in: EdgeControlsSettings.marginMmRange,
                        step: 0.5
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                explainer("How far inward from each physical edge a swipe can begin. Moving more than 6 mm beyond this margin automatically yields back to standard cursor motion.")
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<EdgeControlsSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { val in store.updateEdgeControls { $0[keyPath: keyPath] = val } }
        )
    }

    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Interactive Trackpad Diagram
// ─────────────────────────────────────────────────────────────────────────────

private struct InteractiveEdgeDiagram: View {
    let settings: EdgeControlsSettings
    @Binding var selectedEdge: TrackpadPhysicalEdge
    let activeEdge: TrackpadPhysicalEdge?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Pad surface background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                    )

                // Top Edge Strip
                edgeStrip(edge: .top, action: settings.topEdge, rect: CGRect(x: 24, y: 4, width: w - 48, height: 26))

                // Bottom Edge Strip
                edgeStrip(edge: .bottom, action: settings.bottomEdge, rect: CGRect(x: 24, y: h - 30, width: w - 48, height: 26))

                // Left Edge Strip
                edgeStrip(edge: .left, action: settings.leftEdge, rect: CGRect(x: 4, y: 4, width: 26, height: h - 8))

                // Right Edge Strip
                edgeStrip(edge: .right, action: settings.rightEdge, rect: CGRect(x: w - 30, y: 4, width: 26, height: h - 8))

                // Trackpad center label
                VStack(spacing: 4) {
                    Image(systemName: "hand.point.up.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Standard Cursor Area")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
    }

    private func edgeStrip(edge: TrackpadPhysicalEdge, action: EdgeAction, rect: CGRect) -> some View {
        let isSelected = selectedEdge == edge
        let isActive = activeEdge == edge
        let isConfigured = action != .none

        let fillColor: Color = {
            if isActive { return Color.green.opacity(0.35) }
            if isSelected { return Color.accentColor.opacity(0.25) }
            if isConfigured { return Color.accentColor.opacity(0.12) }
            return Color.secondary.opacity(0.08)
        }()

        let strokeColor: Color = {
            if isActive { return Color.green }
            if isSelected { return Color.accentColor }
            if isConfigured { return Color.accentColor.opacity(0.4) }
            return Color.clear
        }()

        return RoundedRectangle(cornerRadius: 8)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: (isActive || isSelected) ? 2 : 1)
            )
            .overlay(
                HStack(spacing: 4) {
                    if isConfigured {
                        Image(systemName: action.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isActive ? .green : (isSelected ? .accentColor : .primary.opacity(0.7)))
                    }
                }
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedEdge = edge
                }
            }
    }
}

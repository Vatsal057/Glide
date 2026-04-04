import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

// ─────────────────────────────────────────────
// MARK: - Store
// ─────────────────────────────────────────────

@MainActor
final class PreferencesStore: ObservableObject {

    struct RuleDiagnostics {
        var configuredFingerCounts: Int = 0
        var appSpecificRules: Int = 0
        var openAppRulesMissingTarget: Int = 0
    }

    static let shared = PreferencesStore()

    @Published private(set) var rules: [GestureRule] = []
    @Published private(set) var tuning: GestureTuning = .init()
    @Published private(set) var windowTargetingMode: WindowTargetingMode = .focusedThenCursor
    @Published private(set) var hapticFeedbackEnabled = true
    @Published private(set) var debugLoggingEnabled = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var diagnostics = RuleDiagnostics()
    @Published private(set) var launchAtLoginEnabled = false

    // Engine state (push-based — no polling timer)
    @Published private(set) var enginePhase: String = "Idle"
    @Published private(set) var fingerCount: Int = 0
    @Published private(set) var reciprocalActive: Bool = false
    /// Live centroid coordinates from MT callback (0–1 normalised, cy=0 bottom).
    @Published private(set) var centroidX: Float = 0.5
    @Published private(set) var centroidY: Float = 0.5

    private init() { reload() }

    func reload() {
        let s = Settings.shared
        rules = s.rules.map(sanitizedRule)
        tuning = s.tuning
        windowTargetingMode = s.windowTargetingMode
        hapticFeedbackEnabled = s.hapticFeedbackEnabled
        debugLoggingEnabled = s.debugLoggingEnabled
        accessibilityGranted = AXIsProcessTrusted()
        diagnostics = buildDiagnostics(for: rules)
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Subscribe to engine state changes via push callback.
    func startPollingEngineState() {
        let engine = GestureEngine.shared
        enginePhase = engine.currentPhaseName
        fingerCount = engine.currentFingerCount
        reciprocalActive = engine.isReciprocalActive
        centroidX = engine.currentCentroidX
        centroidY = engine.currentCentroidY
        engine.onStateChange = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let engine = GestureEngine.shared
                self.enginePhase = engine.currentPhaseName
                self.fingerCount = engine.currentFingerCount
                self.reciprocalActive = engine.isReciprocalActive
                self.centroidX = engine.currentCentroidX
                self.centroidY = engine.currentCentroidY
            }
        }
    }

    func stopPollingEngineState() {
        GestureEngine.shared.onStateChange = nil
    }

    func addRule() {
        rules.append(nextAvailableRule() ?? GestureRule(fingers: 3, direction: .swipeUp, speed: .normal, action: .doNothing))
        persistRules()
    }

    func resetRules() {
        rules = Settings.defaultRules.map(sanitizedRule)
        persistRules()
    }

    func updateRule(_ r: GestureRule) {
        guard let i = rules.firstIndex(where: { $0.id == r.id }) else { return }
        rules[i] = sanitizedRule(r)
        persistRules()
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persistRules()
    }

    func updateWindowTargetingMode(_ m: WindowTargetingMode) {
        windowTargetingMode = m
        Settings.shared.windowTargetingMode = m
    }

    func updateHapticFeedback(_ v: Bool) {
        hapticFeedbackEnabled = v
        Settings.shared.hapticFeedbackEnabled = v
    }

    func updateDebugLogging(_ v: Bool) {
        debugLoggingEnabled = v
        Settings.shared.debugLoggingEnabled = v
    }

    func updateTuning(_ mutate: (inout GestureTuning) -> Void) {
        var copy = tuning
        mutate(&copy)
        tuning = normalizedTuning(copy)
        Settings.shared.tuning = tuning
    }

    func resetTuning() {
        tuning = GestureTuning()
        Settings.shared.resetTuning()
    }

    func toggleLaunchAtLogin() {
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.setLaunchAtLogin(!launchAtLoginEnabled)
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func chooseApp(for ruleID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.appPath = url.path
        updateRule(rule)
    }

    func setAppFilter(_ bundleID: String?, for ruleID: UUID) {
        guard var rule = rules.first(where: { $0.id == ruleID }) else { return }
        rule.appFilter = bundleID
        updateRule(rule)
    }

    func binding(for ruleID: UUID) -> Binding<GestureRule> {
        Binding(
            get: { self.rules.first(where: { $0.id == ruleID }) ?? GestureRule(fingers: 3, direction: .click, action: .doNothing) },
            set: { self.updateRule($0) }
        )
    }

    func runningApps() -> [RunningAppOption] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bid = app.bundleIdentifier else { return nil }
                return RunningAppOption(bundleID: bid, name: app.localizedName ?? bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func filterLabel(for bundleID: String?) -> String {
        guard let bundleID else { return "Any App" }
        return runningApps().first(where: { $0.bundleID == bundleID })?.name
            ?? bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }

    func appLabel(for path: String?) -> String {
        guard let path else { return "Choose App…" }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Group rules by finger count for sectioned display.
    func rulesGroupedByFingers() -> [(fingers: Int, rules: [GestureRule])] {
        let grouped = Dictionary(grouping: rules) { $0.fingers }
        return grouped.keys.sorted().map { (fingers: $0, rules: grouped[$0]!) }
    }

    private func persistRules() {
        rules = rules.map(sanitizedRule)
        Settings.shared.rules = rules
        rules = Settings.shared.rules
        diagnostics = buildDiagnostics(for: rules)
    }

    private func nextAvailableRule() -> GestureRule? {
        for fingers in 2...5 {
            for direction in GestureDirection.allCases {
                let speeds: [GestureSpeed] = direction == .click ? [.normal] : GestureSpeed.allCases
                for speed in speeds {
                    let candidate = GestureRule(fingers: fingers, direction: direction, speed: speed, action: .doNothing)
                    guard !containsRule(matching: candidate) else { continue }
                    return candidate
                }
            }
        }
        return nil
    }

    private func containsRule(matching c: GestureRule) -> Bool {
        rules.contains { $0.fingers == c.fingers && $0.direction == c.direction && $0.speed == c.speed && $0.appFilter == c.appFilter }
    }

    private func sanitizedRule(_ r: GestureRule) -> GestureRule {
        var copy = r
        if copy.direction == .click { copy.speed = .normal }
        return copy
    }

    private func normalizedTuning(_ t: GestureTuning) -> GestureTuning {
        var n = t
        n.initialThreshold = max(0.005, n.initialThreshold)
        n.appSwitcherStepThreshold = max(0.001, n.appSwitcherStepThreshold)
        n.appSwitcherDebounce = max(0.0, n.appSwitcherDebounce)
        n.slowVelocityThreshold = max(0.001, min(n.slowVelocityThreshold, 0.020))
        n.fastVelocityThreshold = max(n.slowVelocityThreshold + 0.001, max(0.003, min(n.fastVelocityThreshold, 0.030)))
        n.speedSampleCount = max(2, min(n.speedSampleCount, 8))
        n.candidateFrames = max(1, min(n.candidateFrames, 8))
        n.pinchSpreadThreshold = max(0.002, n.pinchSpreadThreshold)
        n.pinchFrameSpreadThreshold = max(0.001, n.pinchFrameSpreadThreshold)
        n.swipeCoherenceThreshold = max(0.0, min(n.swipeCoherenceThreshold, 0.95))
        n.swipeAngleTolerance = max(20, min(n.swipeAngleTolerance, 45))
        let clamp = { (v: Float) in max(EdgeMargin.range.lowerBound, min(v, EdgeMargin.range.upperBound)) }
        n.edgeMargin.left   = clamp(n.edgeMargin.left)
        n.edgeMargin.right  = clamp(n.edgeMargin.right)
        n.edgeMargin.top    = clamp(n.edgeMargin.top)
        n.edgeMargin.bottom = clamp(n.edgeMargin.bottom)
        return n
    }

    private func buildDiagnostics(for rules: [GestureRule]) -> RuleDiagnostics {
        RuleDiagnostics(
            configuredFingerCounts: Set(rules.map(\.fingers)).count,
            appSpecificRules: rules.filter { $0.appFilter != nil }.count,
            openAppRulesMissingTarget: rules.filter { $0.action == .openApp && (($0.appPath?.isEmpty) != false) }.count
        )
    }
}

struct RunningAppOption: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

// ─────────────────────────────────────────────
// MARK: - Root view
// ─────────────────────────────────────────────

struct PreferencesRootView: View {
    @ObservedObject var store: PreferencesStore
    @State private var selection: SidebarItem = .gestures
    @State private var selectedRuleID: UUID?

    enum SidebarItem: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case gestures = "Gestures"
        case tuning   = "Tuning"
        case general  = "General"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentPane
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 620)
        .onAppear { store.startPollingEngineState() }
        .onDisappear { store.stopPollingEngineState() }
    }

    // MARK: Sidebar
    private var sidebar: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: sidebarIcon(item))
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Glide")
                            .font(.system(size: 12, weight: .semibold))
                        Text(store.accessibilityGranted ? "Active" : "Needs Permission")
                            .font(.system(size: 11))
                            .foregroundStyle(store.accessibilityGranted ? Color.secondary : Color.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if selection == .gestures {
                    Button { store.addRule() } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Gesture Rule")
                }
            }
        }
    }

    private func sidebarIcon(_ item: SidebarItem) -> String {
        switch item {
        case .gestures: return "hand.draw"
        case .tuning:   return "slider.horizontal.3"
        case .general:  return "gearshape"
        }
    }

    // MARK: Content (middle column)
    @ViewBuilder
    private var contentPane: some View {
        switch selection {
        case .gestures:
            GestureListView(store: store, selectedID: $selectedRuleID)
        case .tuning:
            TuningFormView(store: store)
        case .general:
            GeneralFormView(store: store)
        }
    }

    // MARK: Detail (right column)
    @ViewBuilder
    private var detailPane: some View {
        if selection == .gestures, let id = selectedRuleID,
           store.rules.contains(where: { $0.id == id }) {
            RuleDetailView(rule: store.binding(for: id), store: store)
        } else if selection == .gestures {
            emptyDetail
        } else {
            Color.clear
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text("Select a Rule")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose a gesture from the list\nto edit its action and options.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────
// MARK: - Gestures list (grouped by finger count)
// ─────────────────────────────────────────────

struct GestureListView: View {
    @ObservedObject var store: PreferencesStore
    @Binding var selectedID: UUID?

    var body: some View {
        Group {
            if store.rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                    Text("No Rules")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button("Add Gesture Rule") { store.addRule() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach(store.rulesGroupedByFingers(), id: \.fingers) { group in
                        Section {
                            ForEach(group.rules) { rule in
                                RuleRowView(rule: rule, store: store)
                                    .tag(rule.id)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: fingerIcon(group.fingers))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(badgeColor(group.fingers))
                                Text("\(group.fingers) Fingers")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.rules.count)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Gestures")
        .navigationSubtitle("\(store.rules.count) rule\(store.rules.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) { store.resetRules() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset to defaults")
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 290)
    }

    private func fingerIcon(_ n: Int) -> String {
        switch n {
        case 2:  return "hand.point.up.braille"
        case 3:  return "hand.raised"
        case 4:  return "hand.raised.fingers.spread"
        case 5:  return "hand.wave"
        default: return "hand.raised"
        }
    }
}

struct RuleRowView: View {
    let rule: GestureRule
    let store: PreferencesStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(badgeColor(rule.fingers).opacity(0.12))
                Image(systemName: directionIcon(rule.direction))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(badgeColor(rule.fingers))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.action.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(rule.direction.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if rule.direction != .click {
                        speedBadge(rule.speed)
                    }
                    if let bid = rule.appFilter {
                        Text(store.filterLabel(for: bid))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(role: .destructive) {
                store.removeRule(rule.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func speedBadge(_ speed: GestureSpeed) -> some View {
        let color: Color = speed == .fast ? .orange : speed == .slow ? .blue : .secondary
        Text(speed.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.10)))
    }
}

private func badgeColor(_ fingers: Int) -> Color {
    switch fingers {
    case 2:  return .blue
    case 3:  return .purple
    case 4:  return .orange
    default: return .pink
    }
}

private func directionIcon(_ dir: GestureDirection) -> String {
    switch dir {
    case .swipeLeft:  return "arrow.left"
    case .swipeRight: return "arrow.right"
    case .swipeUp:    return "arrow.up"
    case .swipeDown:  return "arrow.down"
    case .click:      return "cursorarrow.click"
    }
}

// ─────────────────────────────────────────────
// MARK: - Rule detail editor
// ─────────────────────────────────────────────

struct RuleDetailView: View {
    @Binding var rule: GestureRule
    let store: PreferencesStore

    var body: some View {
        Form {
            Section("Gesture") {
                Picker("Fingers", selection: $rule.fingers) {
                    ForEach(2...5, id: \.self) { n in Text("\(n) Fingers").tag(n) }
                }
                Picker("Direction", selection: $rule.direction) {
                    ForEach(GestureDirection.allCases, id: \.self) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                if rule.direction != .click {
                    Picker("Speed", selection: $rule.speed) {
                        ForEach(GestureSpeed.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }
            }

            Section("Action") {
                Picker("Action", selection: $rule.action) {
                    ForEach(GestureAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }

                if rule.action == .openApp {
                    LabeledContent("Application") {
                        Button(store.appLabel(for: rule.appPath)) {
                            store.chooseApp(for: rule.id)
                        }
                        .buttonStyle(.link)
                    }
                    if rule.appPath == nil {
                        Label("Choose an app target for this rule.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }

            Section("App Filter") {
                Picker("Active In", selection: Binding(
                    get: { rule.appFilter },
                    set: { store.setAppFilter($0, for: rule.id) })) {
                    Text("Any App").tag(String?.none)
                    Divider()
                    ForEach(store.runningApps()) { app in
                        Text(app.name).tag(Optional(app.bundleID))
                    }
                }
                .help("Restrict this rule to a specific app, or leave as Any App.")
            }

            if rule.action.supportsReciprocal, rule.direction != .click {
                Section {
                    Toggle("Reciprocal Gesture", isOn: $rule.reciprocalEnabled)
                    if rule.reciprocalEnabled, let inverse = rule.action.inverseAction {
                        LabeledContent("Reverse Action") {
                            Text(inverse.rawValue)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("Swiping in the opposite direction immediately after this gesture will perform \"\(inverse.rawValue)\".")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("Reciprocal")
                }
            }

            Section {
                Button(role: .destructive) {
                    store.removeRule(rule.id)
                } label: {
                    Label("Delete Rule", systemImage: "trash")
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(rule.action.rawValue)
        .navigationSubtitle("\(rule.fingers) fingers · \(rule.direction.rawValue)")
        .onChange(of: rule.direction) { _ in
            if rule.direction == .click { rule.speed = .normal }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Tuning form
// ─────────────────────────────────────────────

struct TuningFormView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            Section {
                TuningRow(
                    title: "Activation Threshold",
                    subtitle: "How far a finger must travel before a swipe locks in",
                    value: Binding(
                        get: { Double(store.tuning.initialThreshold) },
                        set: { v in store.updateTuning { $0.initialThreshold = Float(v) } }),
                    range: 0.005...0.060,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Switcher Step Distance",
                    subtitle: "Centroid movement per app-switcher step",
                    value: Binding(
                        get: { Double(store.tuning.appSwitcherStepThreshold) },
                        set: { v in store.updateTuning { $0.appSwitcherStepThreshold = Float(v) } }),
                    range: 0.001...0.020,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Switcher Debounce",
                    subtitle: "Minimum time between app-switcher steps",
                    value: Binding(
                        get: { store.tuning.appSwitcherDebounce },
                        set: { v in store.updateTuning { $0.appSwitcherDebounce = v } }),
                    range: 0.00...0.30,
                    unit: "s",
                    fractionDigits: 2)
            } header: {
                Text("Recognition")
            }

            Section {
                TuningRow(
                    title: "Fast Velocity Threshold",
                    subtitle: "Average finger movement per frame above which gesture is \"Fast\"",
                    value: Binding(
                        get: { Double(store.tuning.fastVelocityThreshold) },
                        set: { v in store.updateTuning { $0.fastVelocityThreshold = Float(v) } }),
                    range: 0.003...0.025,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Slow Velocity Threshold",
                    subtitle: "Average finger movement per frame below which gesture is \"Slow\"",
                    value: Binding(
                        get: { Double(store.tuning.slowVelocityThreshold) },
                        set: { v in store.updateTuning { $0.slowVelocityThreshold = Float(v) } }),
                    range: 0.001...0.015,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Speed Sample Frames",
                    subtitle: "Number of frames to average for velocity calculation",
                    value: Binding(
                        get: { Double(store.tuning.speedSampleCount) },
                        set: { v in store.updateTuning { $0.speedSampleCount = Int(v.rounded()) } }),
                    range: 2...8,
                    unit: "",
                    fractionDigits: 0)
            } header: {
                Text("Speed Classification")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed is based on how fast the finger moves (average displacement per frame), not how long the gesture takes.")
                    HStack(spacing: 0) {
                        Text("Fast").foregroundStyle(.orange).fontWeight(.medium)
                        Text(" ≥ \(String(format: "%.3f", store.tuning.fastVelocityThreshold))")
                        Text("  ·  ")
                        Text("Normal").fontWeight(.medium)
                        Text(" \(String(format: "%.3f", store.tuning.slowVelocityThreshold))–\(String(format: "%.3f", store.tuning.fastVelocityThreshold))")
                        Text("  ·  ")
                        Text("Slow").foregroundStyle(.blue).fontWeight(.medium)
                        Text(" ≤ \(String(format: "%.3f", store.tuning.slowVelocityThreshold))")
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
            }

            Section {
                TuningRow(
                    title: "Angle Tolerance",
                    subtitle: "Width (in degrees) of each cardinal direction wedge. 45° = full quadrants, lower = narrower with diagonal dead zones",
                    value: Binding(
                        get: { Double(store.tuning.swipeAngleTolerance) },
                        set: { v in store.updateTuning { $0.swipeAngleTolerance = Float(v) } }),
                    range: 20...45,
                    unit: "°",
                    fractionDigits: 0)
            } header: {
                Text("Direction Detection")
            } footer: {
                Text("Swipe direction is computed from the angle of recent finger movement (atan2), not the first axis to cross the threshold. At 45° each direction covers a full quadrant. At 30° diagonal movements are ignored until the gesture becomes more clearly directional.")
            }

            Section {
                TuningRow(
                    title: "Candidate Frames",
                    subtitle: "Frames to collect before deciding if a touch is a swipe. Lower = faster recognition, higher = better pinch rejection",
                    value: Binding(
                        get: { Double(store.tuning.candidateFrames) },
                        set: { v in store.updateTuning { $0.candidateFrames = Int(v.rounded()) } }),
                    range: 1...8,
                    unit: "",
                    fractionDigits: 0)
                TuningRow(
                    title: "Pinch Spread Threshold",
                    subtitle: "Cumulative finger spread change to veto a swipe. Higher = more lenient",
                    value: Binding(
                        get: { Double(store.tuning.pinchSpreadThreshold) },
                        set: { v in store.updateTuning { $0.pinchSpreadThreshold = Float(v) } }),
                    range: 0.002...0.050,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Pinch Frame Threshold",
                    subtitle: "Per-frame spread change for instant veto. Higher = more lenient",
                    value: Binding(
                        get: { Double(store.tuning.pinchFrameSpreadThreshold) },
                        set: { v in store.updateTuning { $0.pinchFrameSpreadThreshold = Float(v) } }),
                    range: 0.001...0.030,
                    unit: "",
                    fractionDigits: 3)
                TuningRow(
                    title: "Swipe Coherence",
                    subtitle: "Minimum directional agreement between fingers (0–1). Lower = more lenient",
                    value: Binding(
                        get: { Double(store.tuning.swipeCoherenceThreshold) },
                        set: { v in store.updateTuning { $0.swipeCoherenceThreshold = Float(v) } }),
                    range: 0.0...0.95,
                    unit: "",
                    fractionDigits: 2)
            } header: {
                Text("Pinch Veto")
            } footer: {
                Text("Controls how aggressively non-swipe gestures (pinch, zoom) are rejected. Higher values = more lenient swipe detection, but may cause false swipes during pinch.")
            }

            Section {
                Button("Reset to Defaults") { store.resetTuning() }
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tuning")
    }
}

struct TuningRow: View {
    let title: String
    var subtitle: String = ""
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let fractionDigits: Int

    var formatted: String {
        let s = String(format: "%.\(fractionDigits)f", value)
        return unit.isEmpty ? s : "\(s) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                HStack(spacing: 10) {
                    Slider(value: $value, in: range)
                        .frame(width: 180)
                    Text(formatted)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Trackpad Margin Visual
// ─────────────────────────────────────────────

/// A realistic-looking trackpad preview that renders the four edge margins
/// as animated translucent shadow overlays. The overlays resize live as the
/// user drags the sliders. An optional live centroid dot shows the current
/// touch position when fingers are on the trackpad.
struct TrackpadMarginView: View {
    /// Margin fractions (0–0.20) for each edge.
    var marginLeft:   Double
    var marginRight:  Double
    var marginTop:    Double
    var marginBottom: Double
    /// Whether to show the live centroid dot.
    var fingerCount: Int
    var centroidX: Float
    var centroidY: Float   // 0 = bottom in MT coords — we flip for drawing

    // Fixed visual size (points)
    private let padW: CGFloat = 260
    private let padH: CGFloat = 155
    private let cornerR: CGFloat = 14

    var body: some View {
        ZStack {
            // ── Trackpad body ──
            RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.74)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color(white: 0.55), Color(white: 0.45)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            // ── Surface texture gloss ──
            RoundedRectangle(cornerRadius: cornerR - 1, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                        startPoint: .top, endPoint: .center)
                )

            // ── Margin overlays ──
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let l = CGFloat(marginLeft)  * w
                let r = CGFloat(marginRight) * w
                let t = CGFloat(marginTop)   * h
                let b = CGFloat(marginBottom) * h

                // Shadow tint for margin zones
                let shadowColor = Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.28)
                let borderColor = Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.55)

                ZStack(alignment: .topLeading) {
                    // Left
                    if l > 0 {
                        marginOverlay(shadowColor)
                            .frame(width: max(1, l), height: h)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(borderColor)
                                    .frame(width: 1.5)
                            }
                    }
                    // Right
                    if r > 0 {
                        marginOverlay(shadowColor)
                            .frame(width: max(1, r), height: h)
                            .offset(x: w - r)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(borderColor)
                                    .frame(width: 1.5)
                                    .offset(x: w - r)
                            }
                    }
                    // Top
                    if t > 0 {
                        marginOverlay(shadowColor)
                            .frame(width: w, height: max(1, t))
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(borderColor)
                                    .frame(height: 1.5)
                            }
                    }
                    // Bottom
                    if b > 0 {
                        marginOverlay(shadowColor)
                            .frame(width: w, height: max(1, b))
                            .offset(y: h - b)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(borderColor)
                                    .frame(height: 1.5)
                                    .offset(y: h - b)
                            }
                    }

                    // ── Live centroid dot ──
                    // Only visible when fingers are on the trackpad (fingerCount >= 2)
                    if fingerCount >= 2 {
                        // MT cy=0 is bottom → flip to screen coords
                        let dotX = CGFloat(centroidX) * w
                        let dotY = (1.0 - CGFloat(centroidY)) * h
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 22, height: 22)
                                .blur(radius: 3)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color(red: 0.4, green: 0.75, blue: 1.0),
                                                 Color(red: 0.15, green: 0.45, blue: 0.9)],
                                        center: .center,
                                        startRadius: 0, endRadius: 7)
                                )
                                .frame(width: 14, height: 14)
                                .shadow(color: Color(red: 0.2, green: 0.5, blue: 1.0).opacity(0.7), radius: 5)
                        }
                        .position(x: dotX, y: dotY)
                        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.75), value: dotX)
                        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.75), value: dotY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerR - 1, style: .continuous))
            }

            // ── Click bar hint at the bottom ──
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.55).opacity(0.35))
                    .frame(width: 44, height: 3)
                    .padding(.bottom, 7)
            }
        }
        .frame(width: padW, height: padH)
    }

    @ViewBuilder
    private func marginOverlay(_ color: Color) -> some View {
        color
            .animation(.easeInOut(duration: 0.18), value: marginLeft)
            .animation(.easeInOut(duration: 0.18), value: marginRight)
            .animation(.easeInOut(duration: 0.18), value: marginTop)
            .animation(.easeInOut(duration: 0.18), value: marginBottom)
    }
}

// ─────────────────────────────────────────────
// MARK: - Edge Margin Sliders Section
// ─────────────────────────────────────────────

struct EdgeMarginSectionView: View {
    @ObservedObject var store: PreferencesStore

    private var m: EdgeMargin { store.tuning.edgeMargin }

    var body: some View {
        Section {
            // ── Enable / Disable toggle ──
            Toggle("Enable Edge Margin", isOn: Binding(
                get: { store.tuning.edgeMarginEnabled },
                set: { v in store.updateTuning { $0.edgeMarginEnabled = v } }))
            .padding(.bottom, 2)

            if store.tuning.edgeMarginEnabled {
                // ── Trackpad visual ──
                HStack {
                    Spacer()
                    TrackpadMarginView(
                        marginLeft:   Double(m.left),
                        marginRight:  Double(m.right),
                        marginTop:    Double(m.top),
                        marginBottom: Double(m.bottom),
                        fingerCount:  store.fingerCount,
                        centroidX:    store.centroidX,
                        centroidY:    store.centroidY
                    )
                    Spacer()
                }
                .padding(.vertical, 10)

                // ── Per-side sliders ──
                marginSlider("Left Margin",   value: Binding(
                    get: { Double(m.left) },
                    set: { v in store.updateTuning { $0.edgeMargin.left = Float(v) } }))
                marginSlider("Right Margin",  value: Binding(
                    get: { Double(m.right) },
                    set: { v in store.updateTuning { $0.edgeMargin.right = Float(v) } }))
                marginSlider("Top Margin",    value: Binding(
                    get: { Double(m.top) },
                    set: { v in store.updateTuning { $0.edgeMargin.top = Float(v) } }))
                marginSlider("Bottom Margin", value: Binding(
                    get: { Double(m.bottom) },
                    set: { v in store.updateTuning { $0.edgeMargin.bottom = Float(v) } }))

                // ── Reset button ──
                HStack {
                    Spacer()
                    Button("Reset Margins") {
                        withAnimation {
                            store.updateTuning {
                                $0.edgeMargin = EdgeMargin()
                            }
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }

        } header: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.dashed.badge.record")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Trackpad Edge Margin")
            }
        } footer: {
            Text("Gestures starting within the shaded margin zones near the trackpad bezel are ignored — preventing accidental triggers when resting fingers near the edges.")
        }
    }

    @ViewBuilder
    private func marginSlider(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Slider(value: value,
                       in: Double(EdgeMargin.range.lowerBound)...Double(EdgeMargin.range.upperBound),
                       step: 0.005)
                    .frame(width: 160)
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Accessibility Card
// ─────────────────────────────────────────────

struct AccessibilityStatusCard: View {
    let granted: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            // Animated ring indicator
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .frame(width: 46, height: 46)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        granted
                            ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse)
                Circle()
                    .strokeBorder(granted ? Color.green.opacity(0.4) : Color.orange.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 46, height: 46)
                Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(granted ? .green : .orange)
            }
            .onAppear { pulse = granted }
            .onChange(of: granted) { pulse = $0 }

            VStack(alignment: .leading, spacing: 3) {
                Text(granted ? "Accessibility Granted" : "Accessibility Required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(granted ? Color.primary : Color.orange)
                Text(granted
                     ? "Glide has the permissions it needs."
                     : "Open System Settings to grant access.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// ─────────────────────────────────────────────
// MARK: - Engine Status Card
// ─────────────────────────────────────────────

struct EngineStatusCard: View {
    let phase: String
    let fingerCount: Int
    let reciprocalActive: Bool
    @State private var phasePulse = false

    var phaseColor: Color {
        switch phase {
        case "Idle":            return .gray
        case "Candidate":       return .yellow
        case "Locked (Swipe)":  return .green
        case "Ignored":         return .red
        case "Fired":           return .blue
        case "App Switcher":    return .purple
        default:                return .gray
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Phase indicator
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(phaseColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .scaleEffect(phasePulse && (phase == "Locked (Swipe)" || phase == "Fired") ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: phasePulse)
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 10, height: 10)
                }
                Text(phase)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(phaseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 70)
            .onAppear { phasePulse = true }

            Divider().frame(height: 40)

            // Finger count
            VStack(spacing: 4) {
                Text("\(fingerCount)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(fingerCount >= 2 ? Color.primary : Color.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: fingerCount)
                Text("Fingers")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 60)

            Divider().frame(height: 40)

            // Reciprocal badge
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(reciprocalActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08))
                    Image(systemName: reciprocalActive ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(reciprocalActive ? Color.green : Color.gray)
                }
                .frame(width: 36, height: 36)
                Text("Reciprocal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 70)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// ─────────────────────────────────────────────
// MARK: - General form
// ─────────────────────────────────────────────

struct GeneralFormView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            // ── Accessibility ──
            Section {
                AccessibilityStatusCard(granted: store.accessibilityGranted)
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Accessibility")
                }
            }

            // ── Startup ──
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { _ in store.toggleLaunchAtLogin() }
                ))
                .help("Automatically start Glide when you log in.")
            }

            // ── Window Targeting ──
            Section("Window Targeting") {
                Picker("Strategy", selection: Binding(
                    get: { store.windowTargetingMode },
                    set: { store.updateWindowTargetingMode($0) })) {
                    ForEach(WindowTargetingMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            // ── Feedback ──
            Section {
                Toggle("Haptic Feedback", isOn: Binding(
                    get: { store.hapticFeedbackEnabled },
                    set: { store.updateHapticFeedback($0) }))
                Toggle("Debug Logging", isOn: Binding(
                    get: { store.debugLoggingEnabled },
                    set: { store.updateDebugLogging($0) }))
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Feedback & Debugging")
                }
            } footer: {
                Text("Haptic feedback uses the Force Touch actuator for each gesture. Debug logging prints engine output to Console.app.")
            }

            // ── Edge Margin ──
            EdgeMarginSectionView(store: store)

            // ── Engine Status ──
            Section {
                EngineStatusCard(
                    phase: store.enginePhase,
                    fingerCount: store.fingerCount,
                    reciprocalActive: store.reciprocalActive)
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Engine Status")
                }
            }

            // ── Stats ──
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        statPill(
                            label: "Rules",
                            value: "\(store.rules.count)",
                            color: .blue)
                        statPill(
                            label: "Finger Sets",
                            value: "\(store.diagnostics.configuredFingerCounts)/4",
                            color: .purple)
                        statPill(
                            label: "App Rules",
                            value: "\(store.diagnostics.appSpecificRules)",
                            color: .orange)
                        if store.diagnostics.openAppRulesMissingTarget > 0 {
                            statPill(
                                label: "Missing Target",
                                value: "\(store.diagnostics.openAppRulesMissingTarget)",
                                color: .red)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Stats")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    @ViewBuilder
    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }
}

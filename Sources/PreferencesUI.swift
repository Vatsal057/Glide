import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

// ─────────────────────────────────────────────
// MARK: - Store
// ─────────────────────────────────────────────

@MainActor
final class PreferencesStore: ObservableObject {

    // ── Config I/O feedback ──
    enum ConfigAlert: Equatable {
        case exportSuccess(String)   // path
        case importSuccess
        case error(String)
    }
    @Published var configAlert: ConfigAlert? = nil

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
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var diagnostics = RuleDiagnostics()

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
        launchAtLoginEnabled = s.launchAtLoginEnabled
        accessibilityGranted = AXIsProcessTrusted()
        diagnostics = buildDiagnostics(for: rules)
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

    func updateLaunchAtLogin(_ v: Bool) {
        launchAtLoginEnabled = v
        Settings.shared.launchAtLoginEnabled = v
        do {
            if v {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            AppLogger.debug("[Config] SMAppService error: \(error.localizedDescription)")
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            Settings.shared.launchAtLoginEnabled = launchAtLoginEnabled
        }
    }

    func updateTuning(_ mutate: (inout GestureTuning) -> Void) {
        var copy = tuning
        mutate(&copy)
        Settings.shared.tuning = copy          // Settings.normalizedTuning runs here + saves
        tuning = Settings.shared.tuning        // read back the clamped value
    }

    func resetTuning() {
        Settings.shared.resetTuning()
        tuning = Settings.shared.tuning
    }

    // ── YAML Config Export — copies live file to user-chosen location ──
    func exportConfig() {
        let panel = NSSavePanel()
        panel.title                    = "Export Glide Config"
        panel.nameFieldLabel           = "Save As:"
        panel.nameFieldStringValue     = "glide_config.yaml"
        panel.allowedContentTypes      = [.yaml]
        panel.canCreateDirectories     = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if GlideConfigStore.shared.exportTo(url) {
            configAlert = .exportSuccess(url.lastPathComponent)
        } else {
            configAlert = .error("Export failed — check file permissions.")
        }
    }

    // ── YAML Config Import — loads file, applies, saves to live path ──
    func importConfig() {
        let panel = NSOpenPanel()
        panel.title                   = "Import Glide Config"
        panel.allowedContentTypes     = [.yaml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if GlideConfigStore.shared.importFrom(url) {
            reload()
            configAlert = .importSuccess
        } else {
            configAlert = .error("File is not a valid Glide config.")
        }
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
        Settings.shared.rules = rules.map(sanitizedRule)
        rules = Settings.shared.rules       // read back after canonicalization
        diagnostics = buildDiagnostics(for: rules)
    }

    private func nextAvailableRule() -> GestureRule? {
        for fingers in 3...5 {
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
                    ForEach(3...5, id: \.self) { n in Text("\(n) Fingers").tag(n) }
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
        .onChange(of: rule.direction) { newDirection in
            if newDirection == .click { rule.speed = .normal }
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

/// MacBook-style trackpad preview. Margin dead-zones fill their full edge area.
/// The finger-notch groove sits inset into the bottom bezel.
struct TrackpadMarginView: View {
    var marginLeft:   Double
    var marginRight:  Double
    var marginTop:    Double
    var marginBottom: Double
    var fingerCount:  Int
    var centroidX:    Float
    var centroidY:    Float   // 0 = bottom in MT coords — flipped for drawing

    private let W: CGFloat      = 294
    private let H: CGFloat      = 190
    private let outerR: CGFloat = 24
    private let bezel: CGFloat  = 11
    private var innerR: CGFloat { outerR - bezel * 0.55 }

    private let notchW: CGFloat = 44
    private let notchH: CGFloat = 7
    private let notchR: CGFloat = 3.5

    var body: some View {
        ZStack {
            // ── Outer casing ──
            RoundedRectangle(cornerRadius: outerR, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.29), Color(white: 0.22), Color(white: 0.18)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: outerR, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color(white: 0.46), Color(white: 0.16)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1.0))
                .shadow(color: .black.opacity(0.50), radius: 14, y: 6)
                .shadow(color: .black.opacity(0.20), radius: 3,  y: 1)

            // ── Glass surface (inset from casing) ──
            RoundedRectangle(cornerRadius: innerR, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.24), Color(white: 0.19)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: innerR, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))))
                .overlay(RoundedRectangle(cornerRadius: innerR, style: .continuous)
                    .strokeBorder(Color(white: 0.35), lineWidth: 0.5))
                // ── Margin strips overlay on the glass ──
                .overlay {
                    GeometryReader { geo in
                        let gW = geo.size.width
                        let gH = geo.size.height
                        let l  = CGFloat(marginLeft)   * gW
                        let r  = CGFloat(marginRight)  * gW
                        let t  = CGFloat(marginTop)    * gH
                        let b  = CGFloat(marginBottom) * gH
                        let fill   = Color(white: 0.08).opacity(0.55)
                        let border = Color(white: 0.55).opacity(0.28)

                        ZStack {
                            // Left — full height, aligned to leading
                            if l > 0.5 {
                                fill
                                    .frame(width: l, height: gH)
                                    .frame(width: gW, height: gH, alignment: .leading)
                                    .overlay(alignment: .leading) {
                                        border.frame(width: 1).offset(x: l)
                                    }
                                    .animation(.easeInOut(duration: 0.13), value: l)
                            }
                            // Right — full height, aligned to trailing
                            if r > 0.5 {
                                fill
                                    .frame(width: r, height: gH)
                                    .frame(width: gW, height: gH, alignment: .trailing)
                                    .overlay(alignment: .trailing) {
                                        border.frame(width: 1).offset(x: -r)
                                    }
                                    .animation(.easeInOut(duration: 0.13), value: r)
                            }
                            // Top — full width, aligned to top
                            if t > 0.5 {
                                fill
                                    .frame(width: gW, height: t)
                                    .frame(width: gW, height: gH, alignment: .top)
                                    .overlay(alignment: .top) {
                                        border.frame(height: 1).offset(y: t)
                                    }
                                    .animation(.easeInOut(duration: 0.13), value: t)
                            }
                            // Bottom — full width, aligned to bottom
                            if b > 0.5 {
                                fill
                                    .frame(width: gW, height: b)
                                    .frame(width: gW, height: gH, alignment: .bottom)
                                    .overlay(alignment: .bottom) {
                                        border.frame(height: 1).offset(y: -b)
                                    }
                                    .animation(.easeInOut(duration: 0.13), value: b)
                            }

                            // ── Live centroid dot ──
                            if fingerCount >= 2 {
                                let dotX = CGFloat(centroidX) * gW
                                let dotY = (1.0 - CGFloat(centroidY)) * gH
                                let isMargin =
                                    CGFloat(centroidX)       < CGFloat(marginLeft)        ||
                                    CGFloat(centroidX)       > 1.0 - CGFloat(marginRight) ||
                                    1.0 - CGFloat(centroidY) < CGFloat(marginTop)         ||
                                    1.0 - CGFloat(centroidY) > 1.0 - CGFloat(marginBottom)
                                let dot: Color = isMargin ? .orange : Color(red: 0.25, green: 0.88, blue: 0.50)

                                ZStack {
                                    Circle().fill(dot.opacity(0.20)).frame(width: 26, height: 26).blur(radius: 5)
                                    Circle().fill(dot).frame(width: 12, height: 12)
                                        .shadow(color: dot.opacity(0.75), radius: 6)
                                    Text("\(fingerCount)")
                                        .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.black.opacity(0.70))
                                }
                                .position(x: dotX, y: dotY)
                                .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.70), value: dotX)
                                .animation(.interactiveSpring(response: 0.14, dampingFraction: 0.70), value: dotY)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: innerR, style: .continuous))
                }
                .padding(bezel)

            // ── Notch groove — recessed into the bottom bezel ──
            VStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: notchR, style: .continuous)
                        .fill(Color(white: 0.09))
                        .frame(width: notchW, height: notchH)
                        .shadow(color: .black.opacity(0.70), radius: 3, y: 1)
                    RoundedRectangle(cornerRadius: notchR - 1, style: .continuous)
                        .fill(Color(white: 0.40))
                        .frame(width: notchW - 4, height: 1.0)
                        .offset(y: -(notchH / 2) + 1.5)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(white: 0.13))
                        .frame(width: notchW - 10, height: notchH - 3)
                }
                .offset(y: -3)
            }
        }
        .frame(width: W, height: H)
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
            .onChange(of: granted) { newValue in pulse = newValue }

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

            // ── Launch ──
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.launchAtLoginEnabled },
                    set: { store.updateLaunchAtLogin($0) }))
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                    Text("Launch")
                }
            }

            // ── Configuration (Import / Export YAML) ──
            ConfigurationSectionView(store: store)

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

// ─────────────────────────────────────────────
// MARK: - Configuration section (Import / Export YAML)
// ─────────────────────────────────────────────

struct ConfigurationSectionView: View {
    @ObservedObject var store: PreferencesStore
    @State private var bannerVisible = false
    @State private var bannerTimer: Timer?

    private var livePath: String { GlideConfigStore.shared.configPath }

    var body: some View {
        Section {
            // ── Live file path row ──
            LabeledContent("Live Config File") {
                HStack(spacing: 8) {
                    Text(livePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.selectFile(
                            livePath,
                            inFileViewerRootedAtPath: (livePath as NSString).deletingLastPathComponent
                        )
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reveal in Finder")
                }
            }

            // ── Action buttons ──
            HStack(spacing: 12) {
                Button {
                    store.exportConfig()
                } label: {
                    Label("Export Copy…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Copy the live config.yaml to a custom location for backup or sharing")

                Button {
                    store.importConfig()
                } label: {
                    Label("Import Config…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .help("Restore gestures, tuning, and preferences from a .yaml file")

                Spacer()
            }
            .padding(.vertical, 2)

            // ── Inline feedback banner ──
            if bannerVisible, let alert = store.configAlert {
                HStack(spacing: 10) {
                    Image(systemName: alertIcon(alert))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(alertColor(alert))
                    Text(alertMessage(alert))
                        .font(.system(size: 12))
                        .foregroundStyle(alertColor(alert))
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(alertColor(alert).opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(alertColor(alert).opacity(0.25), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("Configuration")
            }
        } footer: {
            Text("config.yaml is saved automatically to Application Support whenever you change any setting. Use \"Export Copy…\" to back it up, or \"Import Config…\" to restore after a reinstall.")
        }
        .onChange(of: store.configAlert) { _ in showBanner() }
    }

    private func showBanner() {
        guard store.configAlert != nil else { return }
        withAnimation(.easeOut(duration: 0.22)) { bannerVisible = true }
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.22)) { bannerVisible = false }
            }
        }
    }

    private func alertIcon(_ a: PreferencesStore.ConfigAlert) -> String {
        switch a {
        case .exportSuccess: return "checkmark.circle.fill"
        case .importSuccess: return "checkmark.circle.fill"
        case .error:         return "exclamationmark.triangle.fill"
        }
    }

    private func alertColor(_ a: PreferencesStore.ConfigAlert) -> Color {
        switch a {
        case .exportSuccess, .importSuccess: return .green
        case .error:                         return .red
        }
    }

    private func alertMessage(_ a: PreferencesStore.ConfigAlert) -> String {
        switch a {
        case .exportSuccess(let name): return "Config exported to \"\(name)\"."
        case .importSuccess:           return "Config imported — gestures and settings updated."
        case .error(let msg):          return msg
        }
    }
}
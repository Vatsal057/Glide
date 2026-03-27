import Cocoa

// MARK: - Enums

enum GestureSpeed: String, Codable, CaseIterable {
    case slow   = "Slow"
    case normal = "Normal"
    case fast   = "Fast"
}

enum GestureDirection: String, Codable, CaseIterable {
    case click           = "Click"
    case swipeHorizontal = "Swipe Left/Right"
    case swipeUp         = "Swipe Up"
    case swipeDown       = "Swipe Down"
}

enum GestureAction: String, Codable, CaseIterable {
    case quitApp         = "Quit App"
    case appSwitcher     = "App Switcher"
    case missionControl  = "Mission Control"
    case minimizeWindow  = "Minimize Window"
    case maximizeWindow  = "Maximize Window"
    case restoreWindow   = "Restore Window"
    case enterFullscreen = "Enter Fullscreen"
    case exitFullscreen  = "Exit Fullscreen"
    case doNothing       = "Do Nothing"
}

// MARK: - GestureRule

struct GestureRule: Codable, Equatable {
    var id        = UUID()
    var fingers:   Int
    var direction: GestureDirection
    var speed:     GestureSpeed
    var action:    GestureAction

    init(fingers: Int, direction: GestureDirection, speed: GestureSpeed = .normal, action: GestureAction) {
        self.fingers   = fingers
        self.direction = direction
        self.speed     = speed
        self.action    = action
    }

    // Backward-compatible: old saved rules without a "speed" key decode as .normal
    init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self,         forKey: .id)        ?? UUID()
        fingers   = try c.decode(Int.self,                   forKey: .fingers)
        direction = try c.decode(GestureDirection.self,      forKey: .direction)
        speed     = try c.decodeIfPresent(GestureSpeed.self, forKey: .speed)     ?? .normal
        action    = try c.decode(GestureAction.self,         forKey: .action)
    }
}

// MARK: - Settings

class Settings {
    static let shared = Settings()

    private let kContextAwareness = "enableContextAwareness"
    private let kGestureRules     = "gestureRulesV2"

    var enableContextAwareness: Bool {
        get { UserDefaults.standard.object(forKey: kContextAwareness) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: kContextAwareness) }
    }

    private var _cachedRules: [GestureRule]?

    var rules: [GestureRule] {
        get {
            if let cached = _cachedRules { return cached }
            if let data    = UserDefaults.standard.data(forKey: kGestureRules),
               let decoded = try? JSONDecoder().decode([GestureRule].self, from: data) {
                _cachedRules = decoded
                return decoded
            }
            let defaults: [GestureRule] = [
                GestureRule(fingers: 3, direction: .click,           speed: .normal, action: .quitApp),
                GestureRule(fingers: 3, direction: .swipeHorizontal, speed: .normal, action: .appSwitcher),
                GestureRule(fingers: 3, direction: .swipeUp,         speed: .normal, action: .missionControl),
                GestureRule(fingers: 3, direction: .swipeDown,       speed: .normal, action: .minimizeWindow),
                GestureRule(fingers: 4, direction: .swipeUp,         speed: .normal, action: .maximizeWindow),
                GestureRule(fingers: 4, direction: .swipeDown,       speed: .normal, action: .restoreWindow),
                GestureRule(fingers: 5, direction: .swipeUp,         speed: .normal, action: .enterFullscreen),
                GestureRule(fingers: 5, direction: .swipeDown,       speed: .normal, action: .exitFullscreen),
            ]
            _cachedRules = defaults
            return defaults
        }
        set {
            _cachedRules = newValue
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: kGestureRules)
            }
        }
    }
}

// MARK: - SettingsWindowController

class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private var rulesStackView: NSStackView!
    private var contextCheckbox: NSButton!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title   = "Glide Preferences"
        window.minSize = NSSize(width: 700, height: 350)
        window.center()
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let window = window else { return }
        let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))

        contextCheckbox = NSButton(
            checkboxWithTitle: "Context Awareness (swipe up restores minimized app, swipe down closes Mission Control)",
            target: self,
            action: #selector(contextAwarenessChanged)
        )
        contextCheckbox.state = Settings.shared.enableContextAwareness ? .on : .off
        contextCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contextCheckbox)

        let headerRow = makeHeaderRow()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerRow)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.drawsBackground     = false
        contentView.addSubview(scrollView)

        rulesStackView             = NSStackView()
        rulesStackView.orientation = .vertical
        rulesStackView.spacing     = 15
        rulesStackView.alignment   = .leading
        rulesStackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rulesStackView)
        scrollView.documentView = documentView

        let addButton = NSButton(title: "+ Add Rule", target: self, action: #selector(addRuleClicked))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        NSLayoutConstraint.activate([
            contextCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            contextCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contextCheckbox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            headerRow.topAnchor.constraint(equalTo: contextCheckbox.bottomAnchor, constant: 20),
            headerRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -20),

            rulesStackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 10),
            rulesStackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 10),
            rulesStackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -10),
            rulesStackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -10),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.widthAnchor.constraint(equalToConstant: 100),
        ])

        window.contentView = contentView
        reloadRulesUI()
    }

    private func makeHeaderRow() -> NSView {
        func label(_ text: String) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font      = .systemFont(ofSize: 11, weight: .semibold)
            f.textColor = .secondaryLabelColor
            return f
        }
        let fingers   = label("Fingers")
        let direction = label("Direction")
        let speed     = label("Speed")
        let spacer    = label("")
        let action    = label("Action")

        let stack = NSStackView(views: [fingers, direction, speed, spacer, action])
        stack.orientation = .horizontal
        stack.spacing     = 15
        stack.alignment   = .centerY

        fingers.widthAnchor.constraint(equalToConstant: 100).isActive   = true
        direction.widthAnchor.constraint(equalToConstant: 140).isActive = true
        speed.widthAnchor.constraint(equalToConstant: 90).isActive      = true
        spacer.widthAnchor.constraint(equalToConstant: 14).isActive     = true
        action.widthAnchor.constraint(equalToConstant: 150).isActive    = true
        return stack
    }

    @objc private func contextAwarenessChanged() {
        Settings.shared.enableContextAwareness = (contextCheckbox.state == .on)
    }

    @objc private func addRuleClicked() {
        var rules = Settings.shared.rules
        rules.append(GestureRule(fingers: 3, direction: .click, speed: .normal, action: .doNothing))
        Settings.shared.rules = rules
        reloadRulesUI()
    }

    @objc private func removeRuleClicked(_ sender: NSButton) {
        let index = sender.tag
        var rules = Settings.shared.rules
        guard index >= 0 && index < rules.count else { return }
        rules.remove(at: index)
        Settings.shared.rules = rules
        reloadRulesUI()
    }

    @objc private func ruleChanged(_ sender: NSPopUpButton) {
        guard let rowView = sender.superview?.superview as? RuleRowView else { return }
        let index = rowView.customTag
        var rules = Settings.shared.rules
        guard index >= 0 && index < rules.count else { return }
        rules[index] = rowView.getRule()
        Settings.shared.rules = rules
        rowView.updateSpeedVisibility()
    }

    private func reloadRulesUI() {
        rulesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, rule) in Settings.shared.rules.enumerated() {
            let row = RuleRowView(
                rule: rule, index: index,
                target: self as AnyObject,
                changeAction: #selector(ruleChanged(_:)),
                removeAction: #selector(removeRuleClicked(_:))
            )
            rulesStackView.addArrangedSubview(row)
        }
        if let docView = rulesStackView.superview {
            docView.setFrameSize(rulesStackView.fittingSize)
        }
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - RuleRowView

class RuleRowView: NSView {
    var fingersPopup:   NSPopUpButton!
    var directionPopup: NSPopUpButton!
    var speedPopup:     NSPopUpButton!
    var actionPopup:    NSPopUpButton!
    var customTag:      Int = 0

    init(rule: GestureRule, index: Int, target: AnyObject?, changeAction: Selector, removeAction: Selector) {
        super.init(frame: .zero)
        customTag = index
        translatesAutoresizingMaskIntoConstraints = false

        fingersPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fingersPopup.addItems(withTitles: ["3 Fingers", "4 Fingers", "5 Fingers"])
        fingersPopup.selectItem(withTitle: "\(rule.fingers) Fingers")
        fingersPopup.target = target
        fingersPopup.action = changeAction

        directionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        directionPopup.addItems(withTitles: GestureDirection.allCases.map { $0.rawValue })
        directionPopup.selectItem(withTitle: rule.direction.rawValue)
        directionPopup.target = target
        directionPopup.action = changeAction

        speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        speedPopup.addItems(withTitles: GestureSpeed.allCases.map { $0.rawValue })
        speedPopup.selectItem(withTitle: rule.speed.rawValue)
        speedPopup.target = target
        speedPopup.action = changeAction

        let arrowLabel = NSTextField(labelWithString: "→")
        arrowLabel.isEditable      = false
        arrowLabel.isBordered      = false
        arrowLabel.drawsBackground = false
        arrowLabel.font            = .systemFont(ofSize: 14, weight: .bold)

        actionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        actionPopup.addItems(withTitles: GestureAction.allCases.map { $0.rawValue })
        actionPopup.selectItem(withTitle: rule.action.rawValue)
        actionPopup.target = target
        actionPopup.action = changeAction

        let removeButton = NSButton(title: "✕", target: target, action: removeAction)
        removeButton.isBordered = false
        removeButton.tag        = index

        let stack = NSStackView(views: [fingersPopup, directionPopup, speedPopup, arrowLabel, actionPopup, removeButton])
        stack.orientation = .horizontal
        stack.spacing     = 15
        stack.alignment   = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            fingersPopup.widthAnchor.constraint(equalToConstant: 100),
            directionPopup.widthAnchor.constraint(equalToConstant: 140),
            speedPopup.widthAnchor.constraint(equalToConstant: 90),
            actionPopup.widthAnchor.constraint(equalToConstant: 150),
            removeButton.widthAnchor.constraint(equalToConstant: 30),
        ])

        updateSpeedVisibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Speed is meaningless for Click gestures — hide it to avoid confusion
    func updateSpeedVisibility() {
        let isClick = GestureDirection(rawValue: directionPopup.titleOfSelectedItem ?? "") == .click
        speedPopup.isHidden = isClick
    }

    func getRule() -> GestureRule {
        let fTitle = fingersPopup.titleOfSelectedItem ?? "3 Fingers"
        let f      = Int(fTitle.split(separator: " ").first ?? "3") ?? 3

        let dTitle = directionPopup.titleOfSelectedItem ?? GestureDirection.click.rawValue
        let d      = GestureDirection(rawValue: dTitle) ?? .click

        let sTitle = speedPopup.titleOfSelectedItem ?? GestureSpeed.normal.rawValue
        let s      = (d == .click) ? .normal : (GestureSpeed(rawValue: sTitle) ?? .normal)

        let aTitle = actionPopup.titleOfSelectedItem ?? GestureAction.doNothing.rawValue
        let a      = GestureAction(rawValue: aTitle)  ?? .doNothing

        return GestureRule(fingers: f, direction: d, speed: s, action: a)
    }
}

import SwiftUI
import Combine

// MARK: - Enums

enum FingerCount: Int, CaseIterable, Codable, Identifiable {
    case three = 3, four = 4, five = 5
    var id: Int { rawValue }
    var label: String { "\(rawValue) Fingers" }
}

enum GestureType: String, CaseIterable, Codable, Identifiable {
    case swipeUp = "Swipe Up"
    case swipeDown = "Swipe Down"
    case swipeLeft = "Swipe Left"
    case swipeRight = "Swipe Right"
    case click = "Click"
    case forceClick = "Force Click"
    var id: String { rawValue }
}

enum SwipeSpeed: String, CaseIterable, Codable, Identifiable {
    case slow = "Slow", normal = "Normal", fast = "Fast"
    var id: String { rawValue }
}

enum ModifierKey: String, CaseIterable, Codable, Identifiable {
    case none = "None"
    case command = "⌘ Command"
    case shift = "⇧ Shift"
    case option = "⌥ Option"
    case control = "⌃ Control"
    var id: String { rawValue }
}

enum WindowState: String, CaseIterable, Codable, Identifiable {
    case any = "Any"
    case fullscreen = "Fullscreen"
    case notFullscreen = "Not Fullscreen"
    case maximized = "Maximized"
    case notMaximized = "Not Maximized"
    var id: String { rawValue }
}

enum GestureAction: String, CaseIterable, Codable, Identifiable {
    // Apps
    case quitAppUnderCursor = "Quit App Under Cursor"
    case forceQuitAppUnderCursor = "Force Quit App Under Cursor"
    case quitFrontmostApp = "Quit Frontmost App"
    case hideAppUnderCursor = "Hide App Under Cursor"
    case hideOtherApps = "Hide Other Apps"
    case openApp = "Open App…"
    case nextApp = "Next App (App Switcher)"
    case prevApp = "Previous App (App Switcher)"
    case activateNextApp = "Activate Next App"
    case activatePrevApp = "Activate Previous App"
    // Windows
    case minimizeWindow = "Minimize Window"
    case minimizeAllApps = "Minimize All Apps"
    case restoreMinimizedApps = "Restore Minimized Apps"
    case maximizeWindow = "Maximize Window"
    case restoreWindow = "Restore / Un-maximize Window"
    case closeWindow = "Close Window"
    case enterFullscreen = "Enter Fullscreen"
    case exitFullscreen = "Exit Fullscreen"
    case toggleFullscreen = "Toggle Fullscreen"
    case cycleWindows = "Cycle Windows (⌘`)"
    case snapLeft = "Snap: Left Half"
    case snapRight = "Snap: Right Half"
    case snapTopLeft = "Snap: Top-Left"
    case snapTopRight = "Snap: Top-Right"
    case snapBottomLeft = "Snap: Bottom-Left"
    case snapBottomRight = "Snap: Bottom-Right"
    case centerWindow = "Center Window"
    case moveToNextDisplay = "Move to Next Display"
    // Screenshots
    case screenshotArea = "Screenshot (Area)"
    case screenshotFull = "Screenshot (Full)"
    case screenshotAreaClipboard = "Screenshot (Area → Clipboard)"
    case screenshotFullClipboard = "Screenshot (Full → Clipboard)"
    case screenshotToolbar = "Screenshot Toolbar"
    // Editing
    case copy = "Copy"
    case paste = "Paste"
    case cut = "Cut"
    case undo = "Undo"
    case redo = "Redo"
    case selectAll = "Select All"
    case find = "Find"
    case emojiSymbols = "Emoji & Symbols"
    case reloadPage = "Reload Page"
    case newTab = "New Tab"
    // Media
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case mute = "Mute"
    case playPause = "Play / Pause"
    case nextTrack = "Next Track"
    case prevTrack = "Previous Track"
    case brightnessUp = "Brightness Up"
    case brightnessDown = "Brightness Down"
    // System
    case missionControl = "Mission Control"
    case appExpose = "App Exposé"
    case showDesktop = "Show Desktop"
    case launchpad = "Launchpad"
    case spotlight = "Spotlight"
    case notificationCenter = "Notification Center"
    case lockScreen = "Lock Screen"
    case sleep = "Sleep"
    case emptyTrash = "Empty Trash"
    case openFinder = "Open Finder"
    case openDownloads = "Open Downloads"
    // Other
    case doNothing = "Do Nothing"

    var id: String { rawValue }

    var category: String {
        switch self {
        case .quitAppUnderCursor, .forceQuitAppUnderCursor, .quitFrontmostApp,
             .hideAppUnderCursor, .hideOtherApps, .openApp,
             .nextApp, .prevApp, .activateNextApp, .activatePrevApp:
            return "Apps"
        case .minimizeWindow, .minimizeAllApps, .restoreMinimizedApps,
             .maximizeWindow, .restoreWindow, .closeWindow,
             .enterFullscreen, .exitFullscreen, .toggleFullscreen, .cycleWindows,
             .snapLeft, .snapRight, .snapTopLeft, .snapTopRight, .snapBottomLeft,
             .snapBottomRight, .centerWindow, .moveToNextDisplay:
            return "Windows"
        case .screenshotArea, .screenshotFull, .screenshotAreaClipboard,
             .screenshotFullClipboard, .screenshotToolbar:
            return "Screenshots"
        case .copy, .paste, .cut, .undo, .redo, .selectAll, .find,
             .emojiSymbols, .reloadPage, .newTab:
            return "Editing"
        case .volumeUp, .volumeDown, .mute, .playPause, .nextTrack, .prevTrack,
             .brightnessUp, .brightnessDown:
            return "Media & Display"
        case .missionControl, .appExpose, .showDesktop, .launchpad, .spotlight,
             .notificationCenter, .lockScreen, .sleep, .emptyTrash,
             .openFinder, .openDownloads:
            return "System"
        case .doNothing:
            return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .quitAppUnderCursor, .forceQuitAppUnderCursor, .quitFrontmostApp: return "xmark.app"
        case .hideAppUnderCursor, .hideOtherApps: return "eye.slash"
        case .openApp: return "square.grid.3x3"
        case .nextApp, .prevApp, .activateNextApp, .activatePrevApp: return "arrow.left.arrow.right"
        case .minimizeWindow: return "minus.square"
        case .minimizeAllApps, .restoreMinimizedApps: return "square.stack"
        case .maximizeWindow, .restoreWindow: return "arrow.up.left.and.arrow.down.right"
        case .closeWindow: return "xmark.circle"
        case .enterFullscreen, .exitFullscreen, .toggleFullscreen: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .cycleWindows: return "rectangle.on.rectangle"
        case .snapLeft: return "rectangle.lefthalf.inset.filled"
        case .snapRight: return "rectangle.righthalf.inset.filled"
        case .snapTopLeft: return "square.topleft.fill"
        case .snapTopRight: return "square.topright.fill"
        case .snapBottomLeft: return "square.bottomleft.fill"
        case .snapBottomRight: return "square.bottomright.fill"
        case .centerWindow: return "rectangle.center.inset.filled"
        case .moveToNextDisplay: return "display.2"
        case .screenshotArea, .screenshotAreaClipboard: return "viewfinder"
        case .screenshotFull, .screenshotFullClipboard: return "camera"
        case .screenshotToolbar: return "camera.aperture"
        case .copy: return "doc.on.doc"
        case .paste: return "clipboard"
        case .cut: return "scissors"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectAll: return "selection.pin.in.out"
        case .find: return "magnifyingglass"
        case .emojiSymbols: return "face.smiling"
        case .reloadPage: return "arrow.clockwise"
        case .newTab: return "plus.square"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .playPause: return "playpause"
        case .nextTrack: return "forward"
        case .prevTrack: return "backward"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .missionControl: return "rectangle.3.group"
        case .appExpose: return "rectangle.stack"
        case .showDesktop: return "desktopcomputer"
        case .launchpad: return "square.grid.3x3.fill"
        case .spotlight: return "magnifyingglass.circle"
        case .notificationCenter: return "bell"
        case .lockScreen: return "lock.display"
        case .sleep: return "moon"
        case .emptyTrash: return "trash"
        case .openFinder: return "folder"
        case .openDownloads: return "arrow.down.circle"
        case .doNothing: return "minus.circle"
        }
    }
}

// MARK: - Gesture Model

struct GestureRule: Identifiable, Codable {
    var id = UUID()
    var fingerCount: FingerCount = .three
    var gestureType: GestureType = .swipeUp
    var speed: SwipeSpeed = .normal
    var action: GestureAction = .doNothing
    var modifier: ModifierKey = .none
    var windowState: WindowState = .any
    var appFilter: String = ""
    var reciprocal: Bool = false
    var targetApp: String = ""
    var isEnabled: Bool = true
}

// MARK: - Store

class GestureStore: ObservableObject {
    static let shared = GestureStore()
    @Published var rules: [GestureRule] = GestureStore.defaultRules()

    static func defaultRules() -> [GestureRule] {
        [
            GestureRule(fingerCount: .three, gestureType: .swipeUp, speed: .normal, action: .missionControl),
            GestureRule(fingerCount: .three, gestureType: .swipeDown, speed: .normal, action: .appExpose),
            GestureRule(fingerCount: .three, gestureType: .swipeLeft, speed: .normal, action: .prevApp),
            GestureRule(fingerCount: .three, gestureType: .swipeRight, speed: .normal, action: .nextApp),
            GestureRule(fingerCount: .four, gestureType: .swipeUp, speed: .normal, action: .showDesktop),
            GestureRule(fingerCount: .four, gestureType: .swipeDown, speed: .normal, action: .launchpad),
            GestureRule(fingerCount: .four, gestureType: .click, speed: .normal, action: .spotlight),
            GestureRule(fingerCount: .three, gestureType: .swipeLeft, speed: .fast, action: .closeWindow),
            GestureRule(fingerCount: .three, gestureType: .swipeRight, speed: .fast, action: .maximizeWindow),
        ]
    }

    func addRule() {
        rules.append(GestureRule())
    }

    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    func move(from: IndexSet, to: Int) {
        rules.move(fromOffsets: from, toOffset: to)
    }
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    // General
    @Published var windowTargetingFocused: Bool = true
    @Published var hapticFeedback: Bool = true
    @Published var debugLogging: Bool = false
    @Published var launchAtLogin: Bool = false

    // Tuning — Recognition
    @Published var activationThreshold: Double = 12.0
    @Published var switcherStepDistance: Double = 40.0
    @Published var switcherDebounce: Double = 0.15

    // Tuning — Speed
    @Published var fastVelocityThreshold: Double = 1200.0
    @Published var slowVelocityThreshold: Double = 400.0
    @Published var speedSampleFrames: Int = 6

    // Tuning — Direction
    @Published var angleTolerance: Double = 45.0

    // Tuning — Pinch Veto
    @Published var candidateFrames: Int = 4
    @Published var pinchSpreadThreshold: Double = 0.06
    @Published var pinchFrameThreshold: Double = 0.03
    @Published var swipeCoherence: Double = 0.80

    // Edge Margins
    @Published var edgeMarginsEnabled: Bool = false
    @Published var marginLeft: Double = 5.0
    @Published var marginRight: Double = 5.0
    @Published var marginTop: Double = 5.0
    @Published var marginBottom: Double = 5.0
}

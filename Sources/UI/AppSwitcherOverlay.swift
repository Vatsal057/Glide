import Cocoa
import CoreGraphics
import SwiftUI

private enum GlideSwitcherPalette {
    static let touchLilac = Color(red: 201 / 255, green: 190 / 255, blue: 234 / 255)
    static let motionViolet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
}

/// Curvature and rim values, following the two rules macOS applies to Liquid Glass
/// surfaces (AltTab's App Icons style follows the same ones):
///
///   1. Nested shapes are concentric: an outer radius equals its inner radius plus
///      the padding between them, so every corner in the stack traces one curve.
///      A glass panel at 32pt around a 32pt plate reads as a mistake; the same
///      panel at 62pt reads as a single moulded object.
///   2. The plate behind an app icon uses the icon's own squircle proportion, so it
///      hugs the icon instead of cutting across it. AltTab lands at ~0.29 of the
///      plate height at every one of its sizes.
private enum GlideSwitcherMetrics {
    /// AltTab sizes an icon cell as `icon + edgeInsets * 2` and lets the selection
    /// plate fill that whole cell, which leaves the rim clear of the icon artwork.
    /// Getting this backwards — a plate smaller than the icon — buries the rim under
    /// the icon and its shadow.
       static let railIconSize: CGFloat = 128
    static let selectionWidth: CGFloat = 118
    static let selectionHeight: CGFloat = 117
    static let railCellWidth: CGFloat = 128
    static let railCellHeight: CGFloat = 117
    
    static let railCardSpacing: CGFloat = 4
    static let railCardStep = railCellWidth + railCardSpacing           // 132
    
    static let railPaddingHorizontal: CGFloat = 26
    static let railPaddingVertical: CGFloat = 28
    
    static let selectionRadius: CGFloat = 35
    static let railSlabRadius = selectionRadius + railPaddingVertical - 5

    static let cardInset: CGFloat = 10
    static let thumbnailTopRadius: CGFloat = 10
    static let thumbnailBottomRadius: CGFloat = 22
    static let cardTopRadius = thumbnailTopRadius + cardInset           // 20
    static let cardBottomRadius = thumbnailBottomRadius + cardInset     // 32
    static let shelfPadding: CGFloat = 20
    static let shelfSlabRadius = cardBottomRadius + shelfPadding        // 52

    static let selectionBorderWidth: CGFloat = 3
    static let selectionFillOpacity: CGFloat = 0.22

    static let iconShadowOpacity: CGFloat = 0.25
    static let iconShadowRadius: CGFloat = 6
    static let iconShadowOffsetY: CGFloat = 3

    static let railBlockHeight = railCellHeight + railPaddingVertical * 2 // 173

    /// Tallest the window shelf gets: three stacked cards plus its header and
    /// padding. Measured off the rendered view rather than derived, so round up.
    static let maxShelfHeight: CGFloat = 340

    /// Width of `n` rail cards including the gaps between them. Both the panel
    /// sizing in the controller and the selected-card centring in the view derive
    /// from this, so the two can't drift apart.
    static func railWidth(forVisibleCards n: Int) -> CGFloat {
        CGFloat(n) * railCellWidth + CGFloat(max(0, n - 1)) * railCardSpacing
    }

    /// The rail is centred in the panel and the shelf hangs below it, so the panel
    /// needs twice the shelf's height plus the rail. Screens shorter than that clamp,
    /// which would clip the bottom of the shelf; this is how far the rail has to move
    /// up to keep it whole. Depends only on panel height, so it is constant for a
    /// session and the rail never shifts under the user's fingers.
    ///
    /// `room` is the space below a centred rail. It is zero when no app in the session
    /// has multiple windows, because the panel then collapses to exactly the rail —
    /// there is no shelf to make space for, and no room to move into either. Clamping
    /// to `room` covers both that case and a screen too short to hold the full shelf.
    static func railCenterBias(panelHeight: CGFloat) -> CGFloat {
        let room = max(0, (panelHeight - railBlockHeight) / 2)
        return min(room, max(0, maxShelfHeight - room))
    }
}

private struct AppSwitcherWindowItem: Identifiable, Equatable {
    let id: Int
    let windowID: CGWindowID?
    let title: String
    let isMinimized: Bool
    let isOnCurrentSpace: Bool
    let isApplicationHidden: Bool

    var status: (label: String, symbol: String)? {
        if isMinimized { return ("Minimized", "minus.square.fill") }
        if isApplicationHidden { return ("Hidden", "eye.slash.fill") }
        if !isOnCurrentSpace { return ("Another Space", "square.grid.2x2.fill") }
        return nil
    }
}

private struct AppSwitcherItem: Identifiable {
    let id: pid_t
    let name: String
    /// Kept for the two places that draw the icon small: the shelf header and the
    /// placeholder behind a window with no thumbnail yet.
    let icon: NSImage
    /// The rail's artwork, already rasterized at the pixel size it will occupy.
    let railIcon: Image?
    let windows: [AppSwitcherWindowItem]
}

/// Pre-rasterizes the icon each rail card draws.
///
/// Handing SwiftUI an `NSImage` makes it choose a representation and resample on
/// every render pass, and a SwiftUI `.shadow` costs an offscreen blur pass per
/// card per pass. Neither depends on anything that changes while the panel is up,
/// yet both were being paid for every visible card every time the selection
/// stepped — with a spring animation running, that is once per display frame.
///
/// So both are paid once, here: the icon is drawn — shadow included — into a
/// bitmap sized for exactly the pixels it will cover, and the rail then only
/// blits it. `padding` is the room the blurred shadow needs; the artwork itself
/// stays `railIconSize`, so the cell reads exactly as it did before.
private enum SwitcherRailIcon {
    static let padding: CGFloat = 16
    static let canvasSide = GlideSwitcherMetrics.railIconSize + padding * 2

    static func render(_ icon: NSImage, scale: CGFloat) -> Image? {
        let pixels = Int((canvasSide * scale).rounded())
        guard pixels > 0, let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            // Native premultiplied BGRA: the layout the compositor wants, so the
            // bitmap reaches the screen without a format conversion.
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(GlideSwitcherMetrics.iconShadowOpacity)
        // A SwiftUI shadow radius is half the Core Graphics blur that matches it.
        shadow.shadowBlurRadius = GlideSwitcherMetrics.iconShadowRadius * 2
        // SwiftUI's positive shadow y points down, an NSShadow's points up.
        shadow.shadowOffset = NSSize(width: 0, height: -GlideSwitcherMetrics.iconShadowOffsetY)
        shadow.set()
        icon.draw(
            in: NSRect(
                x: padding,
                y: padding,
                width: GlideSwitcherMetrics.railIconSize,
                height: GlideSwitcherMetrics.railIconSize
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let bitmap = context.makeImage() else { return nil }
        return Image(decorative: bitmap, scale: scale)
    }
}

/// Window previews, kept apart from `AppSwitcherOverlayModel` on purpose.
///
/// Thumbnails used to live inside each window item, so one arriving preview
/// republished the whole `items` array and re-rendered every card in the app rail
/// — dozens of icons redrawn to show a picture in the shelf. Only
/// `TeardropWindowGrid` observes this, so an arriving preview now invalidates the
/// three cards that can display it and nothing else.
private final class SwitcherThumbnailStore: ObservableObject {
    @Published private(set) var images: [CGWindowID: NSImage] = [:]

    func merge(_ incoming: [CGWindowID: NSImage]) {
        guard !incoming.isEmpty else { return }
        var next = images
        var changed = false
        for (windowID, image) in incoming where next[windowID] !== image {
            next[windowID] = image
            changed = true
        }
        if changed { images = next }
    }

    func clear() {
        guard !images.isEmpty else { return }
        images = [:]
    }
}

private final class AppSwitcherOverlayModel: ObservableObject {
    @Published private(set) var items: [AppSwitcherItem] = []
    @Published private(set) var selectedAppIndex = 0
    @Published private(set) var selectedWindowIndex = 0

    /// Derived from the selection, and stored rather than computed. The rail reads
    /// each of these several times per render pass, and every read used to build a
    /// fresh array; they can only change when the selection or the item list does,
    /// so they are recomputed there instead. Deliberately not `@Published`: every
    /// assignment happens in the same call that publishes `items` or the selection,
    /// so SwiftUI already re-reads them.
    private(set) var visibleAppIndices: [Int] = []
    private(set) var visibleWindowIndices: [Int] = []
    private(set) var hiddenAppsBefore = 0
    private(set) var hiddenAppsAfter = 0
    private(set) var hiddenWindowsBefore = 0
    private(set) var hiddenWindowsAfter = 0

    private var visibleAppCapacity = 1

    var selectedApp: AppSwitcherItem? {
        items.indices.contains(selectedAppIndex) ? items[selectedAppIndex] : nil
    }

    var selectedWindow: AppSwitcherWindowItem? {
        guard let selectedApp, selectedApp.windows.indices.contains(selectedWindowIndex) else { return nil }
        return selectedApp.windows[selectedWindowIndex]
    }

    func configure(
        apps: [NSRunningApplication],
        windowsByApp: [[AppSwitcherWindow]],
        selectedAppIndex: Int,
        selectedWindowIndex: Int,
        visibleAppCapacity: Int,
        iconScale: CGFloat
    ) {
        items = apps.enumerated().map { index, app in
            let windows = windowsByApp.indices.contains(index) ? windowsByApp[index] : []
            let icon = app.icon
                ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
                ?? NSImage()
            return AppSwitcherItem(
                id: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "Application",
                icon: icon,
                railIcon: SwitcherRailIcon.render(icon, scale: iconScale),
                windows: windows.map { window in
                    AppSwitcherWindowItem(
                        id: window.id,
                        windowID: window.windowID,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        isOnCurrentSpace: window.isOnCurrentSpace,
                        isApplicationHidden: window.isApplicationHidden
                    )
                }
            )
        }

        self.selectedAppIndex = min(max(selectedAppIndex, 0), max(items.count - 1, 0))
        let windowCount = self.items.indices.contains(self.selectedAppIndex)
            ? self.items[self.selectedAppIndex].windows.count : 0
        self.selectedWindowIndex = min(max(selectedWindowIndex, 0), max(windowCount - 1, 0))
        self.visibleAppCapacity = max(1, visibleAppCapacity)
        recomputeVisibility()
    }

    func select(appIndex: Int, windowIndex: Int) {
        guard items.indices.contains(appIndex) else { return }
        let nextWindowIndex = min(max(windowIndex, 0), max(items[appIndex].windows.count - 1, 0))
        guard appIndex != selectedAppIndex || nextWindowIndex != selectedWindowIndex else { return }
        selectedAppIndex = appIndex
        selectedWindowIndex = nextWindowIndex
        recomputeVisibility()
    }

    func clear() {
        items = []
        selectedAppIndex = 0
        selectedWindowIndex = 0
        recomputeVisibility()
    }

    private func recomputeVisibility() {
        if items.isEmpty {
            visibleAppIndices = []
            hiddenAppsBefore = 0
            hiddenAppsAfter = 0
        } else {
            let count = min(max(1, visibleAppCapacity), items.count)
            let start = min(max(0, selectedAppIndex - count / 2), items.count - count)
            visibleAppIndices = Array(start..<(start + count))
            hiddenAppsBefore = start
            hiddenAppsAfter = max(0, items.count - (start + count))
        }

        let windows = items.indices.contains(selectedAppIndex) ? items[selectedAppIndex].windows : []
        if windows.isEmpty {
            visibleWindowIndices = []
            hiddenWindowsBefore = 0
            hiddenWindowsAfter = 0
        } else {
            let start = min(max(0, selectedWindowIndex), windows.count - 1)
            let count = min(3, windows.count - start)
            visibleWindowIndices = Array(start..<(start + count))
            hiddenWindowsBefore = start
            hiddenWindowsAfter = max(0, windows.count - (start + count))
        }
    }
}
/// macOS renders the Liquid Glass specular rim — the bright line that traces the
/// panel's edge and gives it depth — only for the *key* window. A panel that never
/// takes key gets a flat fill instead, which is what made the switcher read as a
/// plain dark slab next to the system's own glass surfaces. Borderless windows
/// refuse key by default, so it has to be opted into.
///
/// The style mask stays `.nonactivatingPanel`, so taking key does not activate
/// Glide: the frontmost app stays active and only loses key while the switcher is
/// up, exactly as it does under the system switcher. `ignoresMouseEvents` still
/// applies, so the panel remains click-through.
private final class AppSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppSwitcherOverlayController {
    static let shared = AppSwitcherOverlayController()

    /// How long the selection has to hold still before its window previews are
    /// captured. A capture is the most expensive thing the switcher does — a
    /// full-window composite out of the WindowServer plus a downscale — and while
    /// the fingers are moving the user is passing through apps, not looking at
    /// them. Comfortably longer than the step debounce, so a continuous swipe
    /// costs no captures at all; short enough to be invisible when they stop.
    private static let captureSettleDelay: TimeInterval = 0.16

    private let model = AppSwitcherOverlayModel()
    private let thumbnails = SwitcherThumbnailStore()
    private let backdrop = LiquidGlassBackdropView(frame: .zero)
    private var captureGeneration = UUID()
    private var captureTask: AppSwitcherPreviewCaptureTask?
    private var captureRequest: DispatchWorkItem?
    private var windowsByApp: [[AppSwitcherWindow]] = []
    /// Resolved once per open. The check is a cross-process question, and it was
    /// being asked again on every capture attempt.
    private var screenCaptureAllowed = false

    private lazy var panel: NSPanel = {
        let panel = AppSwitcherPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        // The glass slabs live in their own layer underneath the SwiftUI content, so the
        // container that fuses them can never lift glass on top of the icons and titles.
        let hosting = NSHostingView(
            rootView: AppSwitcherOverlayView(model: model, thumbnails: thumbnails, backdrop: backdrop)
        )
        panel.contentView = LiquidGlassPanelContentView(backdrop: backdrop, content: hosting)
        return panel
    }()

    private init() {}

    @discardableResult
    func show(
        apps: [NSRunningApplication],
        windowsByApp: [[AppSwitcherWindow]],
        selectedAppIndex: Int,
        selectedWindowIndex: Int
    ) -> Bool {
        guard !apps.isEmpty else { return false }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return false }

        captureRequest?.cancel()
        captureTask?.cancel()
        let generation = UUID()
        captureGeneration = generation
        self.windowsByApp = windowsByApp
        screenCaptureAllowed = CGPreflightScreenCaptureAccess()
        if !screenCaptureAllowed { AppSwitcherPreviewProvider.reset() }
        thumbnails.clear()

        let widthCapacity = max(3, Int((screen.frame.width - 240) / GlideSwitcherMetrics.railCardStep))
        let appCapacity = min(apps.count, widthCapacity)

        model.configure(
            apps: apps,
            windowsByApp: windowsByApp,
            selectedAppIndex: selectedAppIndex,
            selectedWindowIndex: selectedWindowIndex,
            visibleAppCapacity: appCapacity,
            iconScale: screen.backingScaleFactor
        )

        let visibleCount = min(appCapacity, apps.count)
        let cardsWidth = GlideSwitcherMetrics.railWidth(forVisibleCards: visibleCount)
        let overflowWidth: CGFloat = apps.count > visibleCount ? 84 : 0
        let panelWidth = min(screen.frame.width, max(520, cardsWidth + overflowWidth + 192))
        // Panel height only reserves layout room; each glass slab covers just its own
        // block, so leftover panel area costs nothing to render. The app rail is centred
        // on the panel, which means the window shelf hanging below it needs twice its own
        // height in panel space — hence the tall default. When no app in this session has
        // more than one window the shelf can never appear, so the rail is the entire
        // layout and the panel can collapse to it. Decided once per open, so the panel
        // never resizes mid-gesture.
        let mayShowWindowSection = windowsByApp.contains { $0.count > 1 }
        let withShelfHeight = GlideSwitcherMetrics.railBlockHeight + GlideSwitcherMetrics.maxShelfHeight * 2
        let panelHeight = min(
            screen.frame.height,
            mayShowWindowSection ? withShelfHeight : GlideSwitcherMetrics.railBlockHeight
        )
        let panelFrame = NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.midY - panelHeight / 2,
            width: panelWidth,
            height: panelHeight
        )
        panel.setFrame(panelFrame, display: true)
        // Vibrant appearance is what lets labels, secondary text and the low-opacity
        // fills blend with the glass behind them rather than sit flatly on top. Set per
        // show so the panel follows a theme change made while the app was running.
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        panel.appearance = NSAppearance(named: isDark ? .vibrantDark : .vibrantLight)
        // Resolve the SwiftUI layout now so the glass slabs are already positioned when
        // the panel first hits the screen, instead of a frame later.
        panel.contentView?.layoutSubtreeIfNeeded()
        // Key, not just ordered front: that is what earns the glass its specular rim.
        panel.makeKeyAndOrderFront(nil)
        SwitcherDiagnostics.startReporting()
        scheduleVisibleCapture(generation: generation, delay: 0)
        return true
    }

    func select(appIndex: Int, windowIndex: Int) {
        SwitcherDiagnostics.bump(.selectCalls)
        let previousAppIndex = model.selectedAppIndex
        let previousWindowIndex = model.selectedWindowIndex
        model.select(appIndex: appIndex, windowIndex: windowIndex)
        if model.selectedAppIndex != previousAppIndex || model.selectedWindowIndex != previousWindowIndex {
            SwitcherDiagnostics.bump(.selectChanged)
            scheduleVisibleCapture(generation: captureGeneration, delay: Self.captureSettleDelay)
        }
    }

    func hide() {
        SwitcherDiagnostics.stopReporting()
        captureRequest?.cancel()
        captureRequest = nil
        captureTask?.cancel()
        captureTask = nil
        captureGeneration = UUID()
        windowsByApp = []
        panel.orderOut(nil)
        model.clear()
        thumbnails.clear()
        backdrop.clear()
    }

    private func scheduleVisibleCapture(generation: UUID, delay: TimeInterval) {
        captureRequest?.cancel()
        captureTask?.cancel()

        let request = DispatchWorkItem { [weak self] in
            self?.captureVisibleWindows(generation: generation)
        }
        captureRequest = request
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: request)
    }

    private func captureVisibleWindows(generation: UUID) {
        captureTask = nil
        guard screenCaptureAllowed else { return }

        let appIndex = model.selectedAppIndex
        guard windowsByApp.indices.contains(appIndex) else { return }

        let appWindows = windowsByApp[appIndex]
        // The window shelf only appears for an app with more than one window, so a
        // capture for any other app produces an image nothing can ever display. The
        // switcher used to pay for one on every single-window app it stepped past.
        guard appWindows.count > 1 else { return }

        let visibleWindows = model.visibleWindowIndices.compactMap { index in
            appWindows.indices.contains(index) ? appWindows[index] : nil
        }
        guard !visibleWindows.isEmpty else { return }

        SwitcherDiagnostics.bump(.captureRounds)
        thumbnails.merge(AppSwitcherPreviewProvider.cachedImages(for: visibleWindows))
        captureTask = AppSwitcherPreviewProvider.capture(
            windows: visibleWindows,
            preferredID: model.selectedWindow?.id
        ) { [weak self] images in
            guard let self, self.captureGeneration == generation else { return }
            self.thumbnails.merge(images)
        }
    }
}

private extension VerticalAlignment {
    struct AppSwitcherRailCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            return d[VerticalAlignment.center]
        }
    }
    static let appSwitcherRailCenter = VerticalAlignment(AppSwitcherRailCenter.self)
}

private extension HorizontalAlignment {
    struct SelectedAppCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat {
            return d[HorizontalAlignment.center]
        }
    }
    static let selectedAppCenter = HorizontalAlignment(SelectedAppCenter.self)
}

private struct TeardropShape: Shape {
    var neckOffset: CGFloat = 0
    var neckWidth: CGFloat = 16
    var neckHeight: CGFloat = 20
    var cornerRadius: CGFloat = GlideSwitcherMetrics.shelfSlabRadius

    var animatableData: CGFloat {
        get { neckOffset }
        set { neckOffset = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX + neckOffset
        let topY = rect.minY
        let neckBottomY = rect.minY + neckHeight
        let bottomY = rect.maxY
        let leftX = rect.minX
        let rightX = rect.maxX
        
        let safeMidX = min(rightX - cornerRadius, max(leftX + cornerRadius, midX))
        
        path.move(to: CGPoint(x: safeMidX - neckWidth / 2, y: topY))
        
        path.addCurve(
            to: CGPoint(x: rightX, y: neckBottomY + cornerRadius),
            control1: CGPoint(x: min(rightX, max(leftX, safeMidX + neckWidth / 2)), y: topY + neckHeight * 0.4),
            control2: CGPoint(x: rightX, y: neckBottomY)
        )
        
        path.addLine(to: CGPoint(x: rightX, y: bottomY - cornerRadius))
        
        path.addArc(
            center: CGPoint(x: rightX - cornerRadius, y: bottomY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        path.addLine(to: CGPoint(x: leftX + cornerRadius, y: bottomY))
        
        path.addArc(
            center: CGPoint(x: leftX + cornerRadius, y: bottomY - cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        path.addLine(to: CGPoint(x: leftX, y: neckBottomY + cornerRadius))
        
        path.addCurve(
            to: CGPoint(x: safeMidX - neckWidth / 2, y: topY),
            control1: CGPoint(x: leftX, y: neckBottomY),
            control2: CGPoint(x: min(rightX, max(leftX, safeMidX - neckWidth / 2)), y: topY + neckHeight * 0.4)
        )
        
        path.closeSubpath()
        return path
    }
}

private struct AppSwitcherOverlayView: View {
    @ObservedObject var model: AppSwitcherOverlayModel
    /// Held, not observed. Subscribing here would put every arriving preview back
    /// on the critical path of the whole panel; `TeardropWindowGrid` observes it.
    let thumbnails: SwitcherThumbnailStore
    let backdrop: LiquidGlassBackdropView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// macOS 26 and later draw the switcher's surface with real Liquid Glass, placed
    /// behind this view by `backdrop`. Older systems keep the SwiftUI material and its
    /// metaball mask, so nothing about them changes.
    private let usesNativeGlass = LiquidGlass.isAvailable
    private static let panelSpace = "glideSwitcherPanel"

    var body: some View {
        let _ = SwitcherDiagnostics.bump(.bodyEvaluations)
        Group {
            if !model.items.isEmpty {
                GeometryReader { geo in
                    ZStack {
                        if !usesNativeGlass {
                            panelBackground
                                .frame(width: geo.size.width, height: geo.size.height)
                                .mask {
                                    Canvas { context, size in
                                        context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                                        context.addFilter(.blur(radius: 24))
                                        context.drawLayer { ctx in
                                            if let resolved = context.resolveSymbol(id: "layout") {
                                                ctx.draw(resolved, at: CGPoint(x: size.width / 2, y: size.height / 2))
                                            }
                                        }
                                    } symbols: {
                                        layoutStructure(isMask: true)
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .tag("layout")
                                    }
                                }
                        }

                        layoutStructure(isMask: false)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .coordinateSpace(name: Self.panelSpace)
                    .onPreferenceChange(GlassSlabPreferenceKey.self) { slabs in
                        backdrop.apply(glassSlabsInAppKitCoordinates(slabs, panelHeight: geo.size.height))
                    }
                }
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.4, dampingFraction: 0.7), value: model.selectedApp?.windows.count)
            }
        }
    }

    private var selectedAppOffset: CGFloat {
        let visible = model.visibleAppIndices
        let selIndex = model.selectedAppIndex
        guard let posInVisible = visible.firstIndex(of: selIndex) else { return 0 }
        
        let cardStep = GlideSwitcherMetrics.railCardStep
        let cardsTotalWidth = GlideSwitcherMetrics.railWidth(forVisibleCards: visible.count)
        let badgeLeftWidth: CGFloat = model.hiddenAppsBefore > 0 ? 46 : 0
        let badgeRightWidth: CGFloat = model.hiddenAppsAfter > 0 ? 46 : 0
        let railTotalWidth = cardsTotalWidth + badgeLeftWidth + badgeRightWidth

        let cardLeftInRail = badgeLeftWidth + CGFloat(posInVisible) * cardStep
        let cardCenterInRail = cardLeftInRail + GlideSwitcherMetrics.railCellWidth / 2
        let railCenter = railTotalWidth / 2.0
        
        return cardCenterInRail - railCenter
    }

    @ViewBuilder
    private func layoutStructure(isMask: Bool) -> some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .appSwitcherRailCenter)) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alignmentGuide(.appSwitcherRailCenter) { d in
                    d[VerticalAlignment.center]
                        - GlideSwitcherMetrics.railCenterBias(panelHeight: d.height)
                }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if isMask {
                        appRail.hidden()
                    } else {
                        appRail
                    }
                }
                .padding(.horizontal, GlideSwitcherMetrics.railPaddingHorizontal)
                .padding(.vertical, GlideSwitcherMetrics.railPaddingVertical)
                .background {
                    if isMask {
                        Color.black.clipShape(
                            RoundedRectangle(cornerRadius: GlideSwitcherMetrics.railSlabRadius, style: .continuous)
                        )
                    }
                }
                .glassSlab(
                    id: 0,
                    cornerRadius: GlideSwitcherMetrics.railSlabRadius,
                    in: Self.panelSpace,
                    enabled: usesNativeGlass && !isMask
                )
                .alignmentGuide(.appSwitcherRailCenter) { d in d[VerticalAlignment.center] }

                if (model.selectedApp?.windows.count ?? 0) > 1 {
                    Group {
                        if isMask {
                            windowSection.hidden()
                        } else {
                            windowSection
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, GlideSwitcherMetrics.shelfPadding)
                    .padding(.bottom, GlideSwitcherMetrics.shelfPadding)
                    .background {
                        if isMask {
                            Color.black.clipShape(TeardropShape(neckOffset: 0))
                        }
                    }
                    // Inside the offset, not outside it. `.offset` translates rendering
                    // without changing layout, and a `.background` attached after it
                    // composes outside the translation — so a slab reported there sits
                    // at the panel's centre while the shelf itself slides away from it.
                    .glassSlab(
                        id: 1,
                        cornerRadius: GlideSwitcherMetrics.shelfSlabRadius,
                        in: Self.panelSpace,
                        enabled: usesNativeGlass && !isMask
                    )
                    .offset(x: selectedAppOffset)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.4, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.6, anchor: .top))
                        )
                    )
                }
            }
        }
    }

    private var appRail: some View {
        HStack(spacing: GlideSwitcherMetrics.railCardSpacing) {
            appOverflowBadge(model.hiddenAppsBefore, symbol: "chevron.left")
            ForEach(model.visibleAppIndices, id: \.self) { index in
                AppRailCard(
                    item: model.items[index],
                    isSelected: index == model.selectedAppIndex,
                    reduceMotion: reduceMotion
                )
                .equatable()
            }
            appOverflowBadge(model.hiddenAppsAfter, symbol: "chevron.right")
        }
    }

    private var windowSection: some View {
        VStack(spacing: 12) {
            if let app = model.selectedApp {
                HStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                    Text(app.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 108)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(app.windows.count) \(app.windows.count == 1 ? "window" : "windows")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())

                TeardropWindowGrid(
                    windows: app.windows,
                    visibleIndices: model.visibleWindowIndices,
                    appIcon: app.icon,
                    selectedIndex: model.selectedWindowIndex,
                    reduceMotion: reduceMotion,
                    thumbnails: thumbnails
                )
            }
            windowOverflowSummary
        }
    }

    // footer removed to match native macOS UI
    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.thickMaterial)
        }
    }

    @ViewBuilder
    private func appOverflowBadge(_ count: Int, symbol: String) -> some View {
        if count > 0 {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                Text("+\(count)").monospacedDigit()
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 42)
            .accessibilityLabel("\(count) more applications")
        }
    }

    @ViewBuilder
    private var windowOverflowSummary: some View {
        let before = model.hiddenWindowsBefore
        let after = model.hiddenWindowsAfter
        if before > 0 || after > 0 {
            HStack(spacing: 10) {
                if before > 0 { Label("+\(before)", systemImage: "chevron.up") }
                if after > 0 { Label("+\(after)", systemImage: "chevron.down") }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    private func windowCountLabel(_ count: Int) -> String {
        count == 1 ? "1 window" : "\(count) windows"
    }
}

private struct AppRailCard: View, Equatable {
    let item: AppSwitcherItem
    let isSelected: Bool
    let reduceMotion: Bool

    /// Stepping the selection changes exactly two cards: the one losing it and the
    /// one gaining it. Without a way to prove that, SwiftUI has to re-evaluate
    /// every visible card's body on every step — a dozen or more — and a spring is
    /// running while it does. `AppSwitcherItem` cannot be `Equatable` (it carries
    /// an `NSImage` and an `Image`), so the comparison is spelled out over the
    /// fields this card actually draws. `id` is the process identifier, and the
    /// icons are derived from it and fixed for the session, so matching ids means
    /// matching artwork.
    static func == (lhs: AppRailCard, rhs: AppRailCard) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.item.id == rhs.item.id
            && lhs.item.name == rhs.item.name
            && lhs.item.windows.count == rhs.item.windows.count
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GlideSwitcherMetrics.selectionRadius, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.25) : Color.clear)
                .frame(width: GlideSwitcherMetrics.selectionWidth, height: GlideSwitcherMetrics.selectionHeight)

            if let railIcon = item.railIcon {
                // Already the right pixels, shadow included: drawn at 1:1 with no
                // resampling and no offscreen blur pass.
                railIcon
                    .frame(width: SwitcherRailIcon.canvasSide, height: SwitcherRailIcon.canvasSide)
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: GlideSwitcherMetrics.railIconSize, height: GlideSwitcherMetrics.railIconSize)
                    .shadow(
                        color: .black.opacity(GlideSwitcherMetrics.iconShadowOpacity),
                        radius: GlideSwitcherMetrics.iconShadowRadius,
                        y: GlideSwitcherMetrics.iconShadowOffsetY
                    )
            }
        }
        .frame(width: GlideSwitcherMetrics.railCellWidth, height: GlideSwitcherMetrics.railCellHeight)
        .overlay(alignment: .bottom) {
            if isSelected {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: GlideSwitcherMetrics.selectionWidth)
                    .offset(y: 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.windows.count > 1 {
                Text("\(item.windows.count)")
                    .font(.headline.bold().monospacedDigit())
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: Capsule())
                    .padding(3)
            }
        }
        .scaleEffect(isSelected ? 1.05 : 1)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.windows.count) windows")
        .accessibilityValue(isSelected ? "Selected application" : "")
    }
}
private struct TeardropWindowGrid: View {
    let windows: [AppSwitcherWindowItem]
    let visibleIndices: [Int]
    let appIcon: NSImage
    let selectedIndex: Int
    let reduceMotion: Bool
    /// The one place in the panel that reacts to an arriving preview.
    @ObservedObject var thumbnails: SwitcherThumbnailStore

    @ViewBuilder
    private func card(for index: Int) -> some View {
        if windows.indices.contains(index) {
            let offsetIndex = max(0, index - selectedIndex)
            WindowSelectionCard(
                item: windows[index],
                thumbnail: windows[index].windowID.flatMap { thumbnails.images[$0] },
                appIcon: appIcon,
                isSelected: index == selectedIndex,
                reduceMotion: reduceMotion
            )
            .equatable()
            .scaleEffect(x: 1.0 - CGFloat(offsetIndex) * 0.08, y: 1.0 - CGFloat(offsetIndex) * 0.04)
            .offset(y: CGFloat(offsetIndex * 50))
            .zIndex(Double(-index))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(visibleIndices, id: \.self) { i in
                card(for: i)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .move(edge: .bottom)).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .move(edge: .top)).combined(with: .opacity)
                    ))
            }
        }
        .padding(.bottom, CGFloat(max(0, visibleIndices.count - 1) * 50))
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: visibleIndices)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6), value: selectedIndex)
    }
}

private struct WindowSelectionCard: View, Equatable {
    let item: AppSwitcherWindowItem
    let thumbnail: NSImage?
    let appIcon: NSImage
    let isSelected: Bool
    let reduceMotion: Bool

    /// Same reasoning as `AppRailCard`: an arriving preview must not re-render the
    /// two cards it does not belong to. Images compare by identity — they are
    /// cached objects, never rebuilt in place.
    static func == (lhs: WindowSelectionCard, rhs: WindowSelectionCard) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.reduceMotion == rhs.reduceMotion
            && lhs.item == rhs.item
            && lhs.thumbnail === rhs.thumbnail
            && lhs.appIcon === rhs.appIcon
    }

    /// Concentric with the thumbnail inside it: each radius is the thumbnail's plus
    /// the card inset.
    private static let cardShape = UnevenRoundedRectangle(
        topLeadingRadius: GlideSwitcherMetrics.cardTopRadius,
        bottomLeadingRadius: GlideSwitcherMetrics.cardBottomRadius,
        bottomTrailingRadius: GlideSwitcherMetrics.cardBottomRadius,
        topTrailingRadius: GlideSwitcherMetrics.cardTopRadius,
        style: .continuous
    )

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.primary.opacity(0.045)
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .frame(width: 192, height: 108)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: GlideSwitcherMetrics.thumbnailTopRadius,
                    bottomLeadingRadius: GlideSwitcherMetrics.thumbnailBottomRadius,
                    bottomTrailingRadius: GlideSwitcherMetrics.thumbnailBottomRadius,
                    topTrailingRadius: GlideSwitcherMetrics.thumbnailTopRadius,
                    style: .continuous
                )
            )
            .overlay(alignment: .topTrailing) {
                if let status = item.status {
                    HStack(spacing: 3) {
                        Image(systemName: status.symbol)
                            .font(.system(size: 9, weight: .bold))
                        Text(status.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .padding(6)
                }
            }

            VStack(spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let status = item.status {
                    Label(status.label, systemImage: status.symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(GlideSwitcherMetrics.cardInset)
        .frame(width: 212)
        .background {
            Self.cardShape.fill(Color(nsColor: .windowBackgroundColor))
            Self.cardShape.fill(
                isSelected
                ? GlideSwitcherPalette.touchLilac.opacity(GlideSwitcherMetrics.selectionFillOpacity)
                : Color.primary.opacity(0.04)
            )
        }
        .overlay {
            // strokeBorder, so the rim sits inside the card edge and keeps the same
            // curve as the thumbnail corner one inset in.
            Self.cardShape.strokeBorder(
                isSelected
                ? AnyShapeStyle(GlideSwitcherPalette.motionViolet)
                : AnyShapeStyle(Color.primary.opacity(0.08)),
                lineWidth: isSelected ? GlideSwitcherMetrics.selectionBorderWidth : 1
            )
        }
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(isSelected ? "Selected window" : (item.status?.label ?? "Current Space"))
    }
}

private final class AppSwitcherPreviewCaptureTask {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private enum AppSwitcherPreviewProvider {
    private struct Target {
        let logicalID: Int
        let processIdentifier: pid_t
        let windowID: CGWindowID
    }

    private struct CacheEntry {
        let processIdentifier: pid_t
        let image: NSImage
        var lastAccess: TimeInterval
    }

    private static let captureQueue = DispatchQueue(
        label: "com.glide.app-switcher-previews",
        qos: .userInitiated
    )
    private static let cacheLock = NSLock()
    private static var cache: [CGWindowID: CacheEntry] = [:]
    private static let cacheLifetime: TimeInterval = 60
    /// A capture is expensive enough that the cache should outlive one pass over
    /// the running apps. At the old 18 it did not: browsing a dozen multi-window
    /// apps evicted the previews from the start of the rail before the user got
    /// back to them, so every sweep re-captured everything.
    private static let maximumCacheEntries = 60

    /// Callers gate on Screen Recording access once per switcher open and call
    /// `reset()` when it is missing, so neither of the hot paths below has to ask.
    static func reset() { clearCache() }

    static func cachedImages(for windows: [AppSwitcherWindow]) -> [CGWindowID: NSImage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        cache = cache.filter { _, entry in now - entry.lastAccess <= cacheLifetime }

        var images: [CGWindowID: NSImage] = [:]
        for window in windows {
            guard !window.isMinimized,
                  window.isOnCurrentSpace,
                  let windowID = window.windowID,
                  var entry = cache[windowID],
                  entry.processIdentifier == window.processIdentifier else { continue }
            entry.lastAccess = now
            cache[windowID] = entry
            images[windowID] = entry.image
        }
        cacheLock.unlock()
        return images
    }

    static func capture(
        windows: [AppSwitcherWindow],
        preferredID: Int?,
        completion: @escaping ([CGWindowID: NSImage]) -> Void
    ) -> AppSwitcherPreviewCaptureTask? {
        var targets = windows.compactMap { window -> Target? in
            guard !window.isMinimized,
                  window.isOnCurrentSpace,
                  let windowID = window.windowID else { return nil }
            return Target(
                logicalID: window.id,
                processIdentifier: window.processIdentifier,
                windowID: windowID
            )
        }
        if let preferredID, let index = targets.firstIndex(where: { $0.logicalID == preferredID }) {
            let preferred = targets.remove(at: index)
            targets.insert(preferred, at: 0)
        }
        guard !targets.isEmpty else { return nil }

        let task = AppSwitcherPreviewCaptureTask()
        captureQueue.async {
            var deferredImages: [CGWindowID: NSImage] = [:]
            for (index, target) in targets.enumerated() {
                guard !task.isCancelled else { return }
                if cachedImage(for: target) != nil { continue }

                guard let captured = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    target.windowID,
                    [.boundsIgnoreFraming, .nominalResolution]
                ) else { continue }
                guard !task.isCancelled else { return }
                guard let thumbnail = resized(captured, maximumDimension: 384) else { continue }
                guard !task.isCancelled else { return }
                SwitcherDiagnostics.bump(.windowsCaptured)

                let image = NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                )
                store(image, for: target)

                if index == 0 {
                    DispatchQueue.main.async {
                        guard !task.isCancelled else { return }
                        completion([target.windowID: image])
                    }
                } else {
                    deferredImages[target.windowID] = image
                }
            }

            if !deferredImages.isEmpty, !task.isCancelled {
                DispatchQueue.main.async {
                    guard !task.isCancelled else { return }
                    completion(deferredImages)
                }
            }
        }
        return task
    }

    private static func cachedImage(for target: Target) -> NSImage? {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard var entry = cache[target.windowID],
              entry.processIdentifier == target.processIdentifier,
              now - entry.lastAccess <= cacheLifetime else {
            cache.removeValue(forKey: target.windowID)
            return nil
        }
        entry.lastAccess = now
        cache[target.windowID] = entry
        return entry.image
    }

    private static func store(_ image: NSImage, for target: Target) {
        cacheLock.lock()
        cache[target.windowID] = CacheEntry(
            processIdentifier: target.processIdentifier,
            image: image,
            lastAccess: ProcessInfo.processInfo.systemUptime
        )
        while cache.count > maximumCacheEntries,
              let leastRecentID = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            cache.removeValue(forKey: leastRecentID)
        }
        cacheLock.unlock()
    }

    private static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    private static func resized(_ image: CGImage, maximumDimension: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maximumDimension else { return image }
        let scale = CGFloat(maximumDimension) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        // A window capture arrives as premultiplied BGRA in the display's colour
        // space. Asking for RGBA in device RGB — as this used to — made the
        // downscale a channel swizzle and a colour conversion as well as a
        // resample, on the largest image the switcher ever touches. Matching the
        // source on both counts leaves only the resample.
        let sourceSpace = image.colorSpace
        let space = (sourceSpace?.model == .rgb ? sourceSpace : nil)
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
import Cocoa
import CoreGraphics
import SwiftUI

private enum GlideSwitcherPalette {
    static let touchLilac = Color(red: 201 / 255, green: 190 / 255, blue: 234 / 255)
    static let motionViolet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
}

private struct AppSwitcherWindowItem: Identifiable {
    let id: Int
    let windowID: CGWindowID?
    let title: String
    let isMinimized: Bool
    let isOnCurrentSpace: Bool
    let isApplicationHidden: Bool
    var thumbnail: NSImage?

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
    let icon: NSImage
    var windows: [AppSwitcherWindowItem]
}

private final class AppSwitcherOverlayModel: ObservableObject {
    @Published private(set) var items: [AppSwitcherItem] = []
    @Published private(set) var selectedAppIndex = 0
    @Published private(set) var selectedWindowIndex = 0
    @Published private(set) var visibleAppCapacity = 1
    private var thumbnailLocations: [CGWindowID: (appIndex: Int, windowIndex: Int)] = [:]

    var selectedApp: AppSwitcherItem? {
        items.indices.contains(selectedAppIndex) ? items[selectedAppIndex] : nil
    }

    var selectedWindow: AppSwitcherWindowItem? {
        guard let selectedApp, selectedApp.windows.indices.contains(selectedWindowIndex) else { return nil }
        return selectedApp.windows[selectedWindowIndex]
    }

    var visibleAppIndices: [Int] {
        guard !items.isEmpty else { return [] }
        let count = min(visibleAppCapacity, items.count)
        let start = min(max(0, selectedAppIndex - count / 2), items.count - count)
        return Array(start..<(start + count))
    }
    var hiddenAppsBefore: Int { visibleAppIndices.first ?? 0 }
    var hiddenAppsAfter: Int {
        guard let last = visibleAppIndices.last else { return 0 }
        return max(0, items.count - last - 1)
    }

    var visibleWindowIndices: [Int] {
        guard let windows = selectedApp?.windows, !windows.isEmpty else { return [] }
        let start = selectedWindowIndex
        let count = min(3, windows.count - start)
        return Array(start..<(start + count))
    }

    var hiddenWindowsBefore: Int { visibleWindowIndices.first ?? 0 }
    var hiddenWindowsAfter: Int {
        guard let windows = selectedApp?.windows, let last = visibleWindowIndices.last else { return 0 }
        return max(0, windows.count - last - 1)
    }

    func configure(
        apps: [NSRunningApplication],
        windowsByApp: [[AppSwitcherWindow]],
        selectedAppIndex: Int,
        selectedWindowIndex: Int,
        visibleAppCapacity: Int,
        cachedThumbnails: [CGWindowID: NSImage]
    ) {
        items = apps.enumerated().map { index, app in
            let windows = windowsByApp.indices.contains(index) ? windowsByApp[index] : []
            return AppSwitcherItem(
                id: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "Application",
                icon: app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                windows: windows.map { window in
                    AppSwitcherWindowItem(
                        id: window.id,
                        windowID: window.windowID,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        isOnCurrentSpace: window.isOnCurrentSpace,
                        isApplicationHidden: window.isApplicationHidden,
                        thumbnail: window.windowID.flatMap { cachedThumbnails[$0] }
                    )
                }
            )
        }
        thumbnailLocations.removeAll(keepingCapacity: true)
        for appIndex in items.indices {
            for windowIndex in items[appIndex].windows.indices {
                if let windowID = items[appIndex].windows[windowIndex].windowID {
                    thumbnailLocations[windowID] = (appIndex, windowIndex)
                }
            }
        }

        self.selectedAppIndex = min(max(selectedAppIndex, 0), max(items.count - 1, 0))
        let windowCount = self.items.indices.contains(self.selectedAppIndex)
            ? self.items[self.selectedAppIndex].windows.count : 0
        self.selectedWindowIndex = min(max(selectedWindowIndex, 0), max(windowCount - 1, 0))
        self.visibleAppCapacity = max(1, visibleAppCapacity)
    }

    func select(appIndex: Int, windowIndex: Int) {
        guard items.indices.contains(appIndex) else { return }
        let nextWindowIndex = min(max(windowIndex, 0), max(items[appIndex].windows.count - 1, 0))
        if selectedAppIndex != appIndex { selectedAppIndex = appIndex }
        if selectedWindowIndex != nextWindowIndex { selectedWindowIndex = nextWindowIndex }
    }

    func updateThumbnails(_ images: [CGWindowID: NSImage]) {
        guard !images.isEmpty else { return }
        var updated = items
        var changed = false
        for (windowID, image) in images {
            guard let location = thumbnailLocations[windowID],
                  updated.indices.contains(location.appIndex),
                  updated[location.appIndex].windows.indices.contains(location.windowIndex) else { continue }
            updated[location.appIndex].windows[location.windowIndex].thumbnail = image
            changed = true
        }
        if changed { items = updated }
    }

    func clear() {
        items = []
        thumbnailLocations.removeAll(keepingCapacity: true)
        selectedAppIndex = 0
        selectedWindowIndex = 0
    }
}
final class AppSwitcherOverlayController {
    static let shared = AppSwitcherOverlayController()

    private let model = AppSwitcherOverlayModel()
    private var captureGeneration = UUID()
    private var captureTask: AppSwitcherPreviewCaptureTask?
    private var captureRequest: DispatchWorkItem?
    private var windowsByApp: [[AppSwitcherWindow]] = []

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
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
        panel.contentView = NSHostingView(rootView: AppSwitcherOverlayView(model: model))
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

        let itemWidth: CGFloat = 148
        let widthCapacity = max(3, Int((screen.frame.width - 240) / itemWidth))
        let appCapacity = min(apps.count, min(7, widthCapacity))

        model.configure(
            apps: apps,
            windowsByApp: windowsByApp,
            selectedAppIndex: selectedAppIndex,
            selectedWindowIndex: selectedWindowIndex,
            visibleAppCapacity: appCapacity,
            cachedThumbnails: [:]
        )

        let visibleCount = min(appCapacity, apps.count)
        let cardsWidth = CGFloat(visibleCount) * 128 + CGFloat(max(0, visibleCount - 1)) * 4
        let overflowWidth: CGFloat = apps.count > visibleCount ? 84 : 0
        let panelWidth = min(screen.frame.width, max(520, cardsWidth + overflowWidth + 192))
        let panelHeight = min(screen.frame.height, 900)
        let panelFrame = NSRect(
            x: screen.frame.midX - panelWidth / 2,
            y: screen.frame.midY - panelHeight / 2,
            width: panelWidth,
            height: panelHeight
        )
        panel.setFrame(panelFrame, display: true)
        panel.orderFrontRegardless()
        scheduleVisibleCapture(generation: generation, delay: 0)
        return true
    }

    func select(appIndex: Int, windowIndex: Int) {
        let previousAppIndex = model.selectedAppIndex
        let previousWindowIndex = model.selectedWindowIndex
        model.select(appIndex: appIndex, windowIndex: windowIndex)
        if model.selectedAppIndex != previousAppIndex || model.selectedWindowIndex != previousWindowIndex {
            scheduleVisibleCapture(generation: captureGeneration, delay: 0.04)
        }
    }

    func hide() {
        captureRequest?.cancel()
        captureRequest = nil
        captureTask?.cancel()
        captureTask = nil
        captureGeneration = UUID()
        windowsByApp = []
        panel.orderOut(nil)
        model.clear()
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
        let appIndex = model.selectedAppIndex
        guard windowsByApp.indices.contains(appIndex) else {
            captureTask = nil
            return
        }

        let appWindows = windowsByApp[appIndex]
        let visibleWindows = model.visibleWindowIndices.compactMap { index in
            appWindows.indices.contains(index) ? appWindows[index] : nil
        }
        guard !visibleWindows.isEmpty else {
            captureTask = nil
            return
        }

        model.updateThumbnails(AppSwitcherPreviewProvider.cachedImages(for: visibleWindows))
        captureTask = AppSwitcherPreviewProvider.capture(
            windows: visibleWindows,
            preferredID: model.selectedWindow?.id
        ) { [weak self] images in
            guard let self, self.captureGeneration == generation else { return }
            self.model.updateThumbnails(images)
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
    var cornerRadius: CGFloat = 28

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !model.items.isEmpty {
                GeometryReader { geo in
                    ZStack {
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

                        layoutStructure(isMask: false)
                            .frame(width: geo.size.width, height: geo.size.height)
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
        
        let cardStep: CGFloat = 132
        let cardsTotalWidth = CGFloat(visible.count) * 128 + CGFloat(max(0, visible.count - 1)) * 4
        let badgeLeftWidth: CGFloat = model.hiddenAppsBefore > 0 ? 46 : 0
        let badgeRightWidth: CGFloat = model.hiddenAppsAfter > 0 ? 46 : 0
        let railTotalWidth = cardsTotalWidth + badgeLeftWidth + badgeRightWidth
        
        let cardLeftInRail = badgeLeftWidth + CGFloat(posInVisible) * cardStep
        let cardCenterInRail = cardLeftInRail + 64
        let railCenter = railTotalWidth / 2.0
        
        return cardCenterInRail - railCenter
    }

    @ViewBuilder
    private func layoutStructure(isMask: Bool) -> some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .appSwitcherRailCenter)) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alignmentGuide(.appSwitcherRailCenter) { d in d[VerticalAlignment.center] }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    if isMask {
                        appRail.hidden()
                    } else {
                        appRail
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 28)
                .background {
                    if isMask {
                        Color.black.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }
                }
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .background {
                        if isMask {
                            Color.black.clipShape(TeardropShape(neckOffset: 0))
                        }
                    }
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
        HStack(spacing: 4) {
            appOverflowBadge(model.hiddenAppsBefore, symbol: "chevron.left")
            ForEach(model.visibleAppIndices, id: \.self) { index in
                AppRailCard(
                    item: model.items[index],
                    isSelected: index == model.selectedAppIndex,
                    reduceMotion: reduceMotion
                )
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
                    reduceMotion: reduceMotion
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

private struct AppRailCard: View {
    let item: AppSwitcherItem
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.60) : Color.clear)
                .frame(width: 118, height: 117)

            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .frame(width: 128, height: 117)
        .overlay(alignment: .bottom) {
            if isSelected {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 118)
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

    @ViewBuilder
    private func card(for index: Int) -> some View {
        if windows.indices.contains(index) {
            let offsetIndex = max(0, index - selectedIndex)
            WindowSelectionCard(
                item: windows[index],
                appIcon: appIcon,
                isSelected: index == selectedIndex,
                reduceMotion: reduceMotion
            )
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

private struct WindowSelectionCard: View {
    let item: AppSwitcherWindowItem
    let appIcon: NSImage
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let thumbnail = item.thumbnail {
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
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22,
                    topTrailingRadius: 10,
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
        .padding(10)
        .frame(width: 212)
        .background {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 14,
                style: .continuous
            )
            shape.fill(Color(nsColor: .windowBackgroundColor))
            shape.fill(isSelected ? GlideSwitcherPalette.touchLilac.opacity(0.22) : Color.primary.opacity(0.04))
        }
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 14,
                style: .continuous
            )
            .stroke(
                isSelected
                ? AnyShapeStyle(GlideSwitcherPalette.motionViolet)
                : AnyShapeStyle(Color.primary.opacity(0.08)),
                lineWidth: isSelected ? 2.5 : 1
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
    private static let maximumCacheEntries = 18

    static func cachedImages(for windows: [AppSwitcherWindow]) -> [CGWindowID: NSImage] {
        guard CGPreflightScreenCaptureAccess() else {
            clearCache()
            return [:]
        }

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
        guard CGPreflightScreenCaptureAccess() else {
            clearCache()
            completion([:])
            return nil
        }

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
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
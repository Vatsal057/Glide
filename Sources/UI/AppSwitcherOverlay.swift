import Cocoa
import CoreGraphics
import SwiftUI

private enum GlideSwitcherPalette {
    static let touchLilac = Color(red: 201 / 255, green: 190 / 255, blue: 234 / 255)
    static let motionViolet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
}

private struct AppSwitcherWindowItem: Identifiable {
    let id: Int
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
        let count = min(6, windows.count)
        let start = min(max(0, selectedWindowIndex - count / 2), windows.count - count)
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
        visibleAppCapacity: Int
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
                        title: window.title,
                        isMinimized: window.isMinimized,
                        isOnCurrentSpace: window.isOnCurrentSpace,
                        isApplicationHidden: window.isApplicationHidden,
                        thumbnail: nil
                    )
                }
            )
        }
        self.selectedAppIndex = min(max(selectedAppIndex, 0), max(items.count - 1, 0))
        let windowCount = self.items.indices.contains(self.selectedAppIndex)
            ? self.items[self.selectedAppIndex].windows.count : 0
        self.selectedWindowIndex = min(max(selectedWindowIndex, 0), max(windowCount - 1, 0))
        self.visibleAppCapacity = max(1, visibleAppCapacity)
    }

    func select(appIndex: Int, windowIndex: Int) {
        guard items.indices.contains(appIndex) else { return }
        selectedAppIndex = appIndex
        selectedWindowIndex = min(max(windowIndex, 0), max(items[appIndex].windows.count - 1, 0))
    }

    func updateThumbnails(_ images: [Int: NSImage]) {
        guard !images.isEmpty else { return }
        var updated = items
        for appIndex in updated.indices {
            for windowIndex in updated[appIndex].windows.indices {
                let id = updated[appIndex].windows[windowIndex].id
                updated[appIndex].windows[windowIndex].thumbnail = images[id]
                    ?? updated[appIndex].windows[windowIndex].thumbnail
            }
        }
        items = updated
    }

    func clear() {
        items = []
        selectedAppIndex = 0
        selectedWindowIndex = 0
    }
}
final class AppSwitcherOverlayController {
    static let shared = AppSwitcherOverlayController()

    private let model = AppSwitcherOverlayModel()
    private var captureGeneration = UUID()

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
        panel.hasShadow = true
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

        let itemWidth: CGFloat = 148
        let appCapacity = min(apps.count, max(3, Int((screen.frame.width - 240) / itemWidth)))
        
        model.configure(
            apps: apps,
            windowsByApp: windowsByApp,
            selectedAppIndex: selectedAppIndex,
            selectedWindowIndex: selectedWindowIndex,
            visibleAppCapacity: appCapacity
        )
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        let generation = UUID()
        captureGeneration = generation
        let preferredID = windowsByApp.indices.contains(selectedAppIndex)
            && windowsByApp[selectedAppIndex].indices.contains(selectedWindowIndex)
            ? windowsByApp[selectedAppIndex][selectedWindowIndex].id : nil
        AppSwitcherPreviewProvider.capture(
            windowsByApp: windowsByApp,
            preferredID: preferredID
        ) { [weak self] images in
            guard let self, self.captureGeneration == generation else { return }
            self.model.updateThumbnails(images)
        }
        return true
    }

    func select(appIndex: Int, windowIndex: Int) {
        model.select(appIndex: appIndex, windowIndex: windowIndex)
    }

    func hide() {
        captureGeneration = UUID()
        panel.orderOut(nil)
        model.clear()
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
private struct AppSwitcherOverlayView: View {
    @ObservedObject var model: AppSwitcherOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
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
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: model.selectedApp?.windows.count)
    }

    @ViewBuilder
    private func layoutStructure(isMask: Bool) -> some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .appSwitcherRailCenter)) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .alignmentGuide(.appSwitcherRailCenter) { d in d[VerticalAlignment.center] }

            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    if isMask {
                        appRail.hidden()
                        Text(model.selectedApp?.name ?? "").hidden()
                    } else {
                        appRail
                        Text(model.selectedApp?.name ?? "")
                            .font(.title.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background {
                    if isMask {
                        Color.black.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    }
                }
                .alignmentGuide(.appSwitcherRailCenter) { d in d[VerticalAlignment.center] }

                if (model.selectedApp?.windows.count ?? 0) > 1 {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(isMask ? Color.clear : Color.primary.opacity(0.2))
                            .frame(width: 4, height: 32)
                        
                        Group {
                            if isMask {
                                windowSection.hidden()
                            } else {
                                windowSection
                            }
                        }
                        .padding(20)
                        .background {
                            if isMask {
                                Color.black.clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }
        }
    }

    private var appRail: some View {
        HStack(spacing: 12) {
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
        VStack(spacing: 16) {
            if let app = model.selectedApp {
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
        VStack(spacing: 0) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .padding(14)
        .frame(width: 136, height: 136)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.15) : Color.clear)
        )
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
            WindowSelectionCard(
                item: windows[index],
                appIcon: appIcon,
                isSelected: index == selectedIndex,
                reduceMotion: reduceMotion
            )
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            if visibleIndices.count == 2 {
                HStack(spacing: 16) {
                    card(for: visibleIndices[0])
                    card(for: visibleIndices[1])
                }
            } else if visibleIndices.count == 3 {
                card(for: visibleIndices[0])
                HStack(spacing: 16) {
                    card(for: visibleIndices[1])
                    card(for: visibleIndices[2])
                }
            } else if visibleIndices.count == 4 {
                HStack(spacing: 16) {
                    card(for: visibleIndices[0])
                    card(for: visibleIndices[1])
                }
                HStack(spacing: 16) {
                    card(for: visibleIndices[2])
                    card(for: visibleIndices[3])
                }
            } else if visibleIndices.count == 5 {
                HStack(spacing: 16) {
                    card(for: visibleIndices[0])
                    card(for: visibleIndices[1])
                }
                HStack(spacing: 16) {
                    card(for: visibleIndices[2])
                    card(for: visibleIndices[3])
                    card(for: visibleIndices[4])
                }
            } else {
                let columns = Array(repeating: GridItem(.fixed(318), spacing: 16), count: 3)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleIndices, id: \.self) { i in
                        card(for: i)
                    }
                }
            }
        }
    }
}

private struct WindowSelectionCard: View {
    let item: AppSwitcherWindowItem
    let appIcon: NSImage
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
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
                            .frame(width: 72, height: 72)
                    }
                }
            }
            .frame(width: 294, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(spacing: 4) {
                Text(item.title)
                    .font(.title3.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let status = item.status {
                    Label(status.label, systemImage: status.symbol)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 318)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? GlideSwitcherPalette.touchLilac.opacity(0.18) : Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? GlideSwitcherPalette.motionViolet : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 3.75 : 1.5)
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(isSelected ? "Selected window" : (item.status?.label ?? "Current Space"))
    }
}

private enum AppSwitcherPreviewProvider {
    static func capture(
        windowsByApp: [[AppSwitcherWindow]],
        preferredID: Int?,
        completion: @escaping ([Int: NSImage]) -> Void
    ) {
        guard CGPreflightScreenCaptureAccess() else {
            completion([:])
            return
        }

        var targets = windowsByApp.flatMap { windows in
            windows.compactMap { window -> (id: Int, windowID: CGWindowID)? in
                guard !window.isMinimized, window.isOnCurrentSpace, let windowID = window.windowID else { return nil }
                return (window.id, windowID)
            }
        }
        if let preferredID, let index = targets.firstIndex(where: { $0.id == preferredID }) {
            let preferred = targets.remove(at: index)
            targets.insert(preferred, at: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var images: [Int: NSImage] = [:]
            for target in targets {
                guard let captured = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    target.windowID,
                    [.boundsIgnoreFraming, .bestResolution]
                ), let thumbnail = resized(captured, maximumDimension: 640) else { continue }
                images[target.id] = NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                )
            }
            DispatchQueue.main.async { completion(images) }
        }
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
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
        let count = min(3, windows.count)
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

        let width = min(720, max(440, screen.visibleFrame.width - 96))
        let height = min(408, max(340, screen.visibleFrame.height - 56))
        let appCapacity = min(apps.count, max(3, Int((width - 100) / 92)))
        model.configure(
            apps: apps,
            windowsByApp: windowsByApp,
            selectedAppIndex: selectedAppIndex,
            selectedWindowIndex: selectedWindowIndex,
            visibleAppCapacity: appCapacity
        )
        panel.setFrame(
            CGRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.midY - height / 2,
                width: width,
                height: height
            ),
            display: true
        )
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
private struct AppSwitcherOverlayView: View {
    @ObservedObject var model: AppSwitcherOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 10) {
            appRail
            Divider()
            windowSection
            footer
        }
        .padding(14)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var appRail: some View {
        HStack(spacing: 7) {
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
        .frame(maxWidth: .infinity, minHeight: 78)
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if let app = model.selectedApp {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(windowCountLabel(app.windows.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                windowOverflowSummary
            }

            if let app = model.selectedApp, !app.windows.isEmpty {
                ForEach(model.visibleWindowIndices, id: \.self) { index in
                    WindowSelectionRow(
                        item: app.windows[index],
                        appIcon: app.icon,
                        isSelected: index == model.selectedWindowIndex,
                        reduceMotion: reduceMotion
                    )
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No open windows")
                            .font(.subheadline.weight(.semibold))
                        Text("Release to activate the application.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Apps", systemImage: "arrow.left.and.right")
            if (model.selectedApp?.windows.count ?? 0) > 1 {
                Label("Windows", systemImage: "arrow.up.and.down")
            }
            Spacer()
            Text("Release to open \(model.selectedWindow?.title ?? model.selectedApp?.name ?? "application")")
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            shape.fill(.ultraThickMaterial)
        }
    }

    @ViewBuilder
    private func appOverflowBadge(_ count: Int, symbol: String) -> some View {
        if count > 0 {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                Text("+\(count)").monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28)
            .accessibilityLabel("\(count) more applications")
        }
    }

    @ViewBuilder
    private var windowOverflowSummary: some View {
        let before = model.hiddenWindowsBefore
        let after = model.hiddenWindowsAfter
        if before > 0 || after > 0 {
            HStack(spacing: 7) {
                if before > 0 { Label("+\(before)", systemImage: "chevron.up") }
                if after > 0 { Label("+\(after)", systemImage: "chevron.down") }
            }
            .font(.caption2.weight(.semibold))
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
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
            Text(item.name)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 72)
        }
        .padding(7)
        .frame(width: 82, height: 74)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? GlideSwitcherPalette.touchLilac.opacity(0.20) : Color.primary.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? GlideSwitcherPalette.motionViolet : Color.primary.opacity(0.09),
                        lineWidth: isSelected ? 3 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if item.windows.count > 1 {
                Text("\(item.windows.count)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(isSelected ? GlideSwitcherPalette.motionViolet : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: Capsule())
                    .padding(4)
            }
        }
        .scaleEffect(isSelected ? 1.03 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.windows.count) windows")
        .accessibilityValue(isSelected ? "Selected application" : "")
    }
}
private struct WindowSelectionRow: View {
    let item: AppSwitcherWindowItem
    let appIcon: NSImage
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.primary.opacity(0.045)
                        Image(nsImage: appIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 34, height: 34)
                    }
                }
            }
            .frame(width: 104, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.callout.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let status = item.status {
                    Label(status.label, systemImage: status.symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Current Space")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(GlideSwitcherPalette.motionViolet)
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? GlideSwitcherPalette.touchLilac.opacity(0.18) : Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? GlideSwitcherPalette.motionViolet : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2.5 : 1)
        }
        .scaleEffect(isSelected ? 1.008 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
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
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
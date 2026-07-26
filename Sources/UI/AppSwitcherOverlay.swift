import Cocoa
import CoreGraphics
import SwiftUI

private enum GlideSwitcherPalette {
    static let touchLilac = Color(red: 201 / 255, green: 190 / 255, blue: 234 / 255)
    static let motionViolet = Color(red: 148 / 255, green: 129 / 255, blue: 201 / 255)
}

private struct AppSwitcherItem: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let windowCount: Int
    let minimizedWindowCount: Int
    var thumbnail: NSImage?

    var accessibilityStatus: String {
        if windowCount == 0 { return "No open windows" }
        if minimizedWindowCount == windowCount {
            return windowCount == 1 ? "One minimized window" : "\(windowCount) minimized windows"
        }
        let windowLabel = windowCount == 1 ? "One window" : "\(windowCount) windows"
        guard minimizedWindowCount > 0 else { return windowLabel }
        return "\(windowLabel), \(minimizedWindowCount) minimized"
    }
}

private final class AppSwitcherOverlayModel: ObservableObject {
    @Published private(set) var items: [AppSwitcherItem] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var visibleCapacity = 1

    var selectedName: String {
        items.indices.contains(selectedIndex) ? items[selectedIndex].name : "app"
    }

    var visibleIndices: [Int] {
        guard !items.isEmpty else { return [] }
        let count = min(visibleCapacity, items.count)
        let start = min(max(0, selectedIndex - count / 2), items.count - count)
        return Array(start..<(start + count))
    }

    var hiddenBefore: Int { visibleIndices.first ?? 0 }
    var hiddenAfter: Int {
        guard let last = visibleIndices.last else { return 0 }
        return max(0, items.count - last - 1)
    }

    func configure(apps: [NSRunningApplication], selectedIndex: Int, visibleCapacity: Int) {
        items = apps.map { app in
            let summary = WindowTargeting.shared.windowSummary(for: app.processIdentifier)
            return AppSwitcherItem(
                id: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "Application",
                icon: app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage(),
                windowCount: summary.totalCount,
                minimizedWindowCount: summary.minimizedCount,
                thumbnail: nil
            )
        }
        self.selectedIndex = min(max(selectedIndex, 0), max(items.count - 1, 0))
        self.visibleCapacity = max(1, visibleCapacity)
    }
    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func updateThumbnails(_ images: [pid_t: NSImage]) {
        guard !images.isEmpty else { return }
        var updated = items
        for index in updated.indices {
            updated[index].thumbnail = images[updated[index].id] ?? updated[index].thumbnail
        }
        items = updated
    }

    func clear() {
        items = []
        selectedIndex = 0
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
    func show(apps: [NSRunningApplication], selectedIndex: Int) -> Bool {
        guard !apps.isEmpty else { return false }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return false }

        let horizontalMargin = min(72, max(36, screen.visibleFrame.width * 0.04))
        let availableWidth = max(320, screen.visibleFrame.width - horizontalMargin * 2)
        let capacity = min(apps.count, max(2, Int((availableWidth - 100) / 140)))
        let reservedOverflowWidth: CGFloat = apps.count > capacity ? 76 : 0
        let panelWidth = min(availableWidth, CGFloat(capacity) * 140 + 36 + reservedOverflowWidth)
        let panelSize = CGSize(width: panelWidth, height: 184)

        model.configure(apps: apps, selectedIndex: selectedIndex, visibleCapacity: capacity)
        panel.setFrame(
            CGRect(
                x: screen.visibleFrame.midX - panelSize.width / 2,
                y: screen.visibleFrame.midY - panelSize.height / 2,
                width: panelSize.width,
                height: panelSize.height
            ),
            display: true
        )
        panel.orderFrontRegardless()

        let generation = UUID()
        captureGeneration = generation
        let pids = apps.map(\.processIdentifier)
        let preferredPID = apps.indices.contains(selectedIndex) ? apps[selectedIndex].processIdentifier : nil
        AppSwitcherPreviewProvider.captureBestWindows(for: pids, preferredPID: preferredPID) { [weak self] images in
            guard let self, self.captureGeneration == generation else { return }
            self.model.updateThumbnails(images)
        }
        return true
    }

    func select(_ index: Int) {
        model.select(index)
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
            HStack(spacing: 8) {
                overflowBadge(model.hiddenBefore, direction: "chevron.left")

                ForEach(model.visibleIndices, id: \.self) { index in
                    AppSwitcherCard(
                        item: model.items[index],
                        isSelected: index == model.selectedIndex,
                        reduceMotion: reduceMotion
                    )
                }

                overflowBadge(model.hiddenAfter, direction: "chevron.right")
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(GlideSwitcherPalette.motionViolet)
                Text("Release to switch to \(model.selectedName)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Release to switch to \(model.selectedName)")
        }
        .padding(14)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    private func overflowBadge(_ count: Int, direction: String) -> some View {
        if count > 0 {
            VStack(spacing: 3) {
                Image(systemName: direction)
                Text("+\(count)")
                    .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30)
            .accessibilityLabel("\(count) more applications")
        }
    }
}

private struct AppSwitcherCard: View {
    let item: AppSwitcherItem
    let isSelected: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 7) {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 112, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(nsImage: item.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 22, height: 22)
                            .padding(5)
                    }
            } else {
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .padding(.vertical, 10)
            }

            Text(item.name)
                .font(.callout.weight(isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 112)
        }
        .padding(8)
        .frame(width: 128, height: 126)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? GlideSwitcherPalette.touchLilac.opacity(0.20) : Color.primary.opacity(0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? GlideSwitcherPalette.motionViolet : Color.primary.opacity(0.10),
                    lineWidth: isSelected ? 3 : 1
                )
        }
        .overlay(alignment: .topTrailing) {
            if item.windowCount > 1 || item.minimizedWindowCount > 0 {
                HStack(spacing: 3) {
                    if item.minimizedWindowCount == item.windowCount {
                        Image(systemName: "minus.square.fill")
                    }
                    if item.windowCount > 1 {
                        Text("\(item.windowCount)")
                            .monospacedDigit()
                    }
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? GlideSwitcherPalette.motionViolet : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: Capsule(style: .continuous))
                .padding(6)
            }
        }
        .scaleEffect(isSelected ? 1.035 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(isSelected ? "Selected, \(item.accessibilityStatus)" : item.accessibilityStatus)
    }
}
private enum AppSwitcherPreviewProvider {
    static func captureBestWindows(
        for pids: [pid_t],
        preferredPID: pid_t?,
        completion: @escaping ([pid_t: NSImage]) -> Void
    ) {
        guard CGPreflightScreenCaptureAccess() else {
            completion([:])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let requested = Set(pids)
            guard let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] else {
                DispatchQueue.main.async { completion([:]) }
                return
            }

            var bestByPID: [pid_t: (windowID: CGWindowID, area: CGFloat)] = [:]
            for window in windowInfo {
                guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
                      let windowNumber = window[kCGWindowNumber as String] as? NSNumber,
                      let layerNumber = window[kCGWindowLayer as String] as? NSNumber,
                      layerNumber.intValue == 0 else { continue }
                let pid = pid_t(pidNumber.int32Value)
                guard requested.contains(pid),
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                let area = (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
                guard area >= 12_000 else { continue }
                let windowID = CGWindowID(windowNumber.uint32Value)
                if area > (bestByPID[pid]?.area ?? 0) {
                    bestByPID[pid] = (windowID, area)
                }
            }

            var order = pids
            if let preferredPID, let index = order.firstIndex(of: preferredPID) {
                order.remove(at: index)
                order.insert(preferredPID, at: 0)
            }

            var images: [pid_t: NSImage] = [:]
            for pid in order {
                guard let target = bestByPID[pid],
                      let captured = CGWindowListCreateImage(
                        .null,
                        .optionIncludingWindow,
                        target.windowID,
                        [.boundsIgnoreFraming, .bestResolution]
                      ),
                      let thumbnail = resized(captured, maximumDimension: 640) else { continue }
                images[pid] = NSImage(
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
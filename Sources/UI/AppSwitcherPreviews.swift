import Cocoa
import CoreGraphics

/// Window previews for the switcher overlay: capture, downscale, and the cache
/// the overlay reads on every selection step. Kept apart from the views so the
/// capture rules can be exercised on their own.

final class AppSwitcherPreviewCaptureTask {
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

enum AppSwitcherPreviewProvider {
    private struct Target {
        let logicalID: Int
        let processIdentifier: pid_t
        let windowID: CGWindowID
        /// A window on another Space is captured from the last frame the
        /// WindowServer still holds for it, which changes what the result is worth
        /// keeping — see `isFresh`.
        let isOffSpace: Bool
    }

    private struct CacheEntry {
        let processIdentifier: pid_t
        let image: NSImage
        let capturedOffSpace: Bool
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

    /// Windows the WindowServer has no image for: never rendered, or its backing
    /// store already dropped. Asking again costs a full capture round trip and
    /// returns nothing every time, so each is asked once per switcher open — long
    /// enough to stop the repeats a single session would otherwise make, short
    /// enough that visiting the window's Space makes it eligible again.
    private static var unavailable: Set<CGWindowID> = []

    /// Callers gate on Screen Recording access once per switcher open and call
    /// `reset()` when it is missing, so neither of the hot paths below has to ask.
    static func reset() {
        cacheLock.lock()
        cache.removeAll()
        unavailable.removeAll()
        cacheLock.unlock()
    }

    /// Kept separate from `reset()` so a new session forgets which windows had no
    /// image without throwing away the previews it can still use.
    static func beginSession() {
        cacheLock.lock()
        unavailable.removeAll()
        cacheLock.unlock()
    }

    /// A capture of a window on another Space cannot go out of date: nothing redraws
    /// the window until its Space returns, and the return itself invalidates the
    /// entry, because `capturedOffSpace` no longer matches. So it is held for as
    /// long as the cache has room for it, while a live window's capture — which the
    /// window can contradict at any moment — still expires on the clock.
    private static func isFresh(
        _ entry: CacheEntry,
        offSpace: Bool,
        processIdentifier: pid_t,
        now: TimeInterval
    ) -> Bool {
        guard entry.processIdentifier == processIdentifier,
              entry.capturedOffSpace == offSpace else { return false }
        return offSpace || now - entry.lastAccess <= cacheLifetime
    }

    static func cachedImages(for windows: [AppSwitcherWindow]) -> [CGWindowID: NSImage] {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        cache = cache.filter { _, entry in
            entry.capturedOffSpace || now - entry.lastAccess <= cacheLifetime
        }

        var images: [CGWindowID: NSImage] = [:]
        for window in windows {
            guard !window.isMinimized,
                  let windowID = window.windowID,
                  var entry = cache[windowID],
                  isFresh(entry,
                          offSpace: !window.isOnCurrentSpace,
                          processIdentifier: window.processIdentifier,
                          now: now) else { continue }
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
        // A window on another Space is included: the WindowServer still holds the
        // last frame it drew, which is exactly what the user left there. Minimized
        // windows are not — nothing keeps an image for those.
        let skipped = unavailableWindowIDs()
        var targets = windows.compactMap { window -> Target? in
            guard !window.isMinimized,
                  let windowID = window.windowID,
                  !skipped.contains(windowID) else { return nil }
            return Target(
                logicalID: window.id,
                processIdentifier: window.processIdentifier,
                windowID: windowID,
                isOffSpace: !window.isOnCurrentSpace
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
                ) else {
                    markUnavailable(target.windowID)
                    continue
                }
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
              isFresh(entry,
                      offSpace: target.isOffSpace,
                      processIdentifier: target.processIdentifier,
                      now: now) else {
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
            capturedOffSpace: target.isOffSpace,
            lastAccess: ProcessInfo.processInfo.systemUptime
        )
        // Evicting the least recently used entry keeps the frozen off-Space
        // previews, which cost nothing to keep and would otherwise have to be
        // re-captured, ahead of live ones that are cheap to refresh.
        while cache.count > maximumCacheEntries,
              let leastRecentID = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            cache.removeValue(forKey: leastRecentID)
        }
        cacheLock.unlock()
    }

    private static func unavailableWindowIDs() -> Set<CGWindowID> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return unavailable
    }

    private static func markUnavailable(_ windowID: CGWindowID) {
        cacheLock.lock()
        unavailable.insert(windowID)
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

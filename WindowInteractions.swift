import Cocoa
import CoreGraphics

class WindowInteractions {
    
    static func getWindowUnderCursor() -> AXUIElement? {
        let mouseLocation = NSEvent.mouseLocation
        
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                        ?? NSScreen.main else { return nil }

        let cgY = screen.frame.maxY - mouseLocation.y
        let cgPoint = CGPoint(x: mouseLocation.x, y: cgY)

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for win in list {
            guard
                let b = win[kCGWindowBounds as String] as? [String: CGFloat],
                let pid = win[kCGWindowOwnerPID as String] as? pid_t,
                let layer = win[kCGWindowLayer as String] as? Int,
                pid != myPID,
                layer == 0
            else { continue }

            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                              width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard rect.contains(cgPoint) else { continue }
            
            // We found the visual window rect!
            let appElement = AXUIElementCreateApplication(pid)
            
            var windowsError: AXError = .success
            var windowsRef: CFTypeRef?
            windowsError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            
            if windowsError == .success, let windows = windowsRef as? [AXUIElement] {
                // Return the first window that matches this rect.
                for window in windows {
                    var positionRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    
                    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
                    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
                    
                    if let posValue = positionRef, let sizeValue = sizeRef {
                        var pos = CGPoint.zero
                        var size = CGSize.zero
                        // Need to cast to AXValue to decode but wait...
                        // Swift 5: AXValue is CFType
                        if CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                            let posAXValue = posValue as! AXValue
                            let sizeAXValue = sizeValue as! AXValue
                            
                            AXValueGetValue(posAXValue, .cgPoint, &pos)
                            AXValueGetValue(sizeAXValue, .cgSize, &size)
                            
                            let axRect = CGRect(origin: pos, size: size)
                            
                            // Margin of error for invisible borders (like shadows)
                            if abs(axRect.minX - rect.minX) < 20 && abs(axRect.minY - rect.minY) < 20 {
                                return window
                            }
                        }
                    }
                }
                
                // Fallback: If exact match failed, return the first main window of that app
                if let first = windows.first {
                    return first
                }
            }
        }
        return nil
    }

    static var previousFrames: [pid_t: CGRect] = [:]

    static func performZoomOnWindowUnderCursor(maximize: Bool) {
        guard let window = getWindowUnderCursor() else { return }
        
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        
        if maximize {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            
            if let posValue = posRef, let sizeValue = sizeRef,
               CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                
                let posAXValue = posValue as! AXValue
                let sizeAXValue = sizeValue as! AXValue
                
                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posAXValue, .cgPoint, &pos)
                AXValueGetValue(sizeAXValue, .cgSize, &size)
                
                // Save current frame
                previousFrames[pid] = CGRect(origin: pos, size: size)
            }
            
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
            
            let mainScreenH = NSScreen.screens[0].frame.height
            let newY = mainScreenH - screen.visibleFrame.maxY
            let newX = screen.visibleFrame.minX
            
            var newPos = CGPoint(x: newX, y: newY)
            var newSize = CGSize(width: screen.visibleFrame.width, height: screen.visibleFrame.height)
            
            if let newPosRef = AXValueCreate(.cgPoint, &newPos) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, newPosRef)
            }
            if let newSizeRef = AXValueCreate(.cgSize, &newSize) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, newSizeRef)
            }
        } else {
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
            let mainScreenH = NSScreen.screens[0].frame.height
            
            let frame: CGRect
            if let oldFrame = previousFrames[pid] {
                frame = oldFrame
                previousFrames.removeValue(forKey: pid) // Prevent memory leak by shedding old cache frames
            } else {
                // No saved frame — restore to 70% of screen centered
                let w = screen.visibleFrame.width * 0.7
                let h = screen.visibleFrame.height * 0.7
                let x = screen.visibleFrame.minX + (screen.visibleFrame.width - w) / 2
                let visibleY = screen.visibleFrame.minY + (screen.visibleFrame.height - h) / 2
                let cgY = mainScreenH - (visibleY + h)
                frame = CGRect(x: x, y: cgY, width: w, height: h)
            }
            
            var oldPos = frame.origin
            var oldSize = frame.size
            
            if let oldSizeRef = AXValueCreate(.cgSize, &oldSize) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, oldSizeRef)
            }
            if let oldPosRef = AXValueCreate(.cgPoint, &oldPos) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, oldPosRef)
            }
        }
    }

    static func setFullscreenWindowUnderCursor(enabled: Bool) {
        guard let window = getWindowUnderCursor() else { return }
        
        var isFullscreenRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &isFullscreenRef)
        
        let currentlyFullscreen = (err == .success && (isFullscreenRef as? Bool ?? false))
        
        if enabled && !currentlyFullscreen {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, true as CFTypeRef)
        } else if !enabled && currentlyFullscreen {
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, false as CFTypeRef)
        }
    }

    static func performMissionControl() {
        let src = CGEventSource(stateID: .hidSystemState)
        let f3: CGKeyCode = 160 // Mission Control hardware key
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: f3, keyDown: false)?.post(tap: .cghidEventTap)
    }

    static func minimizeWindowUnderCursor() -> pid_t? {
        guard let window = getWindowUnderCursor() else { return nil }
        
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        
        // Minimize the window
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
        
        // Find the next frontmost app that isn't the app we just minimized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let next = NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular &&
                $0.processIdentifier != pid &&
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            next?.activate(options: .activateIgnoringOtherApps)
        }
        return pid
    }
    
    static func restoreMinimizedApp(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        
        for window in windows {
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            if minimizedRef as? Bool == true {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication(processIdentifier: pid)?.activate(options: .activateIgnoringOtherApps)
        }
    }
    
    static func pruneCachedFrame(for pid: pid_t) {
        previousFrames.removeValue(forKey: pid) // Garbage collection from AppDelegate
    }
}

import Foundation

// ─────────────────────────────────────────────
// MARK: - MT types (mirrors private framework layout)
// ─────────────────────────────────────────────

struct MTPoint { var x: Float; var y: Float }

struct MTTouch {
    var frame:              Int32
    var timestamp:          Double
    var identifier:         Int32
    var state:              Int32
    var _u1:                Int32
    var _u2:                Int32
    var normalizedPosition: MTPoint
    var velocity:           MTPoint
    var angle:              Float
    var ellipseMajor:       Float
    var ellipseMinor:       Float
    var _u3:                MTPoint
    var _u4:                Float
    var _u5:                Int32
    var size:               Float
    var _u6:                Int32
    var pressure:           Float
    var _u7:                Float
    var _u8:                Int32
}

// Backward compatibility properties for the target app's GestureEngine
extension MTTouch {
    var normalizedX: Float { normalizedPosition.x }
    var normalizedY: Float { normalizedPosition.y }
    var velocityX: Float { velocity.x }
    var velocityY: Float { velocity.y }
}

typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

// ─────────────────────────────────────────────
// MARK: - MultitouchBridge
// ─────────────────────────────────────────────

/// Loads MultitouchSupport.framework via dlopen, enumerates ALL multitouch
/// devices, and forwards raw contact callbacks to the caller.
final class MultitouchBridge {

    static let shared = MultitouchBridge()
    private init() { loadSymbols() }

    private(set) var isRunning = false

    private var devices:    [UnsafeMutableRawPointer] = []
    private var deviceList: [AnyObject]               = []   // retains ARC refs to device objects
    private var currentCallback: MTContactCallback?
    private var handle: UnsafeMutableRawPointer?

    private var fnCreateList: (@convention(c) () -> CFArray)?
    private var fnRegister:   (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void)?
    private var fnUnregister: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void)?
    private var fnStart:      (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void)?
    private var fnStop:       (@convention(c) (UnsafeMutableRawPointer) -> Void)?

    // MARK: Load

    private func loadSymbols() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            NSLog("[MT] dlopen failed: %s", dlerror().map { String(cString: $0) } ?? "Unknown")
            return
        }
        handle = h
        func sym<T>(_ name: String) -> T? {
            dlsym(h, name).map { unsafeBitCast($0, to: T.self) }
        }
        fnCreateList  = sym("MTDeviceCreateList")
        fnRegister    = sym("MTRegisterContactFrameCallback")
        fnUnregister  = sym("MTUnregisterContactFrameCallback")
        fnStart       = sym("MTDeviceStart")
        fnStop        = sym("MTDeviceStop")

        if fnCreateList == nil || fnRegister == nil || fnStart == nil || fnStop == nil {
            NSLog("[MT] One or more symbols missing — multitouch may not work")
        } else {
            NSLog("[MT] Symbols resolved OK")
        }
    }

    // MARK: Start

    func start(callback: MTContactCallback) {
        guard !isRunning else { return }
        guard let createList = fnCreateList, let register = fnRegister, let startFn = fnStart else {
            NSLog("[MT] Cannot start — symbols missing"); return
        }

        let list = createList() as [AnyObject]
        deviceList = list
        devices = list.map { Unmanaged.passUnretained($0).toOpaque() }

        if devices.isEmpty {
            NSLog("[MT] No devices found — scheduling retry")
            retryStart(callback: callback, attempt: 1)
            return
        }

        currentCallback = callback
        for device in devices { register(device, callback); startFn(device, 0) }
        isRunning = true
        NSLog("[MT] Started — %d device(s)", devices.count)
    }

    private func retryStart(callback: MTContactCallback, attempt: Int) {
        guard attempt <= 5 else { NSLog("[MT] Gave up after %d retries", attempt - 1); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isRunning,
                  let createList = self.fnCreateList,
                  let register   = self.fnRegister,
                  let startFn    = self.fnStart else { return }

            let list = createList() as [AnyObject]
            self.deviceList = list
            self.devices = list.map { Unmanaged.passUnretained($0).toOpaque() }

            if self.devices.isEmpty {
                NSLog("[MT] Retry %d: still no devices", attempt)
                self.retryStart(callback: callback, attempt: attempt + 1)
                return
            }

            self.currentCallback = callback
            for device in self.devices { register(device, callback); startFn(device, 0) }
            self.isRunning = true
            NSLog("[MT] Started on retry %d — %d device(s)", attempt, self.devices.count)
        }
    }

    // MARK: Stop

    func stop() {
        guard isRunning, let stopFn = fnStop else { return }

        if let cb = currentCallback, let unregister = fnUnregister {
            for device in devices { unregister(device, cb) }
        }
        for device in devices { stopFn(device) }

        devices         = []
        deviceList      = []
        currentCallback = nil
        isRunning       = false
        NSLog("[MT] Stopped")
    }

    deinit {
        stop()
        if let h = handle { dlclose(h) }
    }
}

import Foundation

// ─────────────────────────────────────────────
// MARK: - MTTouch (mirrors private framework layout)
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

typealias MTContactCallback = @convention(c) (
    Int32,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

// ─────────────────────────────────────────────
// MARK: - MultitouchBridge
// ─────────────────────────────────────────────

/// Loads MultitouchSupport.framework via dlopen, enumerates ALL multitouch
/// devices (not just the default one), and forwards callbacks to the caller.
final class MultitouchBridge {

    static let shared = MultitouchBridge()
    private init() { loadSymbols() }

    private(set) var isRunning = false
    private var devices: [UnsafeMutableRawPointer] = []

    // FIX: Keep a strong ARC reference to the device list objects.
    // Previously, `list` was a local variable that went out of scope immediately
    // after start(), leaving `devices` holding raw unretained pointers.
    // The MT framework retains its own devices in practice, but this was
    // technically a dangling pointer waiting to happen on framework cleanup.
    private var deviceList: [AnyObject] = []

    private var handle: UnsafeMutableRawPointer?

    private var fnCreateList: (@convention(c) () -> CFArray)?
    private var fnRegister:   (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void)?
    private var fnStart:      (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void)?
    private var fnStop:       (@convention(c) (UnsafeMutableRawPointer) -> Void)?

    private var fnUnregister: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void)?

    // MARK: Load

    private func loadSymbols() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown error"
            print("[MT] dlopen failed: \(message)")
            return
        }
        handle = h

        func sym<T>(_ name: String) -> T? {
            guard let ptr = dlsym(h, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        fnCreateList  = sym("MTDeviceCreateList")
        fnRegister    = sym("MTRegisterContactFrameCallback")
        fnUnregister  = sym("MTUnregisterContactFrameCallback")
        fnStart       = sym("MTDeviceStart")
        fnStop        = sym("MTDeviceStop")

        if fnCreateList == nil || fnRegister == nil || fnStart == nil || fnStop == nil {
            print("[MT] One or more symbols could not be resolved — multitouch may not work")
        } else {
            AppLogger.debug("[MT] Symbols resolved OK")
        }
    }

    // MARK: Public

    /// The callback currently registered, stored so we can unregister it later.
    private var currentCallback: MTContactCallback?

    func start(callback: MTContactCallback) {
        guard !isRunning else { return }
        guard let createList = fnCreateList,
              let register   = fnRegister,
              let startFn    = fnStart else {
            print("[MT] Cannot start — symbols missing"); return
        }

        let list = createList() as [AnyObject]
        deviceList = list
        devices = list.map { Unmanaged.passUnretained($0).toOpaque() }

        if devices.isEmpty {
            print("[MT] No multitouch devices found — scheduling retry")
            retryStart(callback: callback, attempt: 1)
            return
        }

        currentCallback = callback
        for device in devices {
            register(device, callback)
            startFn(device, 0)
        }

        isRunning = true
        AppLogger.debug("[MT] Started — \(devices.count) device(s)")
    }

    /// Retry device enumeration after a delay (devices may not be available
    /// immediately after system wake).
    private func retryStart(callback: MTContactCallback, attempt: Int) {
        guard attempt <= 5 else {
            print("[MT] Gave up finding devices after \(attempt - 1) attempts")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.isRunning else { return }
            guard let createList = self.fnCreateList,
                  let register   = self.fnRegister,
                  let startFn    = self.fnStart else { return }

            let list = createList() as [AnyObject]
            self.deviceList = list
            self.devices = list.map { Unmanaged.passUnretained($0).toOpaque() }

            if self.devices.isEmpty {
                AppLogger.debug("[MT] Retry \(attempt): still no devices")
                self.retryStart(callback: callback, attempt: attempt + 1)
                return
            }

            self.currentCallback = callback
            for device in self.devices {
                register(device, callback)
                startFn(device, 0)
            }

            self.isRunning = true
            AppLogger.debug("[MT] Started on retry \(attempt) — \(self.devices.count) device(s)")
        }
    }

    func stop() {
        guard isRunning, let stopFn = fnStop else { return }

        // Unregister callback before stopping to prevent stale callback references
        if let cb = currentCallback, let unregister = fnUnregister {
            for device in devices { unregister(device, cb) }
        }

        for device in devices { stopFn(device) }
        devices         = []
        deviceList      = []   // release ARC references
        currentCallback = nil
        isRunning       = false
        AppLogger.debug("[MT] Stopped")
    }

    deinit {
        stop()
        if let h = handle { dlclose(h) }
    }
}

import Cocoa
import SwiftUI

// ─────────────────────────────────────────────────────────────
//  Native Liquid Glass backdrop for the app switcher
//
//  The switcher used to paint its own surface: a SwiftUI material rectangle
//  covering the whole panel, masked through a `Canvas` that ran an
//  alphaThreshold + 24pt blur metaball pass. That re-blurred the entire panel
//  (up to 900pt tall) on every rendered frame, and the result was an in-window
//  material that never matched the surfaces macOS draws around it.
//
//  Instead we hand the job to the WindowServer. Each block of the layout
//  reports its rect, and one `NSGlassEffectView` per block is placed behind the
//  SwiftUI content inside a single `NSGlassEffectContainerView`. The container
//  batches the slabs into one render pass and fuses the ones that sit close
//  together, which is the system's own version of the metaball blend — at no
//  per-frame cost to us.
// ─────────────────────────────────────────────────────────────

/// Runs `body` with implicit layer animations off, so moving/resizing a glass
/// slab tracks the SwiftUI layout in the same frame instead of easing after it.
private func withoutImplicitAnimations(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

/// Access to the glass "variant" the system switcher uses.
///
/// `NSGlassEffectView(style: .clear)` on its own renders close to fully
/// transparent, so a panel using it barely reads as a surface. Apple's own
/// Cmd-Tab switcher picks an internal variant that keeps the clear look while
/// staying legible. `set_variant:` is the private setter for it; when it is
/// unavailable we fall back to public `.regular` glass, which always works.
enum LiquidGlass {
    private static let setVariantSelector = NSSelectorFromString("set_variant:")
    private typealias SetVariant = @convention(c) (AnyObject, Selector, Int) -> Void
    /// The variant macOS uses for the Cmd-Tab panel.
    private static let commandTabVariant = 3

    /// True when `NSGlassEffectView` exists, i.e. the switcher can drop its
    /// hand-rolled material and let the WindowServer draw the surface.
    static let isAvailable: Bool = {
        if #available(macOS 26.0, *) { return true }
        return false
    }()

    static let supportsCommandTabVariant: Bool = {
        if #available(macOS 26.0, *) {
            return class_getInstanceMethod(object_getClass(NSGlassEffectView()), setVariantSelector) != nil
        }
        return false
    }()

    @available(macOS 26.0, *)
    static func applyCommandTabVariant(to view: NSGlassEffectView) {
        guard let method = class_getInstanceMethod(object_getClass(view), setVariantSelector) else { return }
        let setVariant = unsafeBitCast(method_getImplementation(method), to: SetVariant.self)
        setVariant(view, setVariantSelector, commandTabVariant)
    }
}

/// One glass surface: where it goes, in AppKit panel coordinates, and how round
/// its corners are.
struct GlassSlab: Equatable, Identifiable {
    let id: Int
    var frame: CGRect
    var cornerRadius: CGFloat
}

/// Holds the switcher's glass slabs. Lives behind the `NSHostingView` that draws
/// the icons and titles, so the container's z-order elevation can never lift the
/// glass on top of the content.
final class LiquidGlassBackdropView: NSView {
    /// How close two slabs must be before macOS fuses them. Generous enough that
    /// the app rail and the window shelf below it read as one blob of glass.
    private static let mergeSpacing: CGFloat = 24

    private var slabHost: NSView!
    private var glassContainer: NSView?
    private var slabViews: [Int: NSView] = [:]
    private var appliedSlabs: [GlassSlab] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: bounds)
            let host = NSView(frame: bounds)
            container.spacing = Self.mergeSpacing
            container.contentView = host
            addSubview(container)
            glassContainer = container
            slabHost = host
        } else {
            slabHost = self
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        glassContainer?.frame = bounds
        slabHost.frame = bounds
    }

    /// Applies the rects reported by the SwiftUI layout. Slab ids are stable, so
    /// a moving or resizing block reuses its glass view instead of tearing one
    /// down and building another.
    func apply(_ slabs: [GlassSlab]) {
        guard slabs != appliedSlabs else { return }
        appliedSlabs = slabs

        withoutImplicitAnimations {
            let liveIDs = Set(slabs.map(\.id))
            for (id, view) in slabViews where !liveIDs.contains(id) {
                view.removeFromSuperview()
                slabViews.removeValue(forKey: id)
            }
            for slab in slabs {
                let view = slabViews[slab.id] ?? makeSlabView(id: slab.id)
                view.frame = slab.frame
                if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
                    glass.cornerRadius = slab.cornerRadius
                }
            }
        }
    }

    func clear() {
        guard !slabViews.isEmpty else { return }
        appliedSlabs = []
        withoutImplicitAnimations {
            slabViews.values.forEach { $0.removeFromSuperview() }
            slabViews.removeAll()
        }
    }

    private func makeSlabView(id: Int) -> NSView {
        let view: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            if LiquidGlass.supportsCommandTabVariant {
                glass.style = .clear
                LiquidGlass.applyCommandTabVariant(to: glass)
            } else {
                glass.style = .regular
            }
            // Only `contentView` is a documented render target; an empty one
            // keeps the view on the supported path even though we embed nothing.
            glass.contentView = NSView()
            // Without clipping, the glass bleeds soft shadows past its corners.
            glass.wantsLayer = true
            glass.layer?.masksToBounds = true
            view = glass
        } else {
            view = NSView()
        }
        slabHost.addSubview(view)
        slabViews[id] = view
        return view
    }
}

// MARK: - Reporting layout rects from SwiftUI

/// Collects every block that wants glass behind it during one layout pass.
struct GlassSlabPreferenceKey: PreferenceKey {
    static let defaultValue: [GlassSlab] = []

    static func reduce(value: inout [GlassSlab], nextValue: () -> [GlassSlab]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marks this block as sitting on glass. The rect is measured in `space` and
    /// handed to `LiquidGlassBackdropView`, which puts a real glass slab behind it.
    ///
    /// `enabled` is false before macOS 26, where the switcher keeps its own
    /// material so nothing regresses on older systems.
    func glassSlab(
        id: Int,
        cornerRadius: CGFloat,
        in space: String,
        enabled: Bool
    ) -> some View {
        background {
            if enabled {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: GlassSlabPreferenceKey.self,
                        value: [GlassSlab(
                            id: id,
                            frame: proxy.frame(in: .named(space)),
                            cornerRadius: cornerRadius
                        )]
                    )
                }
            }
        }
    }
}

/// Converts SwiftUI rects (origin top-left, y down) into the AppKit panel
/// coordinates the backdrop lays out in (origin bottom-left, y up).
func glassSlabsInAppKitCoordinates(_ slabs: [GlassSlab], panelHeight: CGFloat) -> [GlassSlab] {
    slabs.map { slab in
        var flipped = slab
        flipped.frame.origin.y = panelHeight - slab.frame.maxY
        return flipped
    }
}

/// Panel content root: glass underneath, SwiftUI on top, both pinned to bounds.
final class LiquidGlassPanelContentView: NSView {
    private let backdrop: LiquidGlassBackdropView
    private let content: NSView

    init(backdrop: LiquidGlassBackdropView, content: NSView) {
        self.backdrop = backdrop
        self.content = content
        super.init(frame: .zero)
        addSubview(backdrop)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        content.frame = bounds
    }
}

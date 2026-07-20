/// Corner of the trackpad a force-click landed in. `.any` = position-blind (the
/// classic force-click). The corners gate a force-click rule to one region,
/// turning the trackpad into a macro pad.
///
/// Pure value type, no framework deps — kept in its own file so the geometry in
/// `at(cx:cy:margin:)` can be exercised by a standalone self-check.
enum TrackpadZone: String, Codable, CaseIterable {
    case any         = "Anywhere"
    case topLeft     = "Top-Left"
    case topRight    = "Top-Right"
    case bottomLeft  = "Bottom-Left"
    case bottomRight = "Bottom-Right"

    /// Which corner the normalized centroid falls in, or nil for the center.
    /// MT coords: x = 0 left → 1 right, y = 0 bottom → 1 top. `margin` is each
    /// corner's reach along both axes (0.35 → outer 35% on each side).
    static func at(cx: Float, cy: Float, margin: Float) -> TrackpadZone? {
        let left = cx < margin, right = cx > 1 - margin
        let bottom = cy < margin, top = cy > 1 - margin
        switch (left, right, top, bottom) {
        case (true, _, true, _):  return .topLeft
        case (_, true, true, _):  return .topRight
        case (true, _, _, true):  return .bottomLeft
        case (_, true, _, true):  return .bottomRight
        default:                  return nil
        }
    }

    init?(yamlValue: String?) {
        switch yamlValue?.lowercased() {
        case "top_left":     self = .topLeft
        case "top_right":    self = .topRight
        case "bottom_left":  self = .bottomLeft
        case "bottom_right": self = .bottomRight
        default:             return nil
        }
    }

    var yamlValue: String? {
        switch self {
        case .any:         return nil
        case .topLeft:     return "top_left"
        case .topRight:    return "top_right"
        case .bottomLeft:  return "bottom_left"
        case .bottomRight: return "bottom_right"
        }
    }
}

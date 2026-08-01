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
    case topEdge     = "Top Edge"
    case bottomEdge  = "Bottom Edge"
    case leftEdge    = "Left Edge"
    case rightEdge   = "Right Edge"

    /// Which corner the normalized centroid falls in, or nil for the center.
    /// MT coords: x = 0 left → 1 right, y = 0 bottom → 1 top. `margin` is each
    /// corner's reach along both axes (0.35 → outer 35% on each side).
    static func at(cx: Float, cy: Float, margin: EdgeMargin) -> TrackpadZone? {
        let left = cx < margin.left, right = cx > 1 - margin.right
        let bottom = cy < margin.bottom, top = cy > 1 - margin.top
        switch (left, right, top, bottom) {
        case (true, false, true, false):  return .topLeft
        case (false, true, true, false):  return .topRight
        case (true, false, false, true):  return .bottomLeft
        case (false, true, false, true):  return .bottomRight
        case (true, false, false, false): return .leftEdge
        case (false, true, false, false): return .rightEdge
        case (false, false, true, false): return .topEdge
        case (false, false, false, true): return .bottomEdge
        default:                          return nil
        }
    }

    /// Whether a normalized point falls inside this zone, where `reach` is the
    /// zone's depth along each axis. Same coordinate convention as
    /// `at(cx:cy:margin:)`. Unlike that method this answers a single zone, so a
    /// point in the top-left corner is inside `.topEdge` and `.leftEdge` too —
    /// which is what a zone the user picked deliberately should do.
    func contains(x: Float, y: Float, reach: Float) -> Bool {
        let left = x <= reach, right = x >= 1 - reach
        let bottom = y <= reach, top = y >= 1 - reach
        switch self {
        case .any:         return true
        case .topLeft:     return left && top
        case .topRight:    return right && top
        case .bottomLeft:  return left && bottom
        case .bottomRight: return right && bottom
        case .topEdge:     return top
        case .bottomEdge:  return bottom
        case .leftEdge:    return left
        case .rightEdge:   return right
        }
    }

    /// Zones offered as a TrackPoint anchor. Corners only: an edge strip spans
    /// half the trackpad and would swallow ordinary cursor work, and `.any`
    /// would swallow all of it.
    static let cornerCases: [TrackpadZone] = [.bottomRight, .bottomLeft, .topRight, .topLeft]

    init?(yamlValue: String?) {
        switch yamlValue?.lowercased() {
        case "top_left":     self = .topLeft
        case "top_right":    self = .topRight
        case "bottom_left":  self = .bottomLeft
        case "bottom_right": self = .bottomRight
        case "top_edge":     self = .topEdge
        case "bottom_edge":  self = .bottomEdge
        case "left_edge":    self = .leftEdge
        case "right_edge":   self = .rightEdge
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
        case .topEdge:     return "top_edge"
        case .bottomEdge:  return "bottom_edge"
        case .leftEdge:    return "left_edge"
        case .rightEdge:   return "right_edge"
        }
    }
}

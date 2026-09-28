import AppKit

/// Tab color marks (Otty's "Mark Tab").
enum MiaottyTabMark: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var title: String { rawValue.capitalized }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }
}

/// Extra per-tab appearance metadata (prefix, mark, divider) that Ghostty tabs
/// don't have. Keyed by window so it survives panel re-creation.
final class MiaottyTabMeta {
    var prefix: String?
    var mark: MiaottyTabMark?
    var dividerAfter: Bool = false
}

final class MiaottyTabMetaStore {
    static let shared = MiaottyTabMetaStore()
    private var map: [ObjectIdentifier: MiaottyTabMeta] = [:]

    private init() {}

    func meta(for window: NSWindow) -> MiaottyTabMeta {
        let key = ObjectIdentifier(window)
        if let existing = map[key] { return existing }
        let meta = MiaottyTabMeta()
        map[key] = meta
        return meta
    }

    func remove(window: NSWindow) {
        map.removeValue(forKey: ObjectIdentifier(window))
    }
}

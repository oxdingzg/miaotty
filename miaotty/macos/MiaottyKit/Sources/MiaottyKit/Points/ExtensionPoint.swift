import Foundation

/// The six extension points that let third parties and the miao integration
/// contribute to the terminal without touching the core.
public enum ExtensionPointKind: String, CaseIterable, Sendable {
    case detailsView
    case quickOpen
    case badge
    case action
    case context
    case terminalTool
}

/// A registered contribution. `handle` is invoked off the main thread by the
/// host; providers must be fast or hand work to their own queue.
public struct ExtensionProvider: Sendable {
    public let id: String
    public let point: ExtensionPointKind
    public let capabilities: [Capability]
    public let handle: @Sendable ([String: AnyCodable]) throws -> AnyCodable

    public init(
        id: String,
        point: ExtensionPointKind,
        capabilities: [Capability] = [],
        handle: @escaping @Sendable ([String: AnyCodable]) throws -> AnyCodable
    ) {
        self.id = id
        self.point = point
        self.capabilities = capabilities
        self.handle = handle
    }
}

/// Registry of extension providers. Register/unregister is cheap and may
/// happen at runtime (a plugin connecting or disconnecting).
public final class ExtensionRegistry {
    private let lock = NSLock()
    private var providers: [String: ExtensionProvider] = [:]

    public init() {}

    public func register(_ provider: ExtensionProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.id] = provider
    }

    public func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        providers[id] = nil
    }

    public func providers(for point: ExtensionPointKind) -> [ExtensionProvider] {
        lock.lock()
        defer { lock.unlock() }
        return providers.values.filter { $0.point == point }
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return providers.count
    }
}

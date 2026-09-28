import Foundation

/// Boundary to the terminal core (the Ghostty fork). The app implements this
/// over the C API added at the fork patch point `surface→child_pid`.
///
/// The scaffold defines the protocol only; `InMemoryPaneSource` stands in
/// until the core is wired up.
public protocol HostBridge: AnyObject {
    /// Child pid of the shell running in a pane, used for the
    /// `agent_pid → pane` fallback lookup (design: state plane).
    func surfaceChildPid(paneID: String) -> Int32?

    /// All live pane ids, in creation order.
    func paneIDs() -> [String]
}

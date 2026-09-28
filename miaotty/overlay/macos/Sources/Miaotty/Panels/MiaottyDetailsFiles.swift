import AppKit
import SwiftUI

struct MiaottyFileNode: Identifiable {
    let id: String
    let url: URL
    let name: String
    let isDirectory: Bool
}

enum MiaottyFiles {
    static func list(_ url: URL, showHidden: Bool) -> [MiaottyFileNode] {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHidden {
            options.insert(.skipsHiddenFiles)
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options) else {
            return []
        }

        var nodes: [MiaottyFileNode] = []
        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            nodes.append(MiaottyFileNode(
                id: item.path,
                url: item,
                name: item.lastPathComponent,
                isDirectory: isDirectory))
        }
        nodes.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return nodes
    }
}

struct MiaottyDetailsFiles: View {
    let cwd: String?

    @State private var rootURL: URL?
    @State private var nodes: [MiaottyFileNode] = []
    @State private var filter = ""
    @State private var showHidden = false
    @State private var refreshToken = 0

    init(cwd: String?) {
        self.cwd = cwd
        self._rootURL = State(initialValue: cwd.map { URL(fileURLWithPath: $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            tree
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
        .task(id: loadKey) { load() }
        .onChange(of: cwd) { newValue in
            rootURL = newValue.map { URL(fileURLWithPath: $0) }
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button {
                up()
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .help("Parent Folder")

            Button {
                refreshToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button {
                showHidden.toggle()
            } label: {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showHidden ? "Hide Dotfiles" : "Show Dotfiles")

            TextField("Find", text: $filter)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if filteredNodes.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(filteredNodes) { node in
                        MiaottyFileNodeRow(node: node, showHidden: showHidden, filter: filter)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var loadKey: String {
        "\(rootURL?.path ?? "")|\(showHidden)|\(refreshToken)"
    }

    private var canGoUp: Bool {
        guard let path = rootURL?.path else { return false }
        return path != "/" && !path.isEmpty
    }

    private var filteredNodes: [MiaottyFileNode] {
        guard !filter.isEmpty else { return nodes }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var emptyMessage: String {
        if rootURL == nil { return "No folder" }
        return filter.isEmpty ? "Empty" : "No matches"
    }

    private func up() {
        guard let current = rootURL else { return }
        rootURL = current.deletingLastPathComponent()
    }

    private func load() {
        guard let rootURL else {
            nodes = []
            return
        }
        let hidden = showHidden
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MiaottyFiles.list(rootURL, showHidden: hidden)
            DispatchQueue.main.async {
                self.nodes = result
            }
        }
    }
}

private struct MiaottyFileNodeRow: View {
    let node: MiaottyFileNode
    let showHidden: Bool
    let filter: String

    @State private var isExpanded = false
    @State private var children: [MiaottyFileNode]?

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(filteredChildren) { child in
                    MiaottyFileNodeRow(node: child, showHidden: showHidden, filter: filter)
                }
            } label: {
                rowLabel(icon: "folder")
            }
            .onChange(of: isExpanded) { expanded in
                if expanded && children == nil {
                    loadChildren()
                }
            }
        } else {
            rowLabel(icon: fileIcon)
        }
    }

    private var filteredChildren: [MiaottyFileNode] {
        let list = children ?? []
        guard !filter.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var fileIcon: String {
        switch node.url.pathExtension.lowercased() {
        case "txt", "md", "markdown", "swift", "js", "ts", "tsx", "jsx",
             "json", "yml", "yaml", "toml", "sh", "zsh", "py", "rb", "go",
             "rs", "c", "h", "cpp", "hpp", "html", "css", "xml", "sql":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private func rowLabel(icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 14)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func loadChildren() {
        let url = node.url
        let hidden = showHidden
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MiaottyFiles.list(url, showHidden: hidden)
            DispatchQueue.main.async {
                self.children = result
            }
        }
    }
}

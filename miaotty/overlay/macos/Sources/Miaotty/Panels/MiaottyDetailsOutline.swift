import AppKit
import SwiftUI

struct MiaottyDetailsOutline: View {
    let entries: [MiaottyHistoryEntry]

    init(entries: [MiaottyHistoryEntry]) {
        self.entries = entries
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No commands yet")
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            entryRows(index: index, entry: entry)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
    }

    @ViewBuilder
    private func entryRows(index: Int, entry: MiaottyHistoryEntry) -> some View {
        let showHeader = index == 0 || entries[index - 1].cwd != entry.cwd

        if showHeader {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(entry.cwd ?? "\u{2014}")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(Self.relativeTime(entry.date))
                    .font(.caption2)
            }
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(.top, index == 0 ? 0 : 8)
        }

        Text(entry.command)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = hours / 24
        return "\(days)d ago"
    }
}

import SwiftUI

struct GuidesSettingsView: View {
    @State private var selectedItemID: PlaceholderGuide.ID?

    private let placeholderGuides: [PlaceholderGuide] = [
        PlaceholderGuide(
            id: "codex-default",
            tool: .codex,
            title: "Default Codex Guide",
            summary: "Task 3 will add full guide editing and persistence for Codex prompt templates."
        ),
        PlaceholderGuide(
            id: "claude-default",
            tool: .claude,
            title: "Default Claude Guide",
            summary: "Task 3 will add full guide editing and persistence for Claude prompt templates."
        )
    ]

    private var selectedGuide: PlaceholderGuide? {
        guard let selectedItemID else {
            return nil
        }
        return placeholderGuides.first { $0.id == selectedItemID }
    }

    var body: some View {
        HSplitView {
            List(selection: $selectedItemID) {
                ForEach(Tool.allCases) { tool in
                    Section(tool.displayName) {
                        ForEach(placeholderGuides(for: tool)) { guide in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guide.title)
                                Text("Placeholder")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(guide.id)
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280)

            Group {
                if let selectedGuide {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedGuide.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(selectedGuide.summary)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView(
                        "Select a Guide",
                        systemImage: "book.closed",
                        description: Text("Guide CRUD will be implemented in Task 3.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedItemID == nil {
                selectedItemID = placeholderGuides.first?.id
            }
        }
    }

    private func placeholderGuides(for tool: Tool) -> [PlaceholderGuide] {
        placeholderGuides.filter { $0.tool == tool }
    }
}

private struct PlaceholderGuide: Identifiable, Hashable {
    typealias ID = String

    let id: ID
    let tool: Tool
    let title: String
    let summary: String
}

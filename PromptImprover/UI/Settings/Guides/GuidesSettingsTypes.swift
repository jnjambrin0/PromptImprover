import Foundation

struct GuidesErrorState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum PendingEditorTransition {
    case selectGuide(String?)
    case closeEditor
    case switchWorkspace(GuidesWorkspaceMode)
}

enum GuidesWorkspaceMode: String, CaseIterable, Identifiable {
    case editor
    case mapping

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .editor:
            return "Guides"
        case .mapping:
            return "Mapping"
        }
    }
}

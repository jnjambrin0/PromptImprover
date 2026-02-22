import SwiftUI

extension GuidesSettingsView {
    var outputModels: [OutputModel] {
        viewModel.outputModels
    }

    var guides: [GuideDoc] {
        viewModel.guides
    }

    var filteredGuides: [GuideDoc] {
        let query = guideSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return guides
        }

        return guides.filter { guide in
            guide.title.lowercased().contains(query)
                || guide.id.lowercased().contains(query)
                || guide.storagePath.lowercased().contains(query)
        }
    }

    var selectedOutputModel: OutputModel? {
        guard let selectedOutputSlug else {
            return nil
        }
        return viewModel.outputModel(forSlug: selectedOutputSlug)
    }

    var orderedGuidesForSelectedOutput: [GuideDoc] {
        guard let selectedOutputSlug else {
            return []
        }
        return viewModel.orderedGuides(forOutputSlug: selectedOutputSlug)
    }

    var unassignedGuidesForSelectedOutput: [GuideDoc] {
        guard let selectedOutputSlug else {
            return []
        }
        return viewModel.unassignedGuides(forOutputSlug: selectedOutputSlug)
    }

    var canAddOutputModel: Bool {
        OutputModel.normalizeDisplayName(addDisplayName) != nil
            && viewModel.normalizedOutputModelSlug(from: addSlug) != nil
    }

    var canSaveSelectedOutputModel: Bool {
        guard selectedOutputModel != nil else {
            return false
        }

        return OutputModel.normalizeDisplayName(editDisplayName) != nil
            && viewModel.normalizedOutputModelSlug(from: editSlug) != nil
    }

    var canAssignSelectedGuide: Bool {
        selectedOutputModel != nil && selectedUnassignedGuideID != nil
    }

    var canUnassignSelectedGuide: Bool {
        selectedOutputModel != nil && selectedMappedGuideID != nil
    }

    var canMoveSelectedGuideUp: Bool {
        guard
            let selectedMappedGuideID,
            let index = orderedGuidesForSelectedOutput.firstIndex(where: { $0.id.caseInsensitiveCompare(selectedMappedGuideID) == .orderedSame })
        else {
            return false
        }

        return index > 0
    }

    var canMoveSelectedGuideDown: Bool {
        guard
            let selectedMappedGuideID,
            let index = orderedGuidesForSelectedOutput.firstIndex(where: { $0.id.caseInsensitiveCompare(selectedMappedGuideID) == .orderedSame })
        else {
            return false
        }

        return index < orderedGuidesForSelectedOutput.count - 1
    }

    var canDeleteSelectedGuide: Bool {
        guard let selectedLibraryGuide = selectedLibraryGuide else {
            return false
        }

        return !selectedLibraryGuide.isBuiltIn
    }

    var selectedLibraryGuide: GuideDoc? {
        guard let selectedLibraryGuideID else {
            return nil
        }
        return guides.first { $0.id.caseInsensitiveCompare(selectedLibraryGuideID) == .orderedSame }
    }

    var librarySelectionBinding: Binding<String?> {
        Binding(
            get: { selectedLibraryGuideID },
            set: { proposed in
                requestLibrarySelection(proposed)
            }
        )
    }

    var workspaceSelectionBinding: Binding<GuidesWorkspaceMode> {
        Binding(
            get: { workspaceMode },
            set: { proposed in
                requestWorkspaceModeChange(proposed)
            }
        )
    }

    var editorGuide: GuideDoc? {
        guard let editorGuideID else {
            return nil
        }
        return guides.first { $0.id.caseInsensitiveCompare(editorGuideID) == .orderedSame }
    }

    var editorBinding: Binding<String> {
        if editorIsEditable {
            return $editorText
        }

        return Binding(
            get: { editorText },
            set: { _ in }
        )
    }

    var isEditorDirty: Bool {
        guard editorGuideID != nil else {
            return false
        }
        return editorText != savedEditorText
    }

    var canSaveEditorChanges: Bool {
        editorGuide != nil && editorIsEditable && isEditorDirty
    }

    var canDiscardEditorChanges: Bool {
        editorGuide != nil && isEditorDirty
    }

    var canStartForkEdit: Bool {
        guard let guide = editorGuide, guide.isBuiltIn else {
            return false
        }
        return !viewModel.guideHasFork(id: guide.id)
    }

    var canRevertToBuiltIn: Bool {
        guard let guide = editorGuide, guide.isBuiltIn else {
            return false
        }
        return viewModel.guideHasFork(id: guide.id)
    }

    var pendingTransitionMessage: String {
        guard let pendingEditorTransition else {
            return ""
        }

        switch pendingEditorTransition {
        case .selectGuide:
            return "You have unsaved changes. Discard them and switch guides?"
        case .closeEditor:
            return "You have unsaved changes. Discard them and close the editor?"
        case .switchWorkspace(let targetMode):
            return "You have unsaved changes. Discard them and switch to \(targetMode.displayName)?"
        }
    }
}

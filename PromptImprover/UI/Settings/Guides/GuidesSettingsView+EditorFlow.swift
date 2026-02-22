import Foundation

extension GuidesSettingsView {
    func syncSelectionAfterCatalogChange() {
        if let selectedOutputSlug,
           outputModels.contains(where: { $0.slug.caseInsensitiveCompare(selectedOutputSlug) == .orderedSame }) {
            syncEditorsFromSelectedOutput()
            return
        }

        if outputModels.contains(where: { $0.slug.caseInsensitiveCompare(viewModel.selectedTargetSlug) == .orderedSame }) {
            selectedOutputSlug = viewModel.selectedTargetSlug
        } else {
            selectedOutputSlug = outputModels.first?.slug
        }

        syncEditorsFromSelectedOutput()
    }

    func syncEditorsFromSelectedOutput() {
        guard let selectedOutputModel else {
            editDisplayName = ""
            editSlug = ""
            selectedMappedGuideID = nil
            selectedUnassignedGuideID = nil
            return
        }

        editDisplayName = selectedOutputModel.displayName
        editSlug = selectedOutputModel.slug

        if let selectedMappedGuideID,
           !orderedGuidesForSelectedOutput.contains(where: { $0.id.caseInsensitiveCompare(selectedMappedGuideID) == .orderedSame }) {
            self.selectedMappedGuideID = nil
        }

        if let selectedUnassignedGuideID,
           !unassignedGuidesForSelectedOutput.contains(where: { $0.id.caseInsensitiveCompare(selectedUnassignedGuideID) == .orderedSame }) {
            self.selectedUnassignedGuideID = nil
        }
    }

    func syncGuideSelectionAfterCatalogChange() {
        if let selectedLibraryGuideID,
           !guides.contains(where: { $0.id.caseInsensitiveCompare(selectedLibraryGuideID) == .orderedSame }) {
            self.selectedLibraryGuideID = nil
            clearEditorState()
            return
        }

        guard let selectedLibraryGuideID else {
            clearEditorState()
            return
        }

        if let editorGuideID,
           editorGuideID.caseInsensitiveCompare(selectedLibraryGuideID) == .orderedSame {
            if let selectedLibraryGuide {
                editorIsEditable = !selectedLibraryGuide.isBuiltIn || viewModel.guideHasFork(id: selectedLibraryGuide.id)
            }
            return
        }

        loadEditor(forGuideID: selectedLibraryGuideID)
    }

    func requestLibrarySelection(_ proposedGuideID: String?) {
        if matchesGuideID(selectedLibraryGuideID, proposedGuideID) == .some(true) {
            return
        }

        if isEditorDirty {
            pendingEditorTransition = .selectGuide(proposedGuideID)
            return
        }

        applyLibrarySelection(proposedGuideID)
    }

    func applyLibrarySelection(_ guideID: String?) {
        selectedLibraryGuideID = guideID
        loadEditor(forGuideID: guideID)
    }

    func requestWorkspaceModeChange(_ proposedMode: GuidesWorkspaceMode) {
        guard proposedMode != workspaceMode else {
            return
        }

        if workspaceMode == .editor && isEditorDirty {
            pendingEditorTransition = .switchWorkspace(proposedMode)
            return
        }

        applyWorkspaceMode(proposedMode)
    }

    func applyWorkspaceMode(_ mode: GuidesWorkspaceMode) {
        workspaceMode = mode
    }

    func loadEditor(forGuideID guideID: String?) {
        guard let guideID,
              let guide = guides.first(where: { $0.id.caseInsensitiveCompare(guideID) == .orderedSame }) else {
            clearEditorState()
            return
        }

        do {
            let loadedText = try viewModel.loadGuideText(id: guide.id)
            editorGuideID = guide.id
            editorText = loadedText
            savedEditorText = loadedText
            editorIsEditable = !guide.isBuiltIn || viewModel.guideHasFork(id: guide.id)
        } catch {
            clearEditorState()
            present(error)
        }
    }

    func beginEditingSelectedGuide() {
        guard let guide = editorGuide else {
            return
        }

        do {
            _ = try viewModel.beginGuideEdit(id: guide.id)
            loadEditor(forGuideID: guide.id)
        } catch {
            present(error)
        }
    }

    func saveEditorChanges() {
        guard let editorGuideID else {
            return
        }

        do {
            _ = try viewModel.saveGuideText(id: editorGuideID, text: editorText)
            loadEditor(forGuideID: editorGuideID)
        } catch {
            present(error)
        }
    }

    func discardEditorChanges() {
        guard editorGuide != nil else {
            return
        }
        editorText = savedEditorText
    }

    func requestRevertSelectedGuide() {
        guard let guide = editorGuide, guide.isBuiltIn, viewModel.guideHasFork(id: guide.id) else {
            return
        }
        pendingRevertGuide = guide
    }

    func confirmRevertSelectedGuide() {
        guard let guide = pendingRevertGuide else {
            return
        }

        do {
            let reverted = try viewModel.revertGuideToBuiltIn(id: guide.id)
            pendingRevertGuide = nil
            selectedLibraryGuideID = reverted.id
            loadEditor(forGuideID: reverted.id)
        } catch {
            present(error)
        }
    }

    func requestCloseEditor() {
        guard editorGuide != nil else {
            return
        }

        if isEditorDirty {
            pendingEditorTransition = .closeEditor
            return
        }

        applyLibrarySelection(nil)
    }

    func confirmPendingEditorTransition() {
        guard let pendingEditorTransition else {
            return
        }

        self.pendingEditorTransition = nil
        discardEditorChanges()

        switch pendingEditorTransition {
        case .selectGuide(let guideID):
            applyLibrarySelection(guideID)
        case .closeEditor:
            applyLibrarySelection(nil)
        case .switchWorkspace(let targetMode):
            applyWorkspaceMode(targetMode)
        }
    }

    func clearEditorState() {
        editorGuideID = nil
        editorText = ""
        savedEditorText = ""
        editorIsEditable = false
    }

    func matchesGuideID(_ lhs: String?, _ rhs: String?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default:
            return nil
        }
    }

    func present(_ error: Error) {
        activeError = GuidesErrorState(
            title: "Guides Error",
            message: error.localizedDescription
        )
    }
}

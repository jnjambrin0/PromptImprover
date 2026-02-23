import Foundation

extension GuidesSettingsView {
    func addOutputModel() {
        do {
            let added = try viewModel.addOutputModel(displayName: addDisplayName, slug: addSlug)
            addDisplayName = ""
            addSlug = ""
            selectedOutputSlug = added.slug
            selectedMappedGuideID = nil
            selectedUnassignedGuideID = nil
            syncEditorsFromSelectedOutput()
        } catch {
            present(error)
        }
    }

    func saveSelectedOutputModel() {
        guard let selectedOutputModel else {
            return
        }

        do {
            let updated = try viewModel.updateOutputModel(
                existingSlug: selectedOutputModel.slug,
                displayName: editDisplayName,
                slug: editSlug
            )
            selectedOutputSlug = updated.slug
            syncEditorsFromSelectedOutput()
        } catch {
            present(error)
        }
    }

    func requestDeleteSelectedOutputModel() {
        pendingOutputDeletion = selectedOutputModel
    }

    func confirmDeleteOutputModel() {
        guard let model = pendingOutputDeletion else {
            return
        }

        _ = viewModel.deleteOutputModel(slug: model.slug)
        pendingOutputDeletion = nil
        selectedMappedGuideID = nil
        selectedUnassignedGuideID = nil
        syncSelectionAfterCatalogChange()
    }

    func assignSelectedGuide() {
        guard let selectedOutputSlug, let selectedUnassignedGuideID else {
            return
        }

        do {
            try viewModel.assignGuide(selectedUnassignedGuideID, toOutputModel: selectedOutputSlug)
            selectedMappedGuideID = selectedUnassignedGuideID
            self.selectedUnassignedGuideID = nil
        } catch {
            present(error)
        }
    }

    func unassignSelectedGuide() {
        guard let selectedOutputSlug, let selectedMappedGuideID else {
            return
        }

        do {
            try viewModel.unassignGuide(selectedMappedGuideID, fromOutputModel: selectedOutputSlug)
            self.selectedMappedGuideID = nil
        } catch {
            present(error)
        }
    }

    func moveSelectedGuideUp() {
        guard let selectedOutputSlug, let selectedMappedGuideID else {
            return
        }

        do {
            try viewModel.moveGuideUp(selectedMappedGuideID, inOutputModel: selectedOutputSlug)
        } catch {
            present(error)
        }
    }

    func moveSelectedGuideDown() {
        guard let selectedOutputSlug, let selectedMappedGuideID else {
            return
        }

        do {
            try viewModel.moveGuideDown(selectedMappedGuideID, inOutputModel: selectedOutputSlug)
        } catch {
            present(error)
        }
    }

    func openSelectedMappedGuideInEditor() {
        guard let selectedMappedGuideID else {
            return
        }

        applyWorkspaceMode(.editor)
        requestLibrarySelection(selectedMappedGuideID)
    }

    func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else {
                return
            }

            do {
                let imported = try viewModel.importGuide(from: sourceURL)
                applyWorkspaceMode(.editor)
                requestLibrarySelection(imported.id)

                if let selectedOutputSlug,
                   viewModel.unassignedGuides(forOutputSlug: selectedOutputSlug).contains(where: { $0.id.caseInsensitiveCompare(imported.id) == .orderedSame }) {
                    selectedUnassignedGuideID = imported.id
                }
            } catch {
                present(error)
            }

        case .failure(let error):
            present(error)
        }
    }

    func requestDeleteSelectedGuide() {
        guard let selectedLibraryGuide, !selectedLibraryGuide.isBuiltIn else {
            return
        }
        pendingGuideDeletion = selectedLibraryGuide
    }

    func confirmDeleteGuide() {
        guard let guide = pendingGuideDeletion else {
            return
        }

        do {
            try viewModel.deleteGuide(id: guide.id)
            pendingGuideDeletion = nil

            if matchesGuideID(selectedLibraryGuideID, guide.id) == .some(true) {
                selectedLibraryGuideID = nil
                clearEditorState()
            }

            selectedMappedGuideID = nil
            if matchesGuideID(selectedUnassignedGuideID, guide.id) == .some(true) {
                selectedUnassignedGuideID = nil
            }
        } catch {
            present(error)
        }
    }
}

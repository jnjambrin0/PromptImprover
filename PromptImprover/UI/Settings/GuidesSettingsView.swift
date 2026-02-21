import SwiftUI
import UniformTypeIdentifiers

struct GuidesSettingsView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    @State private var selectedOutputSlug: String?
    @State private var selectedMappedGuideID: String?
    @State private var selectedLibraryGuideID: String?

    @State private var addDisplayName: String = ""
    @State private var addSlug: String = ""
    @State private var editDisplayName: String = ""
    @State private var editSlug: String = ""

    @State private var selectedUnassignedGuideID: String?
    @State private var isImportingGuide: Bool = false

    @State private var pendingOutputDeletion: OutputModel?
    @State private var pendingGuideDeletion: GuideDoc?
    @State private var activeError: GuidesErrorState?

    private var outputModels: [OutputModel] {
        viewModel.outputModels
    }

    private var guides: [GuideDoc] {
        viewModel.guides
    }

    private var selectedOutputModel: OutputModel? {
        guard let selectedOutputSlug else {
            return nil
        }
        return viewModel.outputModel(forSlug: selectedOutputSlug)
    }

    private var orderedGuidesForSelectedOutput: [GuideDoc] {
        guard let selectedOutputSlug else {
            return []
        }
        return viewModel.orderedGuides(forOutputSlug: selectedOutputSlug)
    }

    private var unassignedGuidesForSelectedOutput: [GuideDoc] {
        guard let selectedOutputSlug else {
            return []
        }
        return viewModel.unassignedGuides(forOutputSlug: selectedOutputSlug)
    }

    private var canAddOutputModel: Bool {
        OutputModel.normalizeDisplayName(addDisplayName) != nil
            && viewModel.normalizedOutputModelSlug(from: addSlug) != nil
    }

    private var canSaveSelectedOutputModel: Bool {
        guard selectedOutputModel != nil else {
            return false
        }

        return OutputModel.normalizeDisplayName(editDisplayName) != nil
            && viewModel.normalizedOutputModelSlug(from: editSlug) != nil
    }

    private var canAssignSelectedGuide: Bool {
        selectedOutputModel != nil && selectedUnassignedGuideID != nil
    }

    private var canUnassignSelectedGuide: Bool {
        selectedOutputModel != nil && selectedMappedGuideID != nil
    }

    private var canMoveSelectedGuideUp: Bool {
        guard
            let selectedMappedGuideID,
            let index = orderedGuidesForSelectedOutput.firstIndex(where: { $0.id.caseInsensitiveCompare(selectedMappedGuideID) == .orderedSame })
        else {
            return false
        }

        return index > 0
    }

    private var canMoveSelectedGuideDown: Bool {
        guard
            let selectedMappedGuideID,
            let index = orderedGuidesForSelectedOutput.firstIndex(where: { $0.id.caseInsensitiveCompare(selectedMappedGuideID) == .orderedSame })
        else {
            return false
        }

        return index < orderedGuidesForSelectedOutput.count - 1
    }

    private var canDeleteSelectedGuide: Bool {
        guard let selectedLibraryGuide = selectedLibraryGuide else {
            return false
        }

        return !selectedLibraryGuide.isBuiltIn
    }

    private var selectedLibraryGuide: GuideDoc? {
        guard let selectedLibraryGuideID else {
            return nil
        }
        return guides.first { $0.id.caseInsensitiveCompare(selectedLibraryGuideID) == .orderedSame }
    }

    var body: some View {
        HSplitView {
            outputModelsPane
                .frame(minWidth: 300, idealWidth: 320)

            VStack(alignment: .leading, spacing: 16) {
                mappingPane
                guideLibraryPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            syncSelectionAfterCatalogChange()
        }
        .onChange(of: outputModels) { _, _ in
            syncSelectionAfterCatalogChange()
        }
        .onChange(of: selectedOutputSlug) { _, _ in
            syncEditorsFromSelectedOutput()
        }
        .fileImporter(
            isPresented: $isImportingGuide,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .confirmationDialog("Delete Output Model?", isPresented: Binding(
            get: { pendingOutputDeletion != nil },
            set: { show in
                if !show {
                    pendingOutputDeletion = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                confirmDeleteOutputModel()
            }
            Button("Cancel", role: .cancel) {
                pendingOutputDeletion = nil
            }
        } message: {
            if let pendingOutputDeletion {
                Text("Delete \"\(pendingOutputDeletion.displayName)\" and remove its guide mapping assignments?")
            }
        }
        .confirmationDialog("Delete Guide?", isPresented: Binding(
            get: { pendingGuideDeletion != nil },
            set: { show in
                if !show {
                    pendingGuideDeletion = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                confirmDeleteGuide()
            }
            Button("Cancel", role: .cancel) {
                pendingGuideDeletion = nil
            }
        } message: {
            if let pendingGuideDeletion {
                Text("Delete \"\(pendingGuideDeletion.title)\" and unassign it from all output models?")
            }
        }
        .alert(item: $activeError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var outputModelsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Output Models") {
                VStack(alignment: .leading, spacing: 10) {
                    List(outputModels, selection: $selectedOutputSlug) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            Text(model.slug)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.slug)
                    }
                    .frame(minHeight: 200)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("New display name", text: $addDisplayName)
                            .textFieldStyle(.roundedBorder)
                        TextField("New slug (e.g. gpt-5-2)", text: $addSlug)
                            .textFieldStyle(.roundedBorder)
                        Button("Add Output Model", action: addOutputModel)
                            .disabled(!canAddOutputModel)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Selected display name", text: $editDisplayName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Selected slug", text: $editSlug)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button("Save Changes", action: saveSelectedOutputModel)
                                .disabled(!canSaveSelectedOutputModel)
                            Button("Delete", role: .destructive, action: requestDeleteSelectedOutputModel)
                                .disabled(selectedOutputModel == nil)
                        }
                    }

                    Button("Reset built-in defaults") {
                        viewModel.resetBuiltInOutputModelsAndMappings()
                        syncSelectionAfterCatalogChange()
                    }
                    .help("Restores built-in output models and their mappings while preserving user-created models and guides.")
                }
                .padding(.top, 4)
            }
        }
    }

    private var mappingPane: some View {
        GroupBox("Guide Mapping") {
            VStack(alignment: .leading, spacing: 10) {
                if let selectedOutputModel {
                    Text("Mapped guides for \(selectedOutputModel.displayName)")
                        .font(.headline)

                    List(orderedGuidesForSelectedOutput, id: \.id, selection: $selectedMappedGuideID) { guide in
                        HStack(spacing: 8) {
                            Text(guide.title)
                            if guide.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text(guide.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(guide.id)
                    }
                    .frame(minHeight: 160)

                    HStack(spacing: 8) {
                        Picker("Unassigned guide", selection: $selectedUnassignedGuideID) {
                            Text("Select guide").tag(Optional<String>.none)
                            ForEach(unassignedGuidesForSelectedOutput, id: \.id) { guide in
                                Text(guide.title).tag(Optional(guide.id))
                            }
                        }
                        .frame(maxWidth: 320)

                        Button("Assign", action: assignSelectedGuide)
                            .disabled(!canAssignSelectedGuide)
                    }

                    HStack(spacing: 8) {
                        Button("Move Up", action: moveSelectedGuideUp)
                            .disabled(!canMoveSelectedGuideUp)
                        Button("Move Down", action: moveSelectedGuideDown)
                            .disabled(!canMoveSelectedGuideDown)
                        Button("Unassign", action: unassignSelectedGuide)
                            .disabled(!canUnassignSelectedGuide)
                    }
                } else {
                    ContentUnavailableView(
                        "Select an Output Model",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Choose an output model to edit ordered guide mappings.")
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    private var guideLibraryPane: some View {
        GroupBox("Guide Library") {
            VStack(alignment: .leading, spacing: 10) {
                List(guides, id: \.id, selection: $selectedLibraryGuideID) { guide in
                    HStack(spacing: 8) {
                        Text(guide.title)
                        if guide.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(guide.storagePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(guide.id)
                }
                .frame(minHeight: 180)

                HStack(spacing: 8) {
                    Button("Import .md") {
                        isImportingGuide = true
                    }

                    Button("Delete Selected", role: .destructive) {
                        requestDeleteSelectedGuide()
                    }
                    .disabled(!canDeleteSelectedGuide)
                }
            }
            .padding(.top, 4)
        }
    }

    private func addOutputModel() {
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

    private func saveSelectedOutputModel() {
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

    private func requestDeleteSelectedOutputModel() {
        pendingOutputDeletion = selectedOutputModel
    }

    private func confirmDeleteOutputModel() {
        guard let model = pendingOutputDeletion else {
            return
        }

        _ = viewModel.deleteOutputModel(slug: model.slug)
        pendingOutputDeletion = nil
        selectedMappedGuideID = nil
        selectedUnassignedGuideID = nil
        syncSelectionAfterCatalogChange()
    }

    private func assignSelectedGuide() {
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

    private func unassignSelectedGuide() {
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

    private func moveSelectedGuideUp() {
        guard let selectedOutputSlug, let selectedMappedGuideID else {
            return
        }

        do {
            try viewModel.moveGuideUp(selectedMappedGuideID, inOutputModel: selectedOutputSlug)
        } catch {
            present(error)
        }
    }

    private func moveSelectedGuideDown() {
        guard let selectedOutputSlug, let selectedMappedGuideID else {
            return
        }

        do {
            try viewModel.moveGuideDown(selectedMappedGuideID, inOutputModel: selectedOutputSlug)
        } catch {
            present(error)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else {
                return
            }

            do {
                let imported = try viewModel.importGuide(from: sourceURL)
                selectedLibraryGuideID = imported.id
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

    private func requestDeleteSelectedGuide() {
        guard let selectedLibraryGuide, !selectedLibraryGuide.isBuiltIn else {
            return
        }
        pendingGuideDeletion = selectedLibraryGuide
    }

    private func confirmDeleteGuide() {
        guard let guide = pendingGuideDeletion else {
            return
        }

        do {
            try viewModel.deleteGuide(id: guide.id)
            pendingGuideDeletion = nil
            selectedLibraryGuideID = nil
            selectedMappedGuideID = nil
            if selectedUnassignedGuideID?.caseInsensitiveCompare(guide.id) == .orderedSame {
                selectedUnassignedGuideID = nil
            }
        } catch {
            present(error)
        }
    }

    private func syncSelectionAfterCatalogChange() {
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

    private func syncEditorsFromSelectedOutput() {
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

    private func present(_ error: Error) {
        activeError = GuidesErrorState(
            title: "Guides Error",
            message: error.localizedDescription
        )
    }
}

private struct GuidesErrorState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

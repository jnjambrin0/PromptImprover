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
    @State private var pendingEditorTransition: PendingEditorTransition?
    @State private var pendingRevertGuide: GuideDoc?
    @State private var activeError: GuidesErrorState?

    @State private var editorGuideID: String?
    @State private var editorText: String = ""
    @State private var savedEditorText: String = ""
    @State private var editorIsEditable: Bool = false

    @State private var workspaceMode: GuidesWorkspaceMode = .editor
    @AppStorage("settings.guides.workspace.mode") private var storedWorkspaceModeRawValue: String = GuidesWorkspaceMode.editor.rawValue
    @State private var guideSearchQuery: String = ""

    private var outputModels: [OutputModel] {
        viewModel.outputModels
    }

    private var guides: [GuideDoc] {
        viewModel.guides
    }

    private var filteredGuides: [GuideDoc] {
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

    private var librarySelectionBinding: Binding<String?> {
        Binding(
            get: { selectedLibraryGuideID },
            set: { proposed in
                requestLibrarySelection(proposed)
            }
        )
    }

    private var workspaceSelectionBinding: Binding<GuidesWorkspaceMode> {
        Binding(
            get: { workspaceMode },
            set: { proposed in
                requestWorkspaceModeChange(proposed)
            }
        )
    }

    private var editorGuide: GuideDoc? {
        guard let editorGuideID else {
            return nil
        }
        return guides.first { $0.id.caseInsensitiveCompare(editorGuideID) == .orderedSame }
    }

    private var editorBinding: Binding<String> {
        if editorIsEditable {
            return $editorText
        }

        return Binding(
            get: { editorText },
            set: { _ in }
        )
    }

    private var isEditorDirty: Bool {
        guard editorGuideID != nil else {
            return false
        }
        return editorText != savedEditorText
    }

    private var canSaveEditorChanges: Bool {
        editorGuide != nil && editorIsEditable && isEditorDirty
    }

    private var canDiscardEditorChanges: Bool {
        editorGuide != nil && isEditorDirty
    }

    private var canStartForkEdit: Bool {
        guard let guide = editorGuide, guide.isBuiltIn else {
            return false
        }
        return !viewModel.guideHasFork(id: guide.id)
    }

    private var canRevertToBuiltIn: Bool {
        guard let guide = editorGuide, guide.isBuiltIn else {
            return false
        }
        return viewModel.guideHasFork(id: guide.id)
    }

    private var pendingTransitionMessage: String {
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

    var body: some View {
        HSplitView {
            outputModelsPane
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)

            rightWorkspacePane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if let persisted = GuidesWorkspaceMode(rawValue: storedWorkspaceModeRawValue) {
                workspaceMode = persisted
            } else {
                workspaceMode = .editor
                storedWorkspaceModeRawValue = GuidesWorkspaceMode.editor.rawValue
            }

            syncSelectionAfterCatalogChange()
            syncGuideSelectionAfterCatalogChange()
        }
        .onChange(of: outputModels) { _, _ in
            syncSelectionAfterCatalogChange()
        }
        .onChange(of: guides) { _, _ in
            syncGuideSelectionAfterCatalogChange()
        }
        .onChange(of: selectedOutputSlug) { _, _ in
            syncEditorsFromSelectedOutput()
        }
        .onChange(of: workspaceMode) { _, newMode in
            storedWorkspaceModeRawValue = newMode.rawValue
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
        .confirmationDialog("Discard Unsaved Changes?", isPresented: Binding(
            get: { pendingEditorTransition != nil },
            set: { show in
                if !show {
                    pendingEditorTransition = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                confirmPendingEditorTransition()
            }
            Button("Keep Editing", role: .cancel) {
                pendingEditorTransition = nil
            }
        } message: {
            Text(pendingTransitionMessage)
        }
        .confirmationDialog("Revert to Built-In?", isPresented: Binding(
            get: { pendingRevertGuide != nil },
            set: { show in
                if !show {
                    pendingRevertGuide = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Revert", role: .destructive) {
                confirmRevertSelectedGuide()
            }
            Button("Cancel", role: .cancel) {
                pendingRevertGuide = nil
            }
        } message: {
            if let pendingRevertGuide {
                Text("Revert \"\(pendingRevertGuide.title)\" to bundled built-in content? Local fork changes will be removed.")
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

    private var rightWorkspacePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Workspace", selection: workspaceSelectionBinding) {
                ForEach(GuidesWorkspaceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Group {
                switch workspaceMode {
                case .editor:
                    editorWorkspacePane
                case .mapping:
                    mappingPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorWorkspacePane: some View {
        HSplitView {
            guideLibraryPane
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)

            guideEditorPane
                .frame(minWidth: 400, maxWidth: .infinity)
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
                    .frame(minHeight: 120, maxHeight: .infinity)

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

                    HStack(spacing: 8) {
                        Button("Open in Editor", action: openSelectedMappedGuideInEditor)
                            .disabled(selectedMappedGuideID == nil)
                        Spacer()
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
                TextField("Search guides by title, id, or path", text: $guideSearchQuery)
                    .textFieldStyle(.roundedBorder)

                List(filteredGuides, id: \.id, selection: librarySelectionBinding) { guide in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(guide.title)
                                .lineLimit(1)
                            if guide.isBuiltIn {
                                Text("Built-in")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            if guide.isBuiltIn && viewModel.guideHasFork(id: guide.id) {
                                Text("Forked")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }

                        Text(guide.storagePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                    .tag(guide.id)
                }
                .frame(minHeight: 180, maxHeight: .infinity)

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

    private var guideEditorPane: some View {
        GroupBox("Guide Editor") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let editorGuide {
                        Text(editorGuide.title)
                            .font(.headline)
                            .lineLimit(1)

                        if editorGuide.isBuiltIn {
                            Text("Built-in")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Text("User")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    } else {
                        Text("No guide selected")
                            .font(.headline)
                    }

                    Spacer()

                    if isEditorDirty {
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if editorGuide != nil {
                    TextEditor(text: editorBinding)
                        .writingToolsBehavior(.disabled)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isEditorDirty
                                        ? Color.accentColor.opacity(0.6)
                                        : Color.secondary.opacity(0.4),
                                    lineWidth: 1
                                )
                        )

                    if canStartForkEdit {
                        Text("Built-in guides are read-only. Choose Edit to create a local fork before saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if canStartForkEdit {
                            Button("Edit", action: beginEditingSelectedGuide)
                        }

                        Button("Save", action: saveEditorChanges)
                            .disabled(!canSaveEditorChanges)

                        Button("Discard", action: discardEditorChanges)
                            .disabled(!canDiscardEditorChanges)

                        if canRevertToBuiltIn {
                            Button("Revert to built-in", role: .destructive) {
                                requestRevertSelectedGuide()
                            }
                        }

                        Spacer()

                        Button("Close Editor") {
                            requestCloseEditor()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Guide",
                        systemImage: "doc.text",
                        description: Text("Choose a guide in the library to view or edit its markdown.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func openSelectedMappedGuideInEditor() {
        guard let selectedMappedGuideID else {
            return
        }

        applyWorkspaceMode(.editor)
        requestLibrarySelection(selectedMappedGuideID)
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
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

    private func syncGuideSelectionAfterCatalogChange() {
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

    private func requestLibrarySelection(_ proposedGuideID: String?) {
        if matchesGuideID(selectedLibraryGuideID, proposedGuideID) == .some(true) {
            return
        }

        if isEditorDirty {
            pendingEditorTransition = .selectGuide(proposedGuideID)
            return
        }

        applyLibrarySelection(proposedGuideID)
    }

    private func applyLibrarySelection(_ guideID: String?) {
        selectedLibraryGuideID = guideID
        loadEditor(forGuideID: guideID)
    }

    private func requestWorkspaceModeChange(_ proposedMode: GuidesWorkspaceMode) {
        guard proposedMode != workspaceMode else {
            return
        }

        if workspaceMode == .editor && isEditorDirty {
            pendingEditorTransition = .switchWorkspace(proposedMode)
            return
        }

        applyWorkspaceMode(proposedMode)
    }

    private func applyWorkspaceMode(_ mode: GuidesWorkspaceMode) {
        workspaceMode = mode
    }

    private func loadEditor(forGuideID guideID: String?) {
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

    private func beginEditingSelectedGuide() {
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

    private func saveEditorChanges() {
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

    private func discardEditorChanges() {
        guard editorGuide != nil else {
            return
        }
        editorText = savedEditorText
    }

    private func requestRevertSelectedGuide() {
        guard let guide = editorGuide, guide.isBuiltIn, viewModel.guideHasFork(id: guide.id) else {
            return
        }
        pendingRevertGuide = guide
    }

    private func confirmRevertSelectedGuide() {
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

    private func requestCloseEditor() {
        guard editorGuide != nil else {
            return
        }

        if isEditorDirty {
            pendingEditorTransition = .closeEditor
            return
        }

        applyLibrarySelection(nil)
    }

    private func confirmPendingEditorTransition() {
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

    private func clearEditorState() {
        editorGuideID = nil
        editorText = ""
        savedEditorText = ""
        editorIsEditable = false
    }

    private func matchesGuideID(_ lhs: String?, _ rhs: String?) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default:
            return nil
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

private enum PendingEditorTransition {
    case selectGuide(String?)
    case closeEditor
    case switchWorkspace(GuidesWorkspaceMode)
}

private enum GuidesWorkspaceMode: String, CaseIterable, Identifiable {
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

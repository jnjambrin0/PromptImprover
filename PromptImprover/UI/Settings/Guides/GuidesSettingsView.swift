import SwiftUI
import UniformTypeIdentifiers

struct GuidesSettingsView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    @State var selectedOutputSlug: String?
    @State var selectedMappedGuideID: String?
    @State var selectedLibraryGuideID: String?

    @State var addDisplayName: String = ""
    @State var addSlug: String = ""
    @State var editDisplayName: String = ""
    @State var editSlug: String = ""

    @State var selectedUnassignedGuideID: String?
    @State var isImportingGuide: Bool = false

    @State var pendingOutputDeletion: OutputModel?
    @State var pendingGuideDeletion: GuideDoc?
    @State var pendingEditorTransition: PendingEditorTransition?
    @State var pendingRevertGuide: GuideDoc?
    @State var activeError: GuidesErrorState?

    @State var editorGuideID: String?
    @State var editorText: String = ""
    @State var savedEditorText: String = ""
    @State var editorIsEditable: Bool = false

    @State var workspaceMode: GuidesWorkspaceMode = .editor
    @AppStorage("settings.guides.workspace.mode") var storedWorkspaceModeRawValue: String = GuidesWorkspaceMode.editor.rawValue
    @State var guideSearchQuery: String = ""

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
}

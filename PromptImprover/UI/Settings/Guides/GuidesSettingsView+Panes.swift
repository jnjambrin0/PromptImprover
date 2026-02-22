import SwiftUI

extension GuidesSettingsView {
    var rightWorkspacePane: some View {
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

    var editorWorkspacePane: some View {
        HSplitView {
            guideLibraryPane
                .frame(minWidth: 220, idealWidth: 270, maxWidth: 360)

            guideEditorPane
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }

    var outputModelsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Output Models") {
                VStack(alignment: .leading, spacing: 4) {
                    List(outputModels, selection: $selectedOutputSlug) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            Text(model.slug)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.slug)
                        .contextMenu {
                            Button("Edit...") {
                                selectedOutputSlug = model.slug
                                editDisplayName = model.displayName
                                editSlug = model.slug
                                showEditOutputPopover = true
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                selectedOutputSlug = model.slug
                                DispatchQueue.main.async { requestDeleteSelectedOutputModel() }
                            }
                        }
                    }
                    .frame(minHeight: 200)

                    HStack(spacing: 4) {
                        Button(action: { showAddOutputPopover = true }) {
                            Image(systemName: "plus")
                        }
                        .popover(isPresented: $showAddOutputPopover) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add Output Model")
                                    .font(.headline)
                                TextField("Display name", text: $addDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 220)
                                TextField("Slug (e.g. gpt-5-2)", text: $addSlug)
                                    .textFieldStyle(.roundedBorder)
                                HStack {
                                    Spacer()
                                    Button("Cancel") {
                                        addDisplayName = ""
                                        addSlug = ""
                                        showAddOutputPopover = false
                                    }
                                    .keyboardShortcut(.cancelAction)
                                    Button("Add") {
                                        addOutputModel()
                                        showAddOutputPopover = false
                                    }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(!canAddOutputModel)
                                }
                            }
                            .padding(12)
                        }

                        Button(action: requestDeleteSelectedOutputModel) {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedOutputModel == nil)

                        Spacer()
                    }
                    .popover(isPresented: $showEditOutputPopover) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Edit Output Model")
                                .font(.headline)
                            TextField("Display name", text: $editDisplayName)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 220)
                            TextField("Slug", text: $editSlug)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Spacer()
                                Button("Cancel") {
                                    syncEditorsFromSelectedOutput()
                                    showEditOutputPopover = false
                                }
                                .keyboardShortcut(.cancelAction)
                                Button("Save") {
                                    saveSelectedOutputModel()
                                    showEditOutputPopover = false
                                }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!canSaveSelectedOutputModel)
                            }
                        }
                        .padding(12)
                    }

                    Button("Reset built-in defaults") {
                        viewModel.resetBuiltInOutputModelsAndMappings()
                        syncSelectionAfterCatalogChange()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .help("Restores built-in output models and their mappings while preserving user-created models and guides.")
                }
                .padding(.top, 4)
            }
        }
    }

    var mappingPane: some View {
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
                        .contextMenu {
                            Button("Move Up") {
                                selectedMappedGuideID = guide.id
                                DispatchQueue.main.async { moveSelectedGuideUp() }
                            }
                            .disabled(orderedGuidesForSelectedOutput.first?.id == guide.id)
                            Button("Move Down") {
                                selectedMappedGuideID = guide.id
                                DispatchQueue.main.async { moveSelectedGuideDown() }
                            }
                            .disabled(orderedGuidesForSelectedOutput.last?.id == guide.id)
                            Divider()
                            Button("Open in Editor") {
                                selectedMappedGuideID = guide.id
                                DispatchQueue.main.async { openSelectedMappedGuideInEditor() }
                            }
                            Divider()
                            Button("Unassign") {
                                selectedMappedGuideID = guide.id
                                DispatchQueue.main.async { unassignSelectedGuide() }
                            }
                        }
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

                        Button(action: unassignSelectedGuide) {
                            Image(systemName: "minus")
                        }
                        .disabled(!canUnassignSelectedGuide)
                        .help("Unassign selected guide")
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

    var guideLibraryPane: some View {
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

    var guideEditorPane: some View {
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
                        Button("Save", action: saveEditorChanges)
                            .disabled(!canSaveEditorChanges)

                        Button("Discard", action: discardEditorChanges)
                            .disabled(!canDiscardEditorChanges)

                        Menu {
                            if canStartForkEdit {
                                Button("Edit (Create Fork)", action: beginEditingSelectedGuide)
                            }
                            if canRevertToBuiltIn {
                                Button("Revert to Built-In", role: .destructive) {
                                    requestRevertSelectedGuide()
                                }
                            }
                            Divider()
                            Button("Close Editor") {
                                requestCloseEditor()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Spacer()

                        if isEditorDirty {
                            Text("Unsaved changes")
                                .font(.caption)
                                .foregroundStyle(.orange)
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
}

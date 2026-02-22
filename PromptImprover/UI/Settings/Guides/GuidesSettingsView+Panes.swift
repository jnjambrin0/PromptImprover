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
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)

            guideEditorPane
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }

    var outputModelsPane: some View {
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
}

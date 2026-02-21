import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var viewModel: PromptImproverViewModel

    @State private var selectedTool: Tool = .codex
    @State private var selectedModel: String?
    @State private var newModelName: String = ""
    @State private var renameModelName: String = ""

    private static let capabilityTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var models: [String] {
        viewModel.resolvedEngineModels(for: selectedTool)
    }

    private var selectedAvailability: CLIAvailability? {
        viewModel.availabilityByTool[selectedTool]
    }

    private var selectedCapabilityEntry: CachedToolCapabilities? {
        viewModel.capabilityEntriesByTool[selectedTool]
    }

    private var supportedEfforts: [EngineEffort] {
        guard let capabilities = viewModel.capabilitiesByTool[selectedTool], capabilities.supportsEffortConfig else {
            return EngineEffort.allCases
        }

        let parsed = ToolEngineSettings.orderedUniqueEfforts(capabilities.supportedEffortValues)
        return parsed.isEmpty ? EngineEffort.allCases : parsed
    }

    private var supportsEffortConfiguration: Bool {
        viewModel.capabilitiesByTool[selectedTool]?.supportsEffortConfig == true
    }

    private var canAddModel: Bool {
        guard let candidate = normalizedModel(from: newModelName) else {
            return false
        }
        return !containsModel(candidate)
    }

    private var canRenameModel: Bool {
        guard let current = selectedModel,
              let candidate = normalizedModel(from: renameModelName) else {
            return false
        }

        if current == candidate {
            return false
        }

        return !containsModel(candidate, excluding: current)
    }

    private var canMoveSelectedModelUp: Bool {
        guard let index = selectedModelIndex else {
            return false
        }
        return index > 0
    }

    private var canMoveSelectedModelDown: Bool {
        guard let index = selectedModelIndex else {
            return false
        }
        return index < models.count - 1
    }

    private var selectedModelIndex: Int? {
        guard let selectedModel else {
            return nil
        }

        return models.firstIndex {
            $0.caseInsensitiveCompare(selectedModel) == .orderedSame
        }
    }

    private var canDeleteModel: Bool {
        selectedModelIndex != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Tool", selection: $selectedTool) {
                    ForEach(Tool.allCases) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button("Reset to defaults") {
                    viewModel.resetToolSettingsToDefaults(selectedTool)
                    syncSelectedModelWithCurrentList()
                }
            }

            modelListEditor

            Form {
                defaultModelPicker
                defaultEffortPicker
                allowlistEditor
                capabilityStatus
            }
        }
        .onAppear {
            syncSelectedModelWithCurrentList()
        }
        .onChange(of: selectedTool) { _, _ in
            syncSelectedModelWithCurrentList()
        }
        .onChange(of: models) { _, _ in
            syncSelectedModelWithCurrentList()
        }
        .onChange(of: selectedModel) { _, newValue in
            renameModelName = newValue ?? ""
        }
    }

    private var modelListEditor: some View {
        GroupBox("Engine Models") {
            HStack(alignment: .top, spacing: 12) {
                List(models, id: \.self, selection: $selectedModel) { model in
                    Text(model)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                }
                .frame(minWidth: 320, minHeight: 200)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Add model identifier", text: $newModelName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add", action: addModel)
                            .disabled(!canAddModel)
                    }

                    HStack(spacing: 8) {
                        TextField("Rename selected model", text: $renameModelName)
                            .textFieldStyle(.roundedBorder)
                        Button("Rename", action: renameSelectedModel)
                            .disabled(!canRenameModel)
                    }

                    HStack(spacing: 8) {
                        Button("Move Up", action: moveSelectedModelUp)
                            .disabled(!canMoveSelectedModelUp)
                        Button("Move Down", action: moveSelectedModelDown)
                            .disabled(!canMoveSelectedModelDown)
                        Button("Delete", role: .destructive, action: deleteSelectedModel)
                            .disabled(!canDeleteModel)
                    }

                    Text("Ordered list applies to new runs only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private var defaultModelPicker: some View {
        let selection = Binding<String?>(
            get: {
                canonicalModelIdentifier(for: viewModel.configuredDefaultEngineModel(for: selectedTool))
            },
            set: { newValue in
                viewModel.updateDefaultEngineModel(newValue, for: selectedTool)
            }
        )

        return LabeledContent {
            Picker("", selection: selection) {
                Text("Automatic (first model)").tag(Optional<String>.none)
                ForEach(models, id: \.self) { model in
                    Text(model).tag(Optional(model))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
        } label: {
            Text("Default engine model")
        }
    }

    private var defaultEffortPicker: some View {
        let selection = Binding<EngineEffort?>(
            get: {
                guard let configured = viewModel.configuredDefaultEffort(for: selectedTool) else {
                    return nil
                }
                return supportedEfforts.contains(configured) ? configured : nil
            },
            set: { newValue in
                viewModel.updateDefaultEffort(newValue, for: selectedTool)
            }
        )

        return Group {
            if supportsEffortConfiguration {
                LabeledContent {
                    Picker("", selection: selection) {
                        Text("None").tag(Optional<EngineEffort>.none)
                        ForEach(supportedEfforts, id: \.self) { effort in
                            Text(effort.rawValue.capitalized).tag(Optional(effort))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                } label: {
                    Text("Default effort")
                }
            } else {
                LabeledContent {
                    Text("Not supported by detected binary")
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Default effort")
                }
            }
        }
    }

    private var allowlistEditor: some View {
        Group {
            if let selectedModel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-model effort allowlist")
                    Text(selectedModel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        ForEach(EngineEffort.allCases, id: \.self) { effort in
                            Toggle(effort.rawValue.capitalized, isOn: effortToggleBinding(for: effort, model: selectedModel))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            } else {
                LabeledContent {
                    Text("Select a model to edit effort allowlist")
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Per-model effort allowlist")
                }
            }
        }
    }

    private var capabilityStatus: some View {
        let statusText: String
        if viewModel.isRecheckingCapabilities(for: selectedTool) {
            statusText = "Rechecking..."
        } else if selectedAvailability == nil {
            statusText = "Checking..."
        } else if selectedAvailability?.installed == false {
            statusText = "Not installed"
        } else if selectedAvailability?.healthMessage != nil {
            statusText = "Error"
        } else {
            statusText = "Ready"
        }

        return Section {
            LabeledContent("Status") {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Binary path") {
                Text(selectedAvailability?.executableURL?.path ?? "Not found")
                    .textSelection(.enabled)
                    .font(.system(size: 11, design: .monospaced))
            }

            LabeledContent("Version") {
                Text(selectedAvailability?.version ?? "Unknown")
            }

            LabeledContent("Last checked") {
                if let timestamp = selectedCapabilityEntry?.signature.lastCheckedAt {
                    Text(ModelsSettingsView.capabilityTimestampFormatter.string(from: timestamp))
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }

            if let healthMessage = selectedAvailability?.healthMessage, !healthMessage.isEmpty {
                LabeledContent("Health") {
                    Text(healthMessage)
                        .foregroundStyle(.red)
                }
            }

            Button("Recheck") {
                viewModel.recheckCapabilities(for: selectedTool)
            }
            .disabled(selectedAvailability?.installed != true || viewModel.isRecheckingCapabilities(for: selectedTool))
        } header: {
            Text("Capability status")
        }
    }

    private func addModel() {
        guard let model = normalizedModel(from: newModelName) else {
            return
        }
        guard !containsModel(model) else {
            return
        }

        var updated = models
        updated.append(model)
        viewModel.updateOrderedEngineModels(updated, for: selectedTool)

        selectedModel = model
        renameModelName = model
        newModelName = ""
    }

    private func renameSelectedModel() {
        guard let currentModel = selectedModel,
              let index = selectedModelIndex,
              let renamed = normalizedModel(from: renameModelName) else {
            return
        }

        if currentModel == renamed {
            return
        }

        if containsModel(renamed, excluding: currentModel) {
            return
        }

        let existingAllowlist = viewModel.configuredAllowlistedEfforts(for: selectedTool, model: currentModel)
        let shouldRetainDefault = viewModel.configuredDefaultEngineModel(for: selectedTool)?
            .caseInsensitiveCompare(currentModel) == .orderedSame

        var updated = models
        updated[index] = renamed
        viewModel.updateOrderedEngineModels(updated, for: selectedTool)

        if shouldRetainDefault {
            viewModel.updateDefaultEngineModel(renamed, for: selectedTool)
        }

        if !existingAllowlist.isEmpty {
            viewModel.updateAllowlistedEfforts(existingAllowlist, for: selectedTool, model: renamed)
        }

        selectedModel = renamed
        renameModelName = renamed
    }

    private func moveSelectedModelUp() {
        guard let index = selectedModelIndex, index > 0 else {
            return
        }

        var updated = models
        updated.swapAt(index, index - 1)
        viewModel.updateOrderedEngineModels(updated, for: selectedTool)
    }

    private func moveSelectedModelDown() {
        guard let index = selectedModelIndex, index < models.count - 1 else {
            return
        }

        var updated = models
        updated.swapAt(index, index + 1)
        viewModel.updateOrderedEngineModels(updated, for: selectedTool)
    }

    private func deleteSelectedModel() {
        guard let index = selectedModelIndex else {
            return
        }

        var updated = models
        updated.remove(at: index)
        viewModel.updateOrderedEngineModels(updated, for: selectedTool)

        if updated.indices.contains(index) {
            selectedModel = updated[index]
        } else {
            selectedModel = updated.last
        }
        renameModelName = selectedModel ?? ""
    }

    private func effortToggleBinding(for effort: EngineEffort, model: String) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.configuredAllowlistedEfforts(for: selectedTool, model: model).contains(effort)
            },
            set: { enabled in
                var updated = viewModel.configuredAllowlistedEfforts(for: selectedTool, model: model)
                if enabled {
                    if !updated.contains(effort) {
                        updated.append(effort)
                    }
                } else {
                    updated.removeAll { $0 == effort }
                }
                viewModel.updateAllowlistedEfforts(updated, for: selectedTool, model: model)
            }
        )
    }

    private func containsModel(_ candidate: String, excluding excluded: String? = nil) -> Bool {
        models.contains { model in
            if let excluded, model.caseInsensitiveCompare(excluded) == .orderedSame {
                return false
            }
            return model.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func normalizedModel(from raw: String) -> String? {
        ToolEngineSettings.normalizeModelIdentifier(raw)
    }

    private func canonicalModelIdentifier(for raw: String?) -> String? {
        guard let normalized = ToolEngineSettings.normalizeModelIdentifier(raw) else {
            return nil
        }

        return models.first { model in
            model.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    private func syncSelectedModelWithCurrentList() {
        guard !models.isEmpty else {
            selectedModel = nil
            renameModelName = ""
            return
        }

        if let selectedModel,
           let canonical = canonicalModelIdentifier(for: selectedModel) {
            self.selectedModel = canonical
            if renameModelName.isEmpty {
                renameModelName = canonical
            }
            return
        }

        selectedModel = models.first
        renameModelName = selectedModel ?? ""
    }
}

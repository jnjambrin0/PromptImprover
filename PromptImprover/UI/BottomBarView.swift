import SwiftUI

struct BottomBarView: View {
    @Binding var selectedTool: Tool
    @Binding var selectedTargetSlug: String
    let outputModels: [OutputModel]
    let isRunning: Bool
    let canImprove: Bool
    let onImprove: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            toolPicker
            modelPicker
            Spacer()
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var toolPicker: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                toolPill(tool)
            }
        }
    }

    private func toolPill(_ tool: Tool) -> some View {
        Button(action: { selectedTool = tool }) {
            Text(tool.shortDisplayName)
                .font(.caption)
                .fontWeight(selectedTool == tool ? .semibold : .regular)
                .foregroundStyle(selectedTool == tool ? Color.accentColor : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if selectedTool == tool {
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    } else {
                        Capsule().fill(Color.secondary.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }

    private var modelPicker: some View {
        Menu {
            ForEach(outputModels) { model in
                Button(action: { selectedTargetSlug = model.slug }) {
                    Text(model.displayName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedModelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.secondary.opacity(0.1))
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(outputModels.isEmpty)
    }

    private var selectedModelName: String {
        outputModels.first(where: { $0.slug == selectedTargetSlug })?.displayName
            ?? outputModels.first?.displayName
            ?? "No model"
    }

    @ViewBuilder
    private var actionButton: some View {
        if isRunning {
            stopButton
        } else {
            improveButton
        }
    }

    private var stopButton: some View {
        Button(action: onStop) {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.caption2)
                Text("Stop")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.red.opacity(0.8)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }

    private var improveButton: some View {
        Button(action: onImprove) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(!canImprove)
        .opacity(canImprove ? 1 : 0.4)
        .keyboardShortcut(.defaultAction)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

#Preview {
    BottomBarView(
        selectedTool: .constant(.codex),
        selectedTargetSlug: .constant("claude-4-sonnet"),
        outputModels: [
            OutputModel(displayName: "Claude 4 Sonnet", slug: "claude-4-sonnet", guideIds: []),
            OutputModel(displayName: "GPT-5.2", slug: "gpt-5-2", guideIds: [])
        ],
        isRunning: false,
        canImprove: true,
        onImprove: {},
        onStop: {}
    )
    .frame(width: 600)
}

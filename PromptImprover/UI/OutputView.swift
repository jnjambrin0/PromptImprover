import SwiftUI

struct OutputView: View {
    let output: String
    let isRunning: Bool
    let onCopy: () -> Void

    private var readOnlyOutputBinding: Binding<String> {
        Binding(
            get: { output },
            set: { _ in }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Optimized Prompt")
                    .font(.headline)
                Spacer()
                Button("Copy", action: onCopy)
                    .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: readOnlyOutputBinding)
                .writingToolsBehavior(.disabled)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 220)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor.opacity(0.5),
                            lineWidth: 1
                        )
                )
                .textSelection(.enabled)

            if isRunning {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Streaming...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

import SwiftUI

struct OutputView: View {
    let output: String
    let isRunning: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Optimized Prompt")
                    .font(.headline)
                Spacer()
                Button("Copy", action: onCopy)
                    .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: .constant(output))
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 180)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
                .disabled(true)

            if isRunning {
                Text("Streaming...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

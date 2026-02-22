import SwiftUI

struct OutputView: View {
    let output: String
    let isRunning: Bool
    let onCopy: () -> Void

    @State private var justCopied = false
    @State private var copyGeneration = 0

    private var hasOutput: Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                copyButton
            }

            TextEditor(text: readOnlyOutputBinding)
                .writingToolsBehavior(.disabled)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
                .cornerRadius(8)
                .frame(minHeight: 120, idealHeight: 220, maxHeight: .infinity)
                .padding(2) // Give space for the border
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            hasOutput
                                ? Color.accentColor.opacity(0.7)
                                : Color.secondary.opacity(0.4),
                            lineWidth: 1.5
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

    private var copyButton: some View {
        Button(action: handleCopy) {
            Label(
                justCopied ? "Copied!" : "Copy",
                systemImage: justCopied ? "checkmark" : "doc.on.doc"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .tint(justCopied ? .green : nil)
        .disabled(!hasOutput)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func handleCopy() {
        onCopy()
        copyGeneration += 1
        let generation = copyGeneration
        withAnimation(.easeInOut(duration: 0.3)) {
            justCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard copyGeneration == generation else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                justCopied = false
            }
        }
    }
}

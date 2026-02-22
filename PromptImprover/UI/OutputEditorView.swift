import SwiftUI

struct OutputEditorView: View {
    let output: String
    let onCopy: () -> Void

    @State private var justCopied = false
    @State private var copyGeneration = 0

    private var hasOutput: Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var readOnlyBinding: Binding<String> {
        Binding(
            get: { output },
            set: { _ in }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: readOnlyBinding)
                .writingToolsBehavior(.disabled)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .textSelection(.enabled)

            if hasOutput {
                Divider()
                HStack {
                    Spacer()
                    copyButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    hasOutput
                        ? Color.accentColor.opacity(0.3)
                        : Color.secondary.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    private var copyButton: some View {
        Button(action: handleCopy) {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(justCopied ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
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

#Preview {
    OutputEditorView(
        output: "This is the optimized prompt output.",
        onCopy: {}
    )
    .frame(width: 500, height: 300)
    .padding()
}

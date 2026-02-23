import SwiftUI

struct InputEditorView: View {
    @Binding var text: String
    var disabledReason: String?
    var showDisabledReason: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .writingToolsBehavior(.disabled)
                .font(.system(size: 14, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)

            if text.isEmpty {
                Text("Describe what you want the prompt to do...")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    text.isEmpty
                        ? Color.secondary.opacity(0.2)
                        : Color.accentColor.opacity(0.3),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottomLeading) {
            if showDisabledReason, let reason = disabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    InputEditorView(
        text: .constant(""),
        disabledReason: "Enter a prompt to improve.",
        showDisabledReason: true
    )
    .frame(width: 500, height: 300)
    .padding()
}

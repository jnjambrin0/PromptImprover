import SwiftUI

struct PromptEditorView: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input Prompt")
                .font(.headline)
            TextEditor(text: $text)
                .writingToolsBehavior(.disabled)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 220)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            text.isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
    }
}

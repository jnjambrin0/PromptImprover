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
                .scrollContentBackground(.hidden)
                .background(VisualEffectView(material: .contentBackground, blendingMode: .withinWindow))
                .cornerRadius(8)
                .frame(minHeight: 120, idealHeight: 220, maxHeight: .infinity)
                .padding(2) // Give space for the border
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            text.isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color.accentColor.opacity(0.7),
                            lineWidth: 1.5
                        )
                )
        }
    }
}

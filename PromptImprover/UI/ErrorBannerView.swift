import SwiftUI

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red.opacity(0.7))
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.06))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

#Preview {
    ErrorBannerView(
        message: "CLI process failed: timeout after 120 seconds.",
        onDismiss: {}
    )
    .frame(width: 500)
    .padding()
}

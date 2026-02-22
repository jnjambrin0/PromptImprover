import SwiftUI

struct StreamingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * 0.3, height: 2)
                .offset(x: animating ? geo.size.width * 0.7 : 0)
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
            ) {
                animating = true
            }
        }
    }
}

#Preview {
    StreamingIndicatorView()
        .frame(width: 400)
        .padding()
}

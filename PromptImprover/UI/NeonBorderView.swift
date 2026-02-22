import SwiftUI

struct NeonBorderView: View {
    var cornerRadius: CGFloat = 10
    var lineWidth: CGFloat = 2
    var glowRadius: CGFloat = 8
    var duration: Double = 2.0

    @State private var rotation: Double = 0

    private var gradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.55),
                .init(color: Color.accentColor.opacity(0.6), location: 0.7),
                .init(color: .white.opacity(0.9), location: 0.78),
                .init(color: Color.accentColor.opacity(0.6), location: 0.86),
                .init(color: .clear, location: 0.95),
                .init(color: .clear, location: 1.0),
            ]),
            center: .center,
            angle: .degrees(rotation)
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        ZStack {
            shape
                .stroke(gradient, lineWidth: lineWidth * 2)
                .blur(radius: glowRadius)

            shape
                .stroke(gradient, lineWidth: lineWidth)
        }
        .onAppear {
            withAnimation(
                .linear(duration: duration)
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}

#Preview {
    RoundedRectangle(cornerRadius: 10)
        .fill(.background)
        .frame(width: 400, height: 300)
        .overlay {
            NeonBorderView(cornerRadius: 10)
        }
        .padding()
}

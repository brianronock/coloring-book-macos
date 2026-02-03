import SwiftUI

struct WelcomeView: View {
    var start: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Welcome to Coloring!")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Image("drawing00")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2), lineWidth: 1))

                Button(action: start) {
                    Text("Start Coloring")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
            }
            .padding(24)
        }
    }
}

#Preview {
    WelcomeView(start: {})
}

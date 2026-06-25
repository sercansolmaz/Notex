import SwiftUI

/// Animated launch splash screen shown briefly on app open.
struct SplashView: View {
    @State private var animateLogo: Bool = false
    @State private var opacity: Double = 1.0

    /// Called when the splash should be dismissed.
    var onDismiss: () -> Void

    private let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.55, blue: 0.95),
            Color(red: 0.40, green: 0.30, blue: 0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18), // #1a1a2e
                    Color(red: 0.09, green: 0.13, blue: 0.24)  // #16213e
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Logo icon in rounded square with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(accentGradient)
                        .frame(width: 92, height: 92)
                        .shadow(color: Color(red: 0.40, green: 0.40, blue: 0.95).opacity(0.4),
                                radius: 20, x: 0, y: 8)

                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.white)
                }

                // App name
                Text("Notex")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(1.5)

                // Tagline
                Text("Düşüncelerinizi düzenleyin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                    .tracking(0.5)
            }
            .scaleEffect(animateLogo ? 1.0 : 0.8)
            .opacity(animateLogo ? 1.0 : 0.0)
            .opacity(opacity)
        }
        .onAppear {
            // Fade in + scale animation
            withAnimation(.easeOut(duration: 0.5)) {
                animateLogo = true
            }
            // After 1.5s, fade out and dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    opacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onDismiss()
                }
            }
        }
    }
}

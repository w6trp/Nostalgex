import SwiftUI

/// A simple beta wordmark, rendered as text rather than upstream logo artwork.
struct CouchWaveWordmark: View {
    var body: some View {
        GeometryReader { geometry in
            Text("CouchWave")
                .font(.system(size: geometry.size.height * 0.85, weight: .heavy, design: .rounded))
                .italic()
                .foregroundStyle(LinearGradient(colors: [.cyan, .white], startPoint: .leading, endPoint: .trailing))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(5, contentMode: .fit)
        .accessibilityLabel("CouchWave")
    }
}

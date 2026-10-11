import SwiftUI

/// Shared original CouchWave artwork for onboarding, settings and the tuner.
struct CouchWaveWordmark: View {
    var body: some View {
        Image("CouchWaveLogo")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("CouchWave")
    }
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cube")
                .font(.system(size: 48, weight: .light))
                .accessibilityHidden(true)

            Text("TwistTutor")
                .font(.largeTitle.bold())

            Text("Cube Solver")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}

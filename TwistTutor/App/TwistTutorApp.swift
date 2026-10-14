import SwiftUI
import AppWorkflow

@main
struct TwistTutorApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}

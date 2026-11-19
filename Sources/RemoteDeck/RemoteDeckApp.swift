import SwiftUI

@main
struct RemoteDeckApp: App {
    @StateObject private var model = RemoteDeckModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

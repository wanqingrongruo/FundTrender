import SwiftUI
import SwiftData

@main
struct FundTrenderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: FundEntity.self)
    }
}

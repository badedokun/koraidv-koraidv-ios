import SwiftUI
import KoraIDV

@main
struct KoraIDVExampleApp: App {

    init() {
        // Configure the SDK once at app launch
        if !KoraIDV.isConfigured {
            KoraIDV.configure(with: Configuration(
                apiKey: "ck_sandbox_your_api_key_here",
                tenantId: "your-tenant-uuid-here",
                environment: .sandbox
            ))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

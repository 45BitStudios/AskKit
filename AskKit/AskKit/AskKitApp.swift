import AppIntents
import AskKit
import SwiftUI

@main
struct AskKitApp: App {
    private let client: AskIntentClient

    init() {
        do {
            let assistant = try SampleProject.selected.assistant()
            let client = AskIntentClient(assistant: assistant)
            self.client = client
            AppDependencyManager.shared.add(dependency: client)
        } catch {
            fatalError("AskKit could not open its store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            SampleHost(client: client)
        }
    }
}

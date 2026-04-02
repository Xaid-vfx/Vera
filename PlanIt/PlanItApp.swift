import SwiftUI

@main
struct PlanItApp: App {
    @StateObject private var viewModel = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environmentObject(viewModel)
            .onReceive(NotificationCenter.default.publisher(for: .startPlanningSession)) { _ in
                let state = viewModel.sessionManager.state
                guard state == .idle || state == .completed else { return }
                viewModel.startSession()
            }
        }
    }
}

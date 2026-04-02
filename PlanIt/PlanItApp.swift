import SwiftUI

@main
struct PlanItApp: App {
    @StateObject private var viewModel = SessionViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                NavigationStack {
                    HomeView()
                }
                .environmentObject(viewModel)
                .onReceive(NotificationCenter.default.publisher(for: .startPlanningSession)) { _ in
                    let state = viewModel.sessionManager.state
                    guard state == .idle || state == .completed else { return }
                    viewModel.startSession()
                }
            } else {
                OnboardingView(
                    whoopService: viewModel.sessionManager.whoopService,
                    googleCalendarService: viewModel.sessionManager.googleCalendarService,
                    onComplete: { hasCompletedOnboarding = true }
                )
            }
        }
    }
}

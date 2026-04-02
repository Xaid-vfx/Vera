import AppIntents
import Foundation

struct StartPlanningIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan My Day"
    static var description = IntentDescription("Start a voice planning session with PlanIt")

    /// Opens the app before running perform() so NotificationCenter works in-process.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .startPlanningSession, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let startPlanningSession = Notification.Name("com.planit.startSession")
}

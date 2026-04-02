import Foundation
import SwiftUI
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var sessionManager: VoiceSessionManager
    @Published var showPlanResult: Bool = false

    private var managerCancellable: AnyCancellable?

    init() {
        let groqKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? APIKeys.groq
        let openRouterKey = UserDefaults.standard.string(forKey: "openrouter_api_key") ?? APIKeys.openRouter
        let manager = VoiceSessionManager(groqKey: groqKey, openRouterKey: openRouterKey)
        self.sessionManager = manager
        manager.onPlanFinalized = { [weak self] in self?.showPlanResult = true }
        // Forward sessionManager changes so HomeView re-renders when session state changes
        managerCancellable = manager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func updateKeys(groqKey: String, openRouterKey: String) {
        UserDefaults.standard.set(groqKey, forKey: "groq_api_key")
        UserDefaults.standard.set(openRouterKey, forKey: "openrouter_api_key")
        let manager = VoiceSessionManager(groqKey: groqKey, openRouterKey: openRouterKey)
        sessionManager = manager
        manager.onPlanFinalized = { [weak self] in self?.showPlanResult = true }
        managerCancellable = manager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var savedGroqKey: String {
        UserDefaults.standard.string(forKey: "groq_api_key") ?? APIKeys.groq
    }

    var savedOpenRouterKey: String {
        UserDefaults.standard.string(forKey: "openrouter_api_key") ?? APIKeys.openRouter
    }

    func startSession() {
        Task {
            await sessionManager.startSession()
        }
    }

    func endSession() {
        sessionManager.endSession()
        showPlanResult = true
    }

    var isSessionActive: Bool {
        sessionManager.state != .idle && sessionManager.state != .completed
    }

    var statusText: String {
        switch sessionManager.state {
        case .idle: return "Tap to start planning"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .creatingPlan: return "Creating your plan..."
        case .completed: return "Plan complete!"
        }
    }

    func toggleTask(_ task: PlanTask) {
        if let index = sessionManager.currentPlan.tasks.firstIndex(where: { $0.id == task.id }) {
            sessionManager.currentPlan.tasks[index].isCompleted.toggle()
        }
    }
}

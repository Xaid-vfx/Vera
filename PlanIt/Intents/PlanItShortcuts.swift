import AppIntents

/// Registers app shortcuts that Siri knows about without any user setup.
/// Users can say "Hey Siri, plan my day with PlanIt" out of the box.
struct PlanItShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPlanningIntent(),
            phrases: [
                "Plan my day with \(.applicationName)",
                "Start planning with \(.applicationName)",
                "Start my day with \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Plan My Day",
            systemImageName: "mic.circle.fill"
        )
    }
}

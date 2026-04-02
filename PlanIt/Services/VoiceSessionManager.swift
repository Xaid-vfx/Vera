import Foundation
import AVFoundation

@MainActor
final class VoiceSessionManager: ObservableObject {
    enum SessionState: Equatable {
        case idle
        case listening
        case processing
        case speaking
        case creatingPlan
        case completed
    }

    @Published var state: SessionState = .idle
    @Published var liveTranscript: String = ""
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var currentPlan: DayPlan = DayPlan()
    @Published var error: String?

    var onPlanFinalized: (() -> Void)?

    let speechService: SpeechRecognitionService
    let ttsService: TextToSpeechService
    private let aiService: AIService
    private let healthKitService: HealthKitService
    let whoopService: WhoopService
    let googleCalendarService: GoogleCalendarService

    private var healthContext: HealthContext?
    private var isProcessingTurn = false
    private var pendingTranscript: String?
    private var lastCompletedTranscript: String = ""
    private var wasInterrupted = false
    private var turnCount = 0
    private var interruptionAllowedAfter: Date = .distantPast

    init(groqKey: String, openRouterKey: String) {
        self.speechService = SpeechRecognitionService()
        self.ttsService = TextToSpeechService()
        self.aiService = AIService(groqKey: groqKey, openRouterKey: openRouterKey)
        self.healthKitService = HealthKitService()
        self.whoopService = WhoopService()
        self.googleCalendarService = GoogleCalendarService()

        setupCallbacks()
    }

    private func setupCallbacks() {
        speechService.onPartialResult = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveTranscript = text
            }
        }

        speechService.onSpeechDetected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard Date() >= self.interruptionAllowedAfter else {
                    appLogger.notice("[Session] Ignoring speech — within TTS cooldown window")
                    return
                }
                if self.ttsService.isSpeaking && self.state == .speaking {
                    appLogger.notice("[Session] User interrupted — stopping TTS")
                    self.wasInterrupted = true
                    self.ttsService.stop()
                    self.state = .listening
                }
            }
        }

        speechService.onTurnComplete = { [weak self] finalText in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.state == .listening else {
                    appLogger.notice("[Session] Ignoring turn complete — not listening")
                    return
                }
                guard finalText != self.lastCompletedTranscript else {
                    return
                }
                self.lastCompletedTranscript = finalText
                await self.handleTurnComplete(transcript: finalText)
            }
        }

        ttsService.onFinishedSpeaking = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                appLogger.notice("[Session] TTS finished speaking")

                if self.wasInterrupted {
                    self.wasInterrupted = false
                    return
                }

                if self.state == .speaking {
                    if let pending = self.pendingTranscript {
                        self.pendingTranscript = nil
                        await self.handleTurnComplete(transcript: pending)
                    } else {
                        self.state = .listening
                        self.liveTranscript = ""
                        self.lastCompletedTranscript = ""
                        self.speechService.stopListening()
                        try? self.speechService.startListening()
                        appLogger.notice("[Session] Now listening for user input")
                    }
                }
            }
        }
    }

    func startSession() async {
        do {
            appLogger.notice("[Session] Requesting speech auth")
            let speechAuthorized = await speechService.requestAuthorization()
            appLogger.notice("[Session] Speech auth result: \(speechAuthorized)")
            guard speechAuthorized else {
                error = "Speech recognition permission required"
                return
            }

            try? await healthKitService.requestAuthorization()

            // Fetch all health + calendar data in parallel
            async let hkContext   = healthKitService.fetchHealthContext()
            async let whoopData   = whoopService.fetchData()
            async let todayEvents = googleCalendarService.fetchTodayEvents()
            async let tomorrowEvents = googleCalendarService.fetchTomorrowEvents()

            var context = await hkContext
            if let whoop = await whoopData {
                context.whoopRecoveryScore   = whoop.recoveryScore
                context.whoopStrainScore     = whoop.strainScore
                context.whoopSleepPerformance = whoop.sleepPerformance
                context.whoopHRV             = whoop.hrv
                context.whoopRHR             = whoop.rhr
            }
            let todayEvts    = await todayEvents
            let tomorrowEvts = await tomorrowEvents
            if !todayEvts.isEmpty    { context.todayEvents    = todayEvts }
            if !tomorrowEvts.isEmpty { context.tomorrowEvents = tomorrowEvts }
            healthContext = context

            conversationHistory = []
            currentPlan = DayPlan()
            error = nil
            liveTranscript = ""
            lastCompletedTranscript = ""
            isProcessingTurn = false
            pendingTranscript = nil
            wasInterrupted = false
            turnCount = 0
            interruptionAllowedAfter = .distantPast

            let greeting = buildGreeting()
            conversationHistory.append(ConversationMessage(role: .assistant, content: greeting))

            try speechService.startListening()

            state = .speaking
            interruptionAllowedAfter = Date().addingTimeInterval(1.0)
            appLogger.notice("[Session] Speaking greeting")
            ttsService.speak(greeting)

        } catch {
            appLogger.notice("[Session] startSession failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
            state = .idle
        }
    }

    func endSession() {
        speechService.stopListening()
        ttsService.stop()
        state = .completed
    }

    private func handleTurnComplete(transcript: String) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isProcessingTurn else {
            pendingTranscript = transcript
            return
        }

        isProcessingTurn = true
        state = .processing
        turnCount += 1
        appLogger.notice("[Session] Processing turn #\(self.turnCount)")

        speechService.stopListening()
        conversationHistory.append(ConversationMessage(role: .user, content: trimmed))

        do {
            let response = try await aiService.processTurn(
                transcript: trimmed,
                conversationHistory: conversationHistory,
                healthContext: healthContext,
                currentPlan: currentPlan
            )

            appLogger.notice("[Session] AI responded, isPlanComplete=\(response.isPlanComplete)")

            conversationHistory.append(ConversationMessage(role: .assistant, content: response.responseText))

            for task in response.newTasks {
                if !currentPlan.tasks.contains(where: { $0.title.lowercased() == task.title.lowercased() }) {
                    currentPlan.tasks.append(task)
                }
            }
            currentPlan.suggestions = response.suggestions
            isProcessingTurn = false

            if response.isPlanComplete {
                // User confirmed they're done — finalize
                appLogger.notice("[Session] Plan complete — finalizing")
                state = .speaking
                interruptionAllowedAfter = Date().addingTimeInterval(1.0)
                ttsService.speak(response.responseText)

                // After this TTS finishes, transition to creatingPlan
                let originalCallback = ttsService.onFinishedSpeaking
                ttsService.onFinishedSpeaking = { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.ttsService.onFinishedSpeaking = originalCallback
                        await self.finalizePlan()
                    }
                }
            } else {
                // Continue conversation
                try? speechService.startListening()
                state = .speaking
                interruptionAllowedAfter = Date().addingTimeInterval(1.0)
                ttsService.speak(response.responseText)
            }

        } catch {
            appLogger.notice("[Session] AI error: \(error.localizedDescription)")
            isProcessingTurn = false

            // Speak user-facing errors aloud so the user hears what went wrong
            let spokenError = error.localizedDescription
            self.error = spokenError

            try? speechService.startListening()
            state = .speaking
            ttsService.speak(spokenError)
            // After speaking, onFinishedSpeaking will restart listening automatically
        }

        liveTranscript = ""
    }

    private func finalizePlan() async {
        speechService.stopListening()
        state = .creatingPlan
        appLogger.notice("[Session] Creating final plan with \(self.currentPlan.tasks.count) tasks")

        // Ask AI to organize and finalize the plan
        do {
            let response = try await aiService.processTurn(
                transcript: "Please finalize my plan. Organize the tasks by priority and suggest a timeline for my day. Respond with all tasks properly categorized.",
                conversationHistory: conversationHistory,
                healthContext: healthContext,
                currentPlan: currentPlan
            )

            // Merge any final task updates
            for task in response.newTasks {
                if !currentPlan.tasks.contains(where: { $0.title.lowercased() == task.title.lowercased() }) {
                    currentPlan.tasks.append(task)
                }
            }
            if !response.suggestions.isEmpty {
                currentPlan.suggestions = response.suggestions
            }
        } catch {
            appLogger.notice("[Session] Finalize error (non-fatal): \(error.localizedDescription)")
        }

        // Sort tasks: high priority first, then medium, then low
        currentPlan.tasks.sort { task1, task2 in
            let order: [PlanTask.Priority] = [.high, .medium, .low]
            let i1 = order.firstIndex(of: task1.priority) ?? 2
            let i2 = order.firstIndex(of: task2.priority) ?? 2
            return i1 < i2
        }

        // Write finalized tasks to Google Calendar if connected
        if googleCalendarService.isConnected && !currentPlan.tasks.isEmpty {
            appLogger.notice("[Session] Writing \(self.currentPlan.tasks.count) events to Google Calendar")
            await googleCalendarService.createEvents(from: currentPlan.tasks)
        }

        state = .completed
        appLogger.notice("[Session] Plan finalized — \(self.currentPlan.tasks.count) tasks")
        onPlanFinalized?()
    }

    private func buildGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        if hour < 12 { timeGreeting = "Good morning" }
        else if hour < 17 { timeGreeting = "Good afternoon" }
        else { timeGreeting = "Good evening" }

        var greeting = "\(timeGreeting)!"

        // Build a spoken health briefing only when we have real data
        if let health = healthContext {
            let briefing = buildHealthBriefing(health)
            if let briefing {
                greeting += " Before we start — \(briefing)"
            } else {
                greeting += " I'm ready to help you plan your day."
            }
        } else {
            greeting += " I'm ready to help you plan your day."
        }

        greeting += " What's on your mind for today?"
        return greeting
    }

    /// Returns a 1-2 sentence spoken briefing if enough health data is available, otherwise nil.
    private func buildHealthBriefing(_ health: HealthContext) -> String? {
        var sentences: [String] = []

        // --- Recovery line (Whoop preferred, HealthKit HRV as fallback) ---
        if let score = health.whoopRecoveryScore {
            // Whoop recovery score — most actionable signal
            switch score {
            case 67...100:
                sentences.append("Your Whoop recovery is at \(score)% — you're well rested and ready to push today.")
            case 34..<67:
                let strain = health.whoopStrainScore.map { String(format: ", and yesterday's strain was %.1f", $0) } ?? ""
                sentences.append("Your Whoop recovery is \(score)%\(strain) — a balanced day is a good call.")
            default:
                sentences.append("Your Whoop recovery is low at \(score)% — keep today lighter and prioritise rest.")
            }
        } else if let hrv = health.hrvValue {
            // HealthKit HRV fallback
            let level = health.recoveryLevel
            let hrvStr = String(format: "%.0f", hrv)
            switch level {
            case .high:
                sentences.append("Your HRV is \(hrvStr) ms — looking well recovered.")
            case .moderate:
                sentences.append("Your HRV is \(hrvStr) ms — moderate recovery, so pace yourself.")
            case .low:
                sentences.append("Your HRV is on the lower side at \(hrvStr) ms — a lighter day might serve you better.")
            default:
                break
            }
        }

        // --- Sleep line (only add if we have it and it's notable) ---
        if let sleep = health.sleepDuration {
            let sleepStr = String(format: "%.1f", sleep)
            if sleep < 6 {
                sentences.append("You only got \(sleepStr) hours of sleep, so factor in some buffer time.")
            } else if let sp = health.whoopSleepPerformance, sp < 70 {
                sentences.append("Sleep performance was \(sp)% — not fully recharged, so plan accordingly.")
            }
            // Don't add a sleep line if everything looks good — no need to state the obvious
        }

        // Only return a briefing if we actually have something meaningful to say
        guard !sentences.isEmpty else { return nil }
        return sentences.joined(separator: " ")
    }
}

import Foundation

enum AIProvider: String, CaseIterable {
    case groq
    case openRouter

    var baseURL: String {
        switch self {
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .openRouter: return "https://openrouter.ai/api/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq: return "llama-3.3-70b-versatile"
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct:free"
        }
    }

    var label: String {
        switch self {
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        }
    }
}

final class AIService {
    private let groqKey: String
    private let openRouterKey: String

    init(groqKey: String, openRouterKey: String) {
        self.groqKey = groqKey
        self.openRouterKey = openRouterKey
    }

    func processTurn(
        transcript: String,
        conversationHistory: [ConversationMessage],
        healthContext: HealthContext?,
        currentPlan: DayPlan?
    ) async throws -> AIResponse {
        // Try Groq first (primary), fall back to OpenRouter
        do {
            return try await callProvider(
                .groq,
                apiKey: groqKey,
                transcript: transcript,
                conversationHistory: conversationHistory,
                healthContext: healthContext,
                currentPlan: currentPlan
            )
        } catch {
            print("[AIService] Groq failed: \(error.localizedDescription). Falling back to OpenRouter.")
            return try await callProvider(
                .openRouter,
                apiKey: openRouterKey,
                transcript: transcript,
                conversationHistory: conversationHistory,
                healthContext: healthContext,
                currentPlan: currentPlan
            )
        }
    }

    private func callProvider(
        _ provider: AIProvider,
        apiKey: String,
        transcript: String,
        conversationHistory: [ConversationMessage],
        healthContext: HealthContext?,
        currentPlan: DayPlan?
    ) async throws -> AIResponse {
        let systemPrompt = buildSystemPrompt(healthContext: healthContext, currentPlan: currentPlan)
        var messages = buildMessages(history: conversationHistory, latestTranscript: transcript)
        messages.insert(["role": "system", "content": systemPrompt], at: 0)

        let requestBody: [String: Any] = [
            "model": provider.defaultModel,
            "max_tokens": 1024,
            "messages": messages,
            "temperature": 0.7
        ]

        var request = URLRequest(url: URL(string: provider.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        if provider == .openRouter {
            request.setValue("PlanIt iOS", forHTTPHeaderField: "X-Title")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AIError.apiError(statusCode: statusCode, message: body)
        }

        let apiResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = apiResponse.choices.first?.message.content else {
            throw AIError.noContent
        }

        return parseResponse(content)
    }

    private func buildSystemPrompt(healthContext: HealthContext?, currentPlan: DayPlan?) -> String {
        var prompt = """
        You are PlanIt, a warm and efficient daily planning assistant. You help users plan their day through natural voice conversation.

        RULES:
        - Keep responses SHORT (2-3 sentences max) — the user is listening, not reading
        - Be conversational and friendly but focused
        - Ask clarifying questions one at a time
        - Extract tasks, priorities, and time estimates from what the user says
        - Suggest time blocks when you have enough information
        - If the user seems done, summarize the plan concisely

        HEALTH & RECOVERY RULES:
        - If recovery is LOW (Whoop < 34% or HRV < 30ms): proactively warn when the user adds intense workouts, back-to-back meetings, or late-night work. Suggest lighter alternatives or earlier sleep.
        - If recovery is MODERATE: gently suggest balancing intense tasks with breaks.
        - If recovery is HIGH: encourage the user to take on ambitious tasks.
        - Always factor in yesterday's strain when recommending today's workload.

        CALENDAR RULES:
        - If a task the user mentions conflicts with an existing calendar event, flag it immediately. Example: "You already have a meeting at 3pm — do you want to work around it or replace it?"
        - After the plan is finalised, the tasks will be automatically added to Google Calendar (tell the user this when wrapping up).
        - Suggest realistic time blocks based on existing calendar gaps.

        RESPONSE FORMAT:
        Always respond with ONLY a JSON object (no markdown, no code fences) containing:
        {
            "response_text": "Your spoken response to the user",
            "tasks": [{"title": "...", "duration": 30, "priority": "high|medium|low", "category": "deep_work|meeting|health|personal|errand|routine"}],
            "suggestions": ["optional suggestion strings"],
            "is_plan_complete": false
        }

        Only include tasks that are NEW or MODIFIED in this turn. Set is_plan_complete to true when the user indicates they're done planning.
        """

        if let health = healthContext {
            prompt += "\n\nUSER HEALTH & CALENDAR CONTEXT:\n\(health.summary)"
            switch health.recoveryLevel {
            case .low:
                prompt += "\n⚠️ RECOVERY IS LOW — warn the user if they add intense exercise, many meetings, or late work. Recommend prioritising rest and an early bedtime."
            case .moderate:
                prompt += "\nRecovery is moderate — suggest a balanced day with scheduled breaks."
            case .high:
                prompt += "\nRecovery is high — the user can handle a demanding day."
            case .unknown:
                break
            }
        }

        if let plan = currentPlan, !plan.tasks.isEmpty {
            let taskList = plan.tasks.map { "- \($0.title) (\($0.duration)min, \($0.priority.rawValue))" }.joined(separator: "\n")
            prompt += "\n\nCURRENT PLAN SO FAR:\n\(taskList)"
        }

        return prompt
    }

    private func buildMessages(history: [ConversationMessage], latestTranscript: String) -> [[String: String]] {
        var messages: [[String: String]] = []

        for msg in history.suffix(10) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }

        messages.append([
            "role": "user",
            "content": latestTranscript
        ])

        return messages
    }

    private func parseResponse(_ text: String) -> AIResponse {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as JSON directly
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONDecoder().decode(AIResponseJSON.self, from: data) {
            return buildResponse(from: json)
        }

        // Try to extract JSON from markdown code blocks
        if let jsonRange = cleaned.range(of: "```json"),
           let endRange = cleaned.range(of: "```", range: jsonRange.upperBound..<cleaned.endIndex) {
            let jsonString = String(cleaned[jsonRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONDecoder().decode(AIResponseJSON.self, from: data) {
                return buildResponse(from: json)
            }
        }

        // Try extracting JSON between first { and last }
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            let jsonString = String(cleaned[start...end])
            if let data = jsonString.data(using: .utf8),
               let json = try? JSONDecoder().decode(AIResponseJSON.self, from: data) {
                return buildResponse(from: json)
            }
        }

        // Fallback: treat entire text as response
        return AIResponse(
            responseText: text,
            newTasks: [],
            suggestions: [],
            isPlanComplete: false
        )
    }

    private func buildResponse(from json: AIResponseJSON) -> AIResponse {
        let tasks = json.tasks?.map { taskJSON in
            PlanTask(
                title: taskJSON.title,
                duration: taskJSON.duration ?? 30,
                priority: PlanTask.Priority(rawValue: taskJSON.priority ?? "medium") ?? .medium,
                category: PlanTask.Category(rawValue: taskJSON.category ?? "personal") ?? .personal
            )
        } ?? []

        return AIResponse(
            responseText: json.response_text,
            newTasks: tasks,
            suggestions: json.suggestions ?? [],
            isPlanComplete: json.is_plan_complete ?? false
        )
    }

    enum AIError: LocalizedError {
        case apiError(statusCode: Int, message: String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
            case .noContent: return "No content in AI response"
            }
        }
    }
}

// MARK: - Response Types

struct AIResponse {
    let responseText: String
    let newTasks: [PlanTask]
    let suggestions: [String]
    let isPlanComplete: Bool
}

// OpenAI-compatible response format (used by Groq and OpenRouter)
private struct OpenAIChatResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String?
    }
}

private struct AIResponseJSON: Codable {
    let response_text: String
    let tasks: [TaskJSON]?
    let suggestions: [String]?
    let is_plan_complete: Bool?
}

private struct TaskJSON: Codable {
    let title: String
    let duration: Int?
    let priority: String?
    let category: String?
}

import Foundation

struct HealthContext: Codable {

    // MARK: - Apple HealthKit / Watch
    var sleepDuration: Double?       // hours
    var sleepDeepHours: Double?      // hours of deep sleep
    var sleepREMHours: Double?       // hours of REM sleep
    var hrvValue: Double?            // ms (latest)
    var hrvWeekAverage: Double?      // ms (7-day avg)
    var restingHeartRate: Double?    // bpm
    var respiratoryRate: Double?     // breaths/min
    var vo2Max: Double?              // mL/kg/min
    var activeCaloriesBurned: Double? // kcal yesterday

    // MARK: - Whoop
    var whoopRecoveryScore: Int?     // 0–100 %
    var whoopStrainScore: Double?    // 0–21
    var whoopSleepPerformance: Int?  // 0–100 %
    var whoopHRV: Double?            // ms
    var whoopRHR: Double?            // bpm

    // MARK: - Google Calendar
    var todayEvents: [CalendarEvent]?
    var tomorrowEvents: [CalendarEvent]?

    // MARK: - Derived

    var recoveryLevel: RecoveryLevel {
        if let score = whoopRecoveryScore {
            if score >= 67 { return .high }
            if score >= 34 { return .moderate }
            return .low
        }
        guard let hrv = whoopHRV ?? hrvValue else { return .unknown }
        if hrv >= 50 { return .high }
        if hrv >= 30 { return .moderate }
        return .low
    }

    /// Rich text summary passed to the AI system prompt.
    var summary: String {
        var lines: [String] = []

        // Recovery — most important signal
        if let score = whoopRecoveryScore {
            lines.append("Whoop recovery score: \(score)% (\(recoveryLevel.label))")
        }
        if let strain = whoopStrainScore {
            lines.append(String(format: "Yesterday's Whoop strain: %.1f / 21", strain))
        }
        if let sp = whoopSleepPerformance {
            lines.append("Whoop sleep performance: \(sp)%")
        }

        // Sleep
        if let h = sleepDuration {
            var sleepLine = String(format: "Sleep: %.1f hrs total", h)
            if let deep = sleepDeepHours { sleepLine += String(format: " (%.1f deep", deep) }
            if let rem = sleepREMHours  { sleepLine += String(format: ", %.1f REM", rem) }
            if sleepDeepHours != nil || sleepREMHours != nil { sleepLine += ")" }
            lines.append(sleepLine)
        }

        // Cardiac
        let hrv = whoopHRV ?? hrvValue
        if let h = hrv {
            var hrvLine = String(format: "HRV: %.0f ms", h)
            if let avg = hrvWeekAverage { hrvLine += String(format: " (7-day avg %.0f ms)", avg) }
            lines.append(hrvLine)
        }
        let rhr = whoopRHR ?? restingHeartRate
        if let r = rhr { lines.append(String(format: "Resting HR: %.0f bpm", r)) }

        // Other fitness
        if let v = vo2Max { lines.append(String(format: "VO2 max: %.1f mL/kg/min", v)) }
        if let r = respiratoryRate { lines.append(String(format: "Respiratory rate: %.1f breaths/min", r)) }
        if let c = activeCaloriesBurned { lines.append(String(format: "Active calories yesterday: %.0f kcal", c)) }

        // Calendar
        if let events = todayEvents, !events.isEmpty {
            let list = events.map { $0.shortDescription }.joined(separator: "; ")
            lines.append("Today's existing calendar events: \(list)")
        }
        if let events = tomorrowEvents, !events.isEmpty {
            let list = events.map { $0.shortDescription }.joined(separator: "; ")
            lines.append("Tomorrow's existing calendar events: \(list)")
        }

        if lines.isEmpty { return "No health or calendar data available." }
        return lines.joined(separator: "\n")
    }

    enum RecoveryLevel: String, Codable {
        case high, moderate, low, unknown

        var label: String {
            switch self {
            case .high:     return "High — good day to push yourself"
            case .moderate: return "Moderate — balanced approach recommended"
            case .low:      return "Low — prioritise rest and light tasks"
            case .unknown:  return "Unknown"
            }
        }
    }
}

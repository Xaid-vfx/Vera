import Foundation

struct CalendarEvent: Identifiable, Codable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarName: String

    var durationMinutes: Int {
        max(0, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    var timeRangeString: String {
        if isAllDay { return "all day" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: startDate))–\(f.string(from: endDate))"
    }

    var shortDescription: String {
        isAllDay ? "\(title) (all day)" : "\(title) \(timeRangeString)"
    }
}

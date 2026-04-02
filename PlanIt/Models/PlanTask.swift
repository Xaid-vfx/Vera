import Foundation

struct PlanTask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var duration: Int // minutes
    var priority: Priority
    var scheduledTime: Date?
    var isCompleted: Bool
    var category: Category

    enum Priority: String, Codable, CaseIterable, Hashable {
        case high, medium, low

        var label: String {
            rawValue.capitalized
        }

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "blue"
            }
        }
    }

    enum Category: String, Codable, CaseIterable, Hashable {
        case deepWork = "deep_work"
        case meeting
        case health
        case personal
        case errand
        case routine

        var icon: String {
            switch self {
            case .deepWork: return "brain.head.profile"
            case .meeting: return "person.2"
            case .health: return "heart.fill"
            case .personal: return "person.fill"
            case .errand: return "cart"
            case .routine: return "arrow.clockwise"
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        duration: Int = 30,
        priority: Priority = .medium,
        scheduledTime: Date? = nil,
        isCompleted: Bool = false,
        category: Category = .personal
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.priority = priority
        self.scheduledTime = scheduledTime
        self.isCompleted = isCompleted
        self.category = category
    }
}

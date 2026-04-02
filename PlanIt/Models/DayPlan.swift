import Foundation

struct DayPlan: Codable {
    var tasks: [PlanTask]
    var timeBlocks: [TimeBlock]
    var suggestions: [String]
    let createdAt: Date

    struct TimeBlock: Identifiable, Codable, Hashable {
        let id: UUID
        var label: String
        var startTime: Date
        var endTime: Date
        var taskIds: [UUID]

        init(id: UUID = UUID(), label: String, startTime: Date, endTime: Date, taskIds: [UUID] = []) {
            self.id = id
            self.label = label
            self.startTime = startTime
            self.endTime = endTime
            self.taskIds = taskIds
        }
    }

    init(tasks: [PlanTask] = [], timeBlocks: [TimeBlock] = [], suggestions: [String] = []) {
        self.tasks = tasks
        self.timeBlocks = timeBlocks
        self.suggestions = suggestions
        self.createdAt = Date()
    }

    var highPriorityTasks: [PlanTask] {
        tasks.filter { $0.priority == .high }
    }

    var totalMinutes: Int {
        tasks.reduce(0) { $0 + $1.duration }
    }
}

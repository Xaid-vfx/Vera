import SwiftUI

struct TaskRowView: View {
    let task: PlanTask
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }

            // Category icon
            Image(systemName: task.category.icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            // Task details
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text("\(task.duration) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let time = task.scheduledTime {
                        Text(time, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Priority indicator
            Text(task.priority.label)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(priorityColor.opacity(0.15))
                .foregroundStyle(priorityColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(PlatformColor.systemBackground))
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

import SwiftUI

struct PlanResultView: View {
    @EnvironmentObject var viewModel: SessionViewModel

    var plan: DayPlan {
        viewModel.sessionManager.currentPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Plan")
                        .font(.largeTitle.bold())

                    HStack(spacing: 16) {
                        Label("\(plan.tasks.count) tasks", systemImage: "checklist")
                        Label("\(plan.totalMinutes) min", systemImage: "clock")
                        Label("\(plan.highPriorityTasks.count) priority", systemImage: "exclamationmark.triangle")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Suggestions
                if !plan.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(.headline)

                        ForEach(plan.suggestions, id: \.self) { suggestion in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(suggestion)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Tasks grouped by priority
                ForEach(PlanTask.Priority.allCases, id: \.self) { priority in
                    let tasks = plan.tasks.filter { $0.priority == priority }
                    if !tasks.isEmpty {
                        Section {
                            ForEach(tasks) { task in
                                TaskRowView(task: task) {
                                    viewModel.toggleTask(task)
                                }
                            }
                        } header: {
                            HStack {
                                Circle()
                                    .fill(colorForPriority(priority))
                                    .frame(width: 8, height: 8)
                                Text("\(priority.label) Priority")
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func colorForPriority(_ priority: PlanTask.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

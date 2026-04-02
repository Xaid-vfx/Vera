import SwiftUI

struct VoiceSessionView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // Background
            Color(PlatformColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("End") {
                        viewModel.endSession()
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(.red)

                    Spacer()

                    Text(viewModel.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut, value: viewModel.sessionManager.state)

                    Spacer()

                    // Task count badge
                    if !viewModel.sessionManager.currentPlan.tasks.isEmpty {
                        Text("\(viewModel.sessionManager.currentPlan.tasks.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding()

                Spacer()

                // Central visualization
                VStack(spacing: 24) {
                    // Animated waveform indicator
                    WaveformView(state: viewModel.sessionManager.state)
                        .frame(height: 120)

                    if viewModel.sessionManager.state == .creatingPlan {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Creating your plan...")
                                .font(.headline)
                                .foregroundStyle(.purple)
                        }
                        .transition(.opacity)
                    } else if !viewModel.sessionManager.liveTranscript.isEmpty {
                        // Live transcript
                        Text(viewModel.sessionManager.liveTranscript)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    }
                }

                Spacer()

                // Conversation feed (last few messages)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.sessionManager.conversationHistory.suffix(6)) { message in
                            ConversationBubble(message: message)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 200)

                // Live task list preview
                if !viewModel.sessionManager.currentPlan.tasks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.sessionManager.currentPlan.tasks) { task in
                                TaskChip(task: task)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                }

                // Error display
                if let error = viewModel.sessionManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    let state: VoiceSessionManager.SessionState
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorForState)
                    .frame(width: 6, height: heightForBar(index: index))
                    .animation(
                        .easeInOut(duration: 0.4 + Double(index) * 0.1)
                        .repeatForever(autoreverses: true),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onChange(of: state) { _, _ in animating.toggle() }
    }

    private var colorForState: Color {
        switch state {
        case .listening: return .blue
        case .processing: return .orange
        case .speaking: return .green
        case .creatingPlan: return .purple
        default: return .gray
        }
    }

    private func heightForBar(index: Int) -> CGFloat {
        let isActive = state == .listening || state == .speaking || state == .creatingPlan
        let baseHeight: CGFloat = isActive ? 20 : 8
        let variation: CGFloat = animating ? CGFloat(index % 3 + 1) * 15 : 0
        return baseHeight + variation
    }
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            Text(message.content)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Color.blue : Color(PlatformColor.systemGray5))
                .foregroundColor(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Task Chip

struct TaskChip: View {
    let task: PlanTask

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: task.category.icon)
                .font(.caption2)
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
            Text("\(task.duration)m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var chipColor: Color {
        switch task.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }
}

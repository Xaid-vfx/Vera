import SwiftUI

struct OnboardingView: View {
    @ObservedObject var whoopService: WhoopService
    @ObservedObject var googleCalendarService: GoogleCalendarService
    let onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WelcomePage()
                .tag(0)

            WhoopPage(whoopService: whoopService)
                .tag(1)

            CalendarPage(googleCalendarService: googleCalendarService)
                .tag(2)

            ReadyPage(
                whoopConnected: whoopService.isConnected,
                calendarConnected: googleCalendarService.isConnected,
                onComplete: onComplete
            )
            .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .animation(.easeInOut, value: page)
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    @State private var animating = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 160, height: 160)
                    .scaleEffect(animating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animating)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 12) {
                Text("Meet PlanIt")
                    .font(.largeTitle.bold())

                Text("Your voice-first daily planner.\nJust talk — PlanIt listens, learns your health data, and builds your day.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "mic.circle.fill",  color: .blue,   text: "Speak your plan naturally")
                FeatureRow(icon: "heart.circle.fill", color: .red,    text: "Adapts to your recovery and sleep")
                FeatureRow(icon: "calendar.circle.fill", color: .green, text: "Reads and writes your calendar")
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("Swipe to set up →")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 48)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Page 2: Whoop

private struct WhoopPage: View {
    @ObservedObject var whoopService: WhoopService

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("Connect Whoop")
                    .font(.title.bold())

                Text("PlanIt reads your recovery score, HRV, strain, and sleep quality so it can warn you before you overdo it.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 12) {
                BulletRow(text: "Recovery score tells us how hard you can push today")
                BulletRow(text: "High strain yesterday → lighter day suggested")
                BulletRow(text: "Poor sleep → earlier bedtime recommended")
            }
            .padding(.horizontal, 40)

            if whoopService.isConnected {
                ConnectedBadge(label: "Whoop connected")
            } else {
                VStack(spacing: 12) {
                    Button {
                        Task { await whoopService.connect() }
                    } label: {
                        if whoopService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Label("Connect Whoop", systemImage: "link")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .font(.headline)
                        }
                    }
                    .disabled(whoopService.isLoading)

                    Text("You'll log in to your Whoop account — PlanIt never sees your password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }

            if let err = whoopService.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Text("Don't have Whoop? Swipe to skip →")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - Page 3: Google Calendar

private struct CalendarPage: View {
    @ObservedObject var googleCalendarService: GoogleCalendarService

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "calendar.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text("Connect Calendar")
                    .font(.title.bold())

                Text("PlanIt reads your existing events so it can warn about conflicts, and adds your finished plan as calendar blocks.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(alignment: .leading, spacing: 12) {
                BulletRow(text: "\"You already have a meeting at 3pm — conflict?\"")
                BulletRow(text: "Suggests free time slots as you plan")
                BulletRow(text: "Writes your finalized plan to Google Calendar")
            }
            .padding(.horizontal, 40)

            if googleCalendarService.isConnected {
                ConnectedBadge(label: "Google Calendar connected")
            } else {
                VStack(spacing: 12) {
                    Button {
                        Task { await googleCalendarService.connect() }
                    } label: {
                        if googleCalendarService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        } else {
                            Label("Connect Google Calendar", systemImage: "link")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .font(.headline)
                        }
                    }
                    .disabled(googleCalendarService.isLoading)

                    Text("You'll sign in to Google — PlanIt only accesses calendar events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            }

            if let err = googleCalendarService.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Text("No Google Calendar? Swipe to skip →")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - Page 4: Ready

private struct ReadyPage: View {
    let whoopConnected: Bool
    let calendarConnected: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("You're all set")
                    .font(.largeTitle.bold())

                Text("PlanIt is ready. Tap the mic and start talking — your plan will come together naturally.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                StatusRow(label: "Apple Health",     connected: true)
                StatusRow(label: "Whoop",            connected: whoopConnected)
                StatusRow(label: "Google Calendar",  connected: calendarConnected)
            }
            .padding(.horizontal, 40)

            if !whoopConnected || !calendarConnected {
                Text("You can connect the rest later from Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                onComplete()
            } label: {
                Text("Start Planning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Reusable components

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct ConnectedBadge: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(label).font(.subheadline.bold())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }
}

private struct StatusRow: View {
    let label: String
    let connected: Bool

    var body: some View {
        HStack {
            Image(systemName: connected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(connected ? .green : .secondary)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(connected ? "Connected" : "Not connected")
                .font(.caption)
                .foregroundStyle(connected ? .green : .secondary)
        }
    }
}

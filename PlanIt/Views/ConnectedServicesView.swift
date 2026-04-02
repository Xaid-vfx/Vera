import SwiftUI

/// Dedicated screen for managing third-party integrations.
struct ConnectedServicesView: View {
    @ObservedObject var whoopService: WhoopService
    @ObservedObject var googleCalendarService: GoogleCalendarService

    var body: some View {
        List {
            // ── Apple Health ────────────────────────────────────────────
            Section {
                ServiceRow(
                    icon: "heart.fill",
                    iconColor: .red,
                    name: "Apple Health",
                    subtitle: "Steps, HRV, resting heart rate, sleep",
                    isConnected: true, // always available — HealthKit permission handled at session start
                    isLoading: false,
                    errorMessage: nil,
                    onConnect: nil,   // permissions requested automatically
                    onDisconnect: nil // can't revoke from inside the app
                )
                Text("Health data permissions are managed in the iOS Settings app under Health → Data Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Health")
            }

            // ── Whoop ───────────────────────────────────────────────────
            Section {
                ServiceRow(
                    icon: "bolt.heart.fill",
                    iconColor: .green,
                    name: "Whoop",
                    subtitle: "Recovery score, strain, HRV, sleep performance",
                    isConnected: whoopService.isConnected,
                    isLoading: whoopService.isLoading,
                    errorMessage: whoopService.error,
                    onConnect: { Task { await whoopService.connect() } },
                    onDisconnect: { whoopService.disconnect() }
                )
            } header: {
                Text("Wearables")
            }

            // ── Google Calendar ─────────────────────────────────────────
            Section {
                ServiceRow(
                    icon: "calendar",
                    iconColor: .blue,
                    name: "Google Calendar",
                    subtitle: "Read today's events · Write finalized plan",
                    isConnected: googleCalendarService.isConnected,
                    isLoading: googleCalendarService.isLoading,
                    errorMessage: googleCalendarService.error,
                    onConnect: { Task { await googleCalendarService.connect() } },
                    onDisconnect: { googleCalendarService.disconnect() }
                )
            } header: {
                Text("Calendar")
            }
        }
        .navigationTitle("Connected Apps")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Reusable service row

private struct ServiceRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let subtitle: String
    let isConnected: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onConnect: (() -> Void)?
    let onDisconnect: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Service icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status badge
                if isLoading {
                    ProgressView().frame(width: 28)
                } else if isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }

            // Error banner
            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Action button
            if !isLoading {
                if isConnected {
                    if let onDisconnect {
                        Button(role: .destructive) {
                            onDisconnect()
                        } label: {
                            Label("Disconnect", systemImage: "minus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                } else {
                    if let onConnect {
                        Button {
                            onConnect()
                        } label: {
                            Label("Connect", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

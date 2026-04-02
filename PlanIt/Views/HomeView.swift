import SwiftUI
import AppIntents

struct HomeView: View {
    @EnvironmentObject var viewModel: SessionViewModel
    @State private var showSettings = false
    @State private var groqKeyInput = ""
    @State private var openRouterKeyInput = ""
    @AppStorage("siriTipVisible") private var siriTipVisible = true

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(PlatformColor.systemBackground), Color.blue.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo / Title
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.blue)

                    Text("PlanIt")
                        .font(.largeTitle.bold())

                    Text("Plan your day with your voice")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Current plan summary (if exists)
                if !viewModel.sessionManager.currentPlan.tasks.isEmpty {
                    NavigationLink {
                        PlanResultView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Today's Plan")
                                    .font(.headline)
                                Text("\(viewModel.sessionManager.currentPlan.tasks.count) tasks, \(viewModel.sessionManager.currentPlan.totalMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Start button
                Button {
                    if viewModel.sessionManager.state == .idle || viewModel.sessionManager.state == .completed {
                        viewModel.startSession()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 88, height: 88)
                            .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                }

                Text("Tap to start planning")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Siri shortcut tip — dismissed by user tapping X, remembered across launches
                if siriTipVisible {
                    SiriTipView(intent: StartPlanningIntent(), isVisible: $siriTipVisible)
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: .init(
            get: { viewModel.isSessionActive },
            set: { if !$0 { viewModel.endSession() } }
        )) {
            VoiceSessionView()
                .environmentObject(viewModel)
        }
        #else
        .sheet(isPresented: .init(
            get: { viewModel.isSessionActive },
            set: { if !$0 { viewModel.endSession() } }
        )) {
            VoiceSessionView()
                .environmentObject(viewModel)
                .frame(minWidth: 500, minHeight: 600)
        }
        #endif
        .sheet(isPresented: $viewModel.showPlanResult) {
            NavigationStack {
                PlanResultView()
                    .environmentObject(viewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    groqKeyInput = viewModel.savedGroqKey
                    openRouterKeyInput = viewModel.savedOpenRouterKey
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                groqKey: $groqKeyInput,
                openRouterKey: $openRouterKeyInput,
                ttsService: viewModel.sessionManager.ttsService,
                whoopService: viewModel.sessionManager.whoopService,
                googleCalendarService: viewModel.sessionManager.googleCalendarService,
                onSave: {
                    viewModel.updateKeys(groqKey: groqKeyInput, openRouterKey: openRouterKeyInput)
                    showSettings = false
                },
                onCancel: {
                    showSettings = false
                }
            )
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Binding var groqKey: String
    @Binding var openRouterKey: String
    @ObservedObject var ttsService: TextToSpeechService
    @ObservedObject var whoopService: WhoopService
    @ObservedObject var googleCalendarService: GoogleCalendarService
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var selectedVoiceId: String = ""
    @State private var availableVoices: [(name: String, identifier: String, quality: String)] = []
    @State private var whoopClientId: String = ""
    @State private var whoopClientSecret: String = ""
    @State private var googleClientId: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Voice", selection: $selectedVoiceId) {
                        ForEach(availableVoices, id: \.identifier) { voice in
                            Text(voice.name).tag(voice.identifier)
                        }
                    }
                    .onChange(of: selectedVoiceId) { _, newValue in
                        ttsService.setVoice(identifier: newValue)
                    }

                    Button("Preview Voice") {
                        ttsService.speak("Hi! I'm ready to help you plan your day. What's on your mind?")
                    }

                    Text("Download premium voices in System Settings > Accessibility > Spoken Content > Manage Voices for the best quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Assistant Voice")
                }

                Section {
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Primary")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    Text("Groq (llama-3.3-70b-versatile)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Groq API Key", text: $groqKey)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Groq")
                }

                Section {
                    HStack(spacing: 8) {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                        Text("Fallback")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Text("OpenRouter (llama-3.3-70b-instruct:free)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("OpenRouter API Key", text: $openRouterKey)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("OpenRouter")
                }

                // MARK: Whoop
                Section {
                    if whoopService.isConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Whoop connected")
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                whoopService.disconnect()
                            }
                            .font(.caption)
                        }
                    } else {
                        SecureField("Client ID", text: $whoopClientId)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        SecureField("Client Secret", text: $whoopClientSecret)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        Button {
                            whoopService.clientId     = whoopClientId
                            whoopService.clientSecret = whoopClientSecret
                            Task { await whoopService.connect() }
                        } label: {
                            if whoopService.isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Connect Whoop").frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(whoopClientId.isEmpty || whoopClientSecret.isEmpty || whoopService.isLoading)
                    }
                    if let err = whoopService.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Text("Get credentials at developer.whoop.com — enables recovery score, HRV, strain, and sleep performance in your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Whoop")
                }

                // MARK: Google Calendar
                Section {
                    if googleCalendarService.isConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Google Calendar connected")
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                googleCalendarService.disconnect()
                            }
                            .font(.caption)
                        }
                    } else {
                        SecureField("OAuth Client ID", text: $googleClientId)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        Button {
                            googleCalendarService.clientId = googleClientId
                            Task { await googleCalendarService.connect() }
                        } label: {
                            if googleCalendarService.isLoading {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Connect Google Calendar").frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(googleClientId.isEmpty || googleCalendarService.isLoading)
                    }
                    if let err = googleCalendarService.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Text("Get an OAuth 2.0 Client ID from console.cloud.google.com — enables reading today's events and writing your plan to your calendar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Google Calendar")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .bold()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            availableVoices = TextToSpeechService.availableVoices()
            if let saved = UserDefaults.standard.string(forKey: "tts_voice_identifier") {
                selectedVoiceId = saved
            } else if let current = availableVoices.first {
                selectedVoiceId = current.identifier
            }
        }
    }
}

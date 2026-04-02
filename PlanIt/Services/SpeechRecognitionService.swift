import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?

    /// Set to true when startListening() was called but recognizer wasn't ready yet.
    private var pendingListenStart = false

    private var silenceTimer: Timer?
    private var lastTranscriptLength: Int = 0
    private var lastTextChangeTime: Date = Date()

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self
    }

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            appLogger.notice("[STT] Recognizer availability changed: \(available)")
            if available && self.pendingListenStart {
                self.pendingListenStart = false
                try? self.startListening()
            }
        }
    }

    /// How long to wait after speech stops before completing the turn.
    /// Dynamically adjusted based on how much the user has said.
    private var silenceThreshold: TimeInterval {
        let wordCount = transcript.split(separator: " ").count
        // Short utterances (< 5 words): wait 3.5s — user likely has more to say
        // Medium (5-20 words): wait 2.5s
        // Long (20+ words): wait 2.0s — user likely finished a full thought
        if wordCount < 5 { return 3.5 }
        if wordCount < 20 { return 2.5 }
        return 2.0
    }

    var onPartialResult: ((String) -> Void)?
    var onTurnComplete: ((String) -> Void)?
    /// Fires when new speech is detected (used for TTS interruption)
    var onSpeechDetected: (() -> Void)?

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() throws {
        appLogger.notice("[STT] startListening called, recognizer available: \(self.speechRecognizer?.isAvailable ?? false)")
        guard let speechRecognizer else {
            appLogger.notice("[STT] Recognizer nil — throwing")
            throw SpeechError.recognizerUnavailable
        }

        // Don't gate on isAvailable — it stays false on many simulators even when
        // recognition works fine. Just start and let the task fail/succeed naturally.
        pendingListenStart = false
        stopListening()

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        appLogger.notice("[STT] Configuring audio session")
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        appLogger.notice("[STT] Audio session active")
        #endif

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        lastTranscriptLength = 0
        lastTextChangeTime = Date()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    self.onPartialResult?(text)

                    // Only reset silence timer when NEW text arrives
                    if text.count != self.lastTranscriptLength {
                        let wasEmpty = self.lastTranscriptLength == 0
                        self.lastTranscriptLength = text.count
                        self.lastTextChangeTime = Date()
                        self.resetSilenceTimer()

                        // Notify that user started speaking (for TTS interruption).
                        // Require ≥2 words to avoid triggering on single-word noise hits.
                        if wasEmpty {
                            let wordCount = text.split(separator: " ").count
                            if wordCount >= 2 {
                                self.onSpeechDetected?()
                            }
                        }
                    }

                    // If the recognition result is final, treat as turn complete
                    if result.isFinal {
                        self.silenceTimer?.invalidate()
                        self.onTurnComplete?(text)
                    }
                }

                if let error {
                    if (error as NSError).code != 216 {
                        self.error = error.localizedDescription
                        appLogger.notice("[STT] Error: \(error.localizedDescription)")
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isListening = true
        self.transcript = ""
        self.error = nil
        appLogger.notice("[STT] Started listening")
    }

    func stopListening() {
        pendingListenStart = false
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        lastTranscriptLength = 0
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        let threshold = self.silenceThreshold
        silenceTimer = Timer.scheduledTimer(withTimeInterval: threshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.transcript.isEmpty else { return }

                let wordCount = self.transcript.split(separator: " ").count
                appLogger.notice("[STT] Silence detected after \(threshold)s, \(wordCount) words — completing turn")
                self.onTurnComplete?(self.transcript)
            }
        }
    }

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "Speech recognizer is not available"
            case .notAuthorized: return "Speech recognition not authorized"
            }
        }
    }
}

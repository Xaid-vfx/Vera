import Foundation
import AVFoundation

@MainActor
final class TextToSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false
    @Published var currentVoiceName: String = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var selectedVoice: AVSpeechSynthesisVoice?

    var onFinishedSpeaking: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        selectedVoice = Self.bestAvailableVoice()
        currentVoiceName = selectedVoice?.name ?? "System Default"
        appLogger.notice("[TTS] Selected voice: \(self.currentVoiceName)")
    }

    /// Picks the best English voice available, preferring premium > enhanced > compact.
    /// Prefers natural-sounding female voices for a friendly assistant feel.
    static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let allEnglish = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en-US") || $0.language.starts(with: "en-GB") }

        // Preferred voice names in order (these sound the most natural as assistants)
        let preferred = ["Zoe", "Samantha", "Ava", "Allison", "Susan", "Siri", "Karen", "Moira"]

        // Try premium first, then enhanced, then default
        for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced, .default] {
            let voicesAtQuality = allEnglish.filter { $0.quality == quality }
            // Try preferred names first
            for name in preferred {
                if let voice = voicesAtQuality.first(where: { $0.name == name }) {
                    return voice
                }
            }
            // Fall back to any voice at this quality
            if let voice = voicesAtQuality.first {
                return voice
            }
        }

        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Returns all available English voices grouped by quality for the settings UI.
    static func availableVoices() -> [(name: String, identifier: String, quality: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .filter { !$0.identifier.contains("speech.synthesis.voice") } // Skip novelty voices
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .map { voice in
                let qualityLabel: String
                switch voice.quality {
                case .premium: qualityLabel = "Premium"
                case .enhanced: qualityLabel = "Enhanced"
                default: qualityLabel = "Standard"
                }
                return (name: "\(voice.name) (\(qualityLabel))", identifier: voice.identifier, quality: qualityLabel)
            }
    }

    func setVoice(identifier: String) {
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            selectedVoice = voice
            currentVoiceName = voice.name
            UserDefaults.standard.set(identifier, forKey: "tts_voice_identifier")
            appLogger.notice("[TTS] Voice changed to: \(voice.name)")
        }
    }

    func loadSavedVoice() {
        if let savedId = UserDefaults.standard.string(forKey: "tts_voice_identifier"),
           let voice = AVSpeechSynthesisVoice(identifier: savedId) {
            selectedVoice = voice
            currentVoiceName = voice.name
        }
    }

    func speak(_ text: String) {
        stop()

        // Break text into sentences for more natural pacing
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "en-US")

        // Tune for natural conversational speech
        let isPremium = selectedVoice?.quality == .premium || selectedVoice?.quality == .enhanced
        if isPremium {
            // Premium voices sound best near default rate
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
        } else {
            // Standard voices need slight tweaks to sound less robotic
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92 // Slightly slower
            utterance.pitchMultiplier = 1.05 // Slightly higher pitch for warmth
        }

        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.0
        utterance.volume = 0.9

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    var isCurrentlySpeaking: Bool {
        synthesizer.isSpeaking
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.onFinishedSpeaking?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
        }
    }
}

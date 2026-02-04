import Foundation
import AVFoundation
import Combine

/// 音声読み上げ管理クラス
class TextToSpeechManager: NSObject, ObservableObject {
    static let shared = TextToSpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    // 状態
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentText = ""
    @Published var progress: Float = 0  // 0.0 - 1.0

    // 設定（自然な読み上げのため調整）
    // デフォルト速度は速すぎるため、0.45-0.5が自然な速度
    @Published var speechRate: Float = 0.48
    @Published var speechPitch: Float = 1.0
    @Published var speechVolume: Float = 1.0

    // 利用可能な音声のキャッシュ
    private var cachedJapaneseVoice: AVSpeechSynthesisVoice?
    private var cachedEnglishVoice: AVSpeechSynthesisVoice?

    private var totalCharacters: Int = 0
    private var spokenCharacters: Int = 0

    private override init() {
        super.init()
        synthesizer.delegate = self
        // 起動時に最適な音声を検索してキャッシュ
        cacheOptimalVoices()
    }

    /// 利用可能な最高品質の音声を検索してキャッシュ
    private func cacheOptimalVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        // 日本語音声を品質順に検索
        cachedJapaneseVoice = findBestVoice(voices: allVoices, language: "ja-JP")

        // 英語音声を品質順に検索
        cachedEnglishVoice = findBestVoice(voices: allVoices, language: "en-US")

        // デバッグログ
        if let jpVoice = cachedJapaneseVoice {
            print("TextToSpeech: Japanese voice: \(jpVoice.name) (quality: \(jpVoice.quality.rawValue))")
        }
        if let enVoice = cachedEnglishVoice {
            print("TextToSpeech: English voice: \(enVoice.name) (quality: \(enVoice.quality.rawValue))")
        }
    }

    /// 指定言語で最も品質の高い音声を検索
    private func findBestVoice(voices: [AVSpeechSynthesisVoice], language: String) -> AVSpeechSynthesisVoice? {
        let languageVoices = voices.filter { $0.language.hasPrefix(language.prefix(2).lowercased()) }

        // 品質順にソート（premium > enhanced > default > compact）
        // quality: 0 = default, 1 = enhanced, 2 = premium
        let sortedVoices = languageVoices.sorted { $0.quality.rawValue > $1.quality.rawValue }

        // 最も品質の高い音声を返す
        return sortedVoices.first
    }

    /// 利用可能な音声一覧を取得（デバッグ用）
    func getAvailableVoices() -> [(name: String, language: String, quality: String)] {
        return AVSpeechSynthesisVoice.speechVoices().map { voice in
            let qualityName: String
            switch voice.quality {
            case .default: qualityName = "Default"
            case .enhanced: qualityName = "Enhanced"
            case .premium: qualityName = "Premium"
            @unknown default: qualityName = "Unknown"
            }
            return (voice.name, voice.language, qualityName)
        }
    }

    // MARK: - Public Methods

    /// テキストを音声で読み上げる
    func speak(text: String) {
        // 既存の読み上げを停止
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        guard !text.isEmpty else {
            print("TextToSpeech: Empty text, skipping")
            return
        }

        currentText = text
        totalCharacters = text.count
        spokenCharacters = 0
        progress = 0

        let utterance = AVSpeechUtterance(string: text)

        // 言語を自動検出（日本語優先）
        utterance.voice = detectVoice(for: text)

        // 読み上げ設定
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume

        // iOS 16+では前後の無音を調整可能
        if #available(iOS 16.0, *) {
            utterance.prefersAssistiveTechnologySettings = false
        }

        isSpeaking = true
        isPaused = false

        synthesizer.speak(utterance)
        print("TextToSpeech: Started speaking \(text.count) characters")
    }

    /// 読み上げを一時停止
    func pause() {
        if synthesizer.isSpeaking && !isPaused {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            print("TextToSpeech: Paused")
        }
    }

    /// 読み上げを再開
    func resume() {
        if isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            print("TextToSpeech: Resumed")
        }
    }

    /// 読み上げを停止
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        progress = 0
        currentText = ""
        print("TextToSpeech: Stopped")
    }

    /// 一時停止/再開をトグル
    func togglePause() {
        if isPaused {
            resume()
        } else {
            pause()
        }
    }

    // MARK: - Private Methods

    /// テキストの言語を判定して適切な音声を選択
    private func detectVoice(for text: String) -> AVSpeechSynthesisVoice? {
        // 日本語の文字が含まれているかチェック
        let japaneseRange = text.range(of: "\\p{Script=Han}|\\p{Script=Hiragana}|\\p{Script=Katakana}", options: .regularExpression)

        if japaneseRange != nil {
            // キャッシュした日本語音声を使用
            if let voice = cachedJapaneseVoice {
                return voice
            }
            // フォールバック
            return AVSpeechSynthesisVoice(language: "ja-JP")
        } else {
            // キャッシュした英語音声を使用
            if let voice = cachedEnglishVoice {
                return voice
            }
            // フォールバック
            return AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    /// 拡張音声が利用可能かどうかをチェック
    var hasEnhancedJapaneseVoice: Bool {
        cachedJapaneseVoice?.quality.rawValue ?? 0 >= 1
    }

    var hasEnhancedEnglishVoice: Bool {
        cachedEnglishVoice?.quality.rawValue ?? 0 >= 1
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 1.0
            print("TextToSpeech: Finished")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.progress = 0
            print("TextToSpeech: Cancelled")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.spokenCharacters = characterRange.location + characterRange.length
            if self.totalCharacters > 0 {
                self.progress = Float(self.spokenCharacters) / Float(self.totalCharacters)
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = false
        }
    }
}

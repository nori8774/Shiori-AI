import Foundation
import SwiftUI
import Combine

/// AI機能使用時のデータ送信同意を管理するクラス
/// App Store審査ガイドライン 5.1.1/5.1.2 対応
class AIConsentManager: ObservableObject {
    static let shared = AIConsentManager()

    private let consentKey = "ai_data_sharing_consent"
    private let consentDateKey = "ai_data_sharing_consent_date"

    /// ユーザーがAIデータ共有に同意しているか
    @Published private(set) var hasConsent: Bool

    /// 同意した日時
    var consentDate: Date? {
        UserDefaults.standard.object(forKey: consentDateKey) as? Date
    }

    private init() {
        self.hasConsent = UserDefaults.standard.bool(forKey: consentKey)
    }

    /// 同意状態を更新（内部用）
    private func setConsent(_ value: Bool) {
        print("AIConsentManager: setConsent(\(value)) called")
        hasConsent = value
        UserDefaults.standard.set(value, forKey: consentKey)
        UserDefaults.standard.synchronize() // 即座に保存
        if value {
            UserDefaults.standard.set(Date(), forKey: consentDateKey)
        }
        print("AIConsentManager: hasConsent is now \(hasConsent)")
    }

    /// 同意を記録
    func grantConsent() {
        print("AIConsentManager: grantConsent() called")
        setConsent(true)
    }

    /// 同意を取り消し
    func revokeConsent() {
        setConsent(false)
        UserDefaults.standard.removeObject(forKey: consentDateKey)
    }

    /// AI機能を使用可能かチェック
    /// - Returns: 同意済みかつAPIキー設定済みの場合true
    func canUseAIFeatures() -> Bool {
        guard hasConsent else { return false }

        // APIキーが設定されているか確認
        guard let data = KeychainHelper.standard.read(
            service: "com.myapp.gemini",
            account: "gemini_api_key"
        ), !data.isEmpty else {
            return false
        }

        return true
    }

    /// 同意が必要な場合にtrueを返す
    func needsConsent() -> Bool {
        return !hasConsent
    }
}

// MARK: - 送信データの説明テキスト

extension AIConsentManager {

    /// 同意ダイアログに表示するデータ送信説明
    static let dataExplanationJapanese = """
    このアプリのAI機能を使用すると、以下のデータがGoogle Gemini APIに送信されます：

    📄 PDFページの画像
    • 翻訳・要約・音声読み上げ時に送信
    • OCR（文字認識）処理に使用

    📝 テキストデータ
    • しおり検索のインデックス作成時に送信
    • ベクトル化（意味検索用）に使用

    これらのデータはAI処理のためにのみ使用され、アプリ開発者がアクセスすることはありません。

    詳細はプライバシーポリシーをご確認ください。
    """

    static let dataExplanationEnglish = """
    When using AI features in this app, the following data is sent to Google Gemini API:

    📄 PDF Page Images
    • Sent during translation, summarization, and text-to-speech
    • Used for OCR (text recognition) processing

    📝 Text Data
    • Sent when creating bookmark search indexes
    • Used for vectorization (semantic search)

    This data is used solely for AI processing and is not accessed by the app developer.

    Please see our Privacy Policy for details.
    """

    /// システム言語に応じた説明テキストを返す
    static var localizedDataExplanation: String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        return languageCode == "ja" ? dataExplanationJapanese : dataExplanationEnglish
    }
}

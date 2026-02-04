import Foundation
import UIKit
import GoogleGenerativeAI

// AIからの返答データ
struct AIResponse: Codable {
    let rawText: String // 原文
    let summary: String // 要約（または回答結果）
    
    enum CodingKeys: String, CodingKey {
        case rawText
        case summary
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawText = try container.decode(String.self, forKey: .rawText)
        
        if let stringSummary = try? container.decode(String.self, forKey: .summary) {
            self.summary = stringSummary
        } else if let arraySummary = try? container.decode([String].self, forKey: .summary) {
            self.summary = arraySummary.map { "• " + $0 }.joined(separator: "\n")
        } else {
            self.summary = "回答の取得に失敗しました"
        }
    }
    
    init(rawText: String, summary: String) {
        self.rawText = rawText
        self.summary = summary
    }
}

class GeminiService {
    static let shared = GeminiService()

    private init() {}

    // MARK: - 検索用要約生成

    /// しおりページの検索用要約を生成（マーカーテキストを優先）
    func generateSearchSummary(rawText: String, markerTexts: [String]?) async throws -> String {
        guard let data = KeychainHelper.standard.read(service: "com.myapp.gemini", account: "gemini_api_key"),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません。"])
        }

        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)

        var markerSection = ""
        if let markers = markerTexts, !markers.isEmpty {
            markerSection = """

            【マーカー部分（優先してください）】
            \(markers.joined(separator: "\n"))
            """
        }

        let prompt = """
        以下のテキストから、セマンティック検索用のインデックステキストを作成してください。

        【出力形式】
        1行目: このページの主題を1文で（例：「○○の仕組みについて説明している」）
        2行目: 重要なキーワードを5-10個、カンマ区切りで列挙
        3行目: ユーザーが検索しそうな質問形式（例：「○○とは何か」「○○の方法」）
        \(markerSection)

        【ページ全文】
        \(rawText.prefix(3000))
        """

        let response = try await model.generateContent(prompt)

        guard let text = response.text else {
            throw NSError(domain: "GeminiError", code: 500, userInfo: [NSLocalizedDescriptionKey: "AIからの応答が空でした"])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 【変更】instruction（指示）を受け取れるように修正
    // デフォルト値は「要約」にしておく
    func analyzePage(image: UIImage, instruction: String = "この内容の要点を3つ箇条書きでまとめてください") async throws -> AIResponse {
        
        guard let data = KeychainHelper.standard.read(service: "com.myapp.gemini", account: "gemini_api_key"),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GeminiService", code: 401, userInfo: [NSLocalizedDescriptionKey: "APIキーが設定されていません。"])
        }
        
        // Gemini 2.5 Flash を使用
        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)
        
        // 【変更】プロンプトに動的な指示(instruction)を埋め込む
        let prompt = """
        あなたは優秀なアシスタントです。添付された画像のテキストを読み取り、以下の指示に従ってJSON形式で出力してください。
        
        ■ あなたへの指示:
        \(instruction)
        
        ■ 制約条件:
        1. "rawText" には、読み取った画像の全文を格納してください。
        2. "summary" には、上記の指示に対するあなたの回答（要約、翻訳、回答など）を格納してください。
        3. 出力は純粋なJSONのみを返してください。
        
        ■ 出力フォーマット:
        {
            "rawText": "...",
            "summary": "..."
        }
        """
        
        guard let jpegData = image.jpegData(compressionQuality: 0.5),
              let compressedImage = UIImage(data: jpegData) else {
            throw NSError(domain: "ImageError", code: 500, userInfo: [NSLocalizedDescriptionKey: "画像処理に失敗しました"])
        }
        
        let response = try await model.generateContent(prompt, compressedImage)
        
        guard let text = response.text else {
            throw NSError(domain: "GeminiError", code: 500, userInfo: [NSLocalizedDescriptionKey: "AIからの応答が空でした"])
        }
        
        let cleanText = text.replacingOccurrences(of: "```json", with: "")
                            .replacingOccurrences(of: "```", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanText.data(using: .utf8) else {
            throw NSError(domain: "ParseError", code: 500, userInfo: [NSLocalizedDescriptionKey: "データの変換に失敗しました"])
        }
        
        let aiResponse = try JSONDecoder().decode(AIResponse.self, from: jsonData)
        return aiResponse
    }
}

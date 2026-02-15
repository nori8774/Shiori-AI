import Foundation
import VecturaKit

/// Gemini Embedding APIを使用するVecturaEmbedder実装
/// 日本語テキストのセマンティック検索に最適化
public actor GeminiEmbedder: VecturaEmbedder {

    private let apiKey: String
    private let modelName = "gemini-embedding-001"
    private let outputDimension = 768  // 768次元（NLEmbedderと互換性を持たせる）

    private var cachedDimension: Int?

    /// APIキーをKeychainから取得して初期化
    public init() async throws {
        // 同意チェック
        guard AIConsentManager.shared.hasConsent else {
            throw GeminiEmbedderError.consentRequired
        }

        guard let data = KeychainHelper.standard.read(service: "com.myapp.gemini", account: "gemini_api_key"),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw GeminiEmbedderError.apiKeyNotFound
        }
        self.apiKey = apiKey
        print("GeminiEmbedder: Initialized with API key")
    }

    /// 明示的にAPIキーを渡して初期化
    public init(apiKey: String) {
        self.apiKey = apiKey
        print("GeminiEmbedder: Initialized with provided API key")
    }

    // MARK: - VecturaEmbedder Protocol

    public var dimension: Int {
        get async throws {
            return outputDimension
        }
    }

    public func embed(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            guard !text.isEmpty else {
                throw GeminiEmbedderError.emptyText(index: index)
            }

            let vector = try await embedSingle(text: text)
            results.append(vector)

            // レート制限対策: 複数テキストの場合は少し待機
            if texts.count > 1 && index < texts.count - 1 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            }
        }

        return results
    }

    public func embed(text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw GeminiEmbedderError.emptyText(index: 0)
        }
        return try await embedSingle(text: text)
    }

    // MARK: - Private Methods

    private func embedSingle(text: String) async throws -> [Float] {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):embedContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw GeminiEmbedderError.invalidURL
        }

        // リクエストボディを構築
        let requestBody: [String: Any] = [
            "model": "models/\(modelName)",
            "content": [
                "parts": [
                    ["text": text]
                ]
            ],
            "outputDimensionality": outputDimension
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiEmbedderError.invalidResponse
        }

        // エラーレスポンスのチェック
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {

                // レート制限エラーのチェック
                if httpResponse.statusCode == 429 {
                    throw GeminiEmbedderError.rateLimited(message: message)
                }

                throw GeminiEmbedderError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            throw GeminiEmbedderError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        // レスポンスをパース
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [String: Any],
              let values = embedding["values"] as? [Double] else {
            throw GeminiEmbedderError.parseError
        }

        // DoubleからFloatに変換
        let floatVector = values.map { Float($0) }

        print("GeminiEmbedder: Generated \(floatVector.count)-dimensional embedding for text (\(text.prefix(30))...)")

        return floatVector
    }
}

// MARK: - Errors

public enum GeminiEmbedderError: LocalizedError {
    case consentRequired
    case apiKeyNotFound
    case emptyText(index: Int)
    case invalidURL
    case invalidResponse
    case rateLimited(message: String)
    case apiError(statusCode: Int, message: String)
    case parseError

    public var errorDescription: String? {
        switch self {
        case .consentRequired:
            return "AI機能を使用するにはデータ送信への同意が必要です。"
        case .apiKeyNotFound:
            return "Gemini APIキーが見つかりません。設定画面で設定してください。"
        case .emptyText(let index):
            return "テキストが空です（インデックス: \(index)）"
        case .invalidURL:
            return "無効なURL"
        case .invalidResponse:
            return "無効なレスポンス"
        case .rateLimited(let message):
            return "レート制限: \(message)"
        case .apiError(let statusCode, let message):
            return "APIエラー (\(statusCode)): \(message)"
        case .parseError:
            return "レスポンスの解析に失敗しました"
        }
    }
}

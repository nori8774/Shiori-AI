import Foundation
import UIKit
import PDFKit
import GoogleGenerativeAI

// MARK: - Paper Summary Response

struct PaperInfoResponse: Codable {
    let title: String
    let authors: [String]
    let institution: String?
    let year: String?
    let journal: String?
}

struct PaperSummaryResponse: Codable {
    let abstractSummary: String
    let keyFindings: [String]
    let methodology: String
    let figureNotes: [String]
    let keywords: [String]
}

// MARK: - Paper Summary Service

class PaperSummaryService {
    static let shared = PaperSummaryService()

    private init() {}

    // MARK: - Main Entry Point

    /// 論文を要約し、要約付きPDFを生成して「要約」本棚に保存
    func summarizePaper(book: Book, progressHandler: @escaping (String, Float) -> Void) async throws -> Book {
        let fileURL = LibraryManager.shared.getBookURL(book)

        guard let document = PDFDocument(url: fileURL) else {
            throw PaperSummaryError.pdfLoadFailed
        }

        let pageCount = document.pageCount

        // ページ数制限チェック
        guard pageCount <= 50 else {
            throw PaperSummaryError.tooManyPages(pageCount)
        }

        // Step 1: 表紙から論文情報を抽出
        progressHandler("表紙を解析中...", 0.1)
        let paperInfo = try await extractPaperInfo(from: document)

        // Step 2: 本文を要約
        progressHandler("本文を要約中...", 0.3)
        let summaryResponse = try await summarizeContent(from: document, progressHandler: { progress in
            progressHandler("本文を要約中...", 0.3 + progress * 0.5)
        })

        // Step 3: PaperSummaryを作成
        let summary = PaperSummary(
            id: UUID(),
            originalBookId: book.id,
            summaryBookId: nil,
            title: paperInfo.title,
            authors: paperInfo.authors,
            abstractSummary: summaryResponse.abstractSummary,
            keyFindings: summaryResponse.keyFindings,
            methodology: summaryResponse.methodology,
            figureNotes: summaryResponse.figureNotes,
            keywords: summaryResponse.keywords,
            createdAt: Date()
        )

        // Step 4: 要約ページPDFを生成
        progressHandler("要約ページを生成中...", 0.85)
        guard let summaryDoc = PDFGenerator.shared.generateSummaryPage(summary: summary, originalFileName: book.fileName),
              let summaryPage = summaryDoc.page(at: 0) else {
            throw PaperSummaryError.pdfGenerationFailed
        }

        // Step 5: 元PDFと合成
        progressHandler("PDFを合成中...", 0.9)
        guard let mergedDoc = PDFGenerator.shared.insertSummaryPage(into: fileURL, summaryPage: summaryPage) else {
            throw PaperSummaryError.pdfMergeFailed
        }

        // Step 6: 新しいファイルとして保存
        let newFileName = PDFGenerator.shared.generateSummaryFileName(from: book.fileName)
        guard let pdfData = mergedDoc.dataRepresentation() else {
            throw PaperSummaryError.pdfSaveFailed
        }

        // 「要約」本棚に保存
        let summaryShelfId = SystemShelfID.summaries
        guard let newBook = LibraryManager.shared.savePDFDirectly(data: pdfData, fileName: newFileName, bookshelfId: summaryShelfId) else {
            throw PaperSummaryError.pdfSaveFailed
        }

        progressHandler("完了", 1.0)

        return newBook
    }

    // MARK: - Extract Paper Info

    private func extractPaperInfo(from document: PDFDocument) async throws -> PaperInfoResponse {
        guard let coverPage = document.page(at: 0) else {
            throw PaperSummaryError.pdfLoadFailed
        }

        // 表紙をキャプチャ
        let coverImage = capturePageImage(page: coverPage)

        guard let data = KeychainHelper.standard.read(service: "com.myapp.gemini", account: "gemini_api_key"),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw PaperSummaryError.apiKeyMissing
        }

        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)

        let prompt = """
        この論文の表紙から以下の情報を抽出してJSON形式で出力してください。
        情報が見つからない場合は空文字列を使用してください。

        ■ 出力フォーマット:
        {
            "title": "論文タイトル",
            "authors": ["著者1", "著者2"],
            "institution": "所属機関",
            "year": "発行年",
            "journal": "ジャーナル名"
        }

        注意: 純粋なJSONのみを出力してください。
        """

        guard let jpegData = coverImage.jpegData(compressionQuality: 0.7),
              let compressedImage = UIImage(data: jpegData) else {
            throw PaperSummaryError.imageProcessingFailed
        }

        let response = try await model.generateContent(prompt, compressedImage)

        guard let text = response.text else {
            throw PaperSummaryError.emptyResponse
        }

        let cleanText = text.replacingOccurrences(of: "```json", with: "")
                            .replacingOccurrences(of: "```", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanText.data(using: .utf8) else {
            throw PaperSummaryError.parseError
        }

        return try JSONDecoder().decode(PaperInfoResponse.self, from: jsonData)
    }

    // MARK: - Summarize Content

    private func summarizeContent(from document: PDFDocument, progressHandler: @escaping (Float) -> Void) async throws -> PaperSummaryResponse {
        guard let data = KeychainHelper.standard.read(service: "com.myapp.gemini", account: "gemini_api_key"),
              let apiKey = String(data: data, encoding: .utf8) else {
            throw PaperSummaryError.apiKeyMissing
        }

        let model = GenerativeModel(name: "gemini-2.5-flash", apiKey: apiKey)

        // 複数ページをまとめて解析（最大10ページずつ）
        var allText = ""
        let pageCount = min(document.pageCount, 20)  // 最大20ページ

        for i in 0..<pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                allText += "\n--- Page \(i + 1) ---\n"
                allText += pageText
            }
            progressHandler(Float(i + 1) / Float(pageCount))
        }

        // テキストが長すぎる場合は切り詰め
        if allText.count > 50000 {
            allText = String(allText.prefix(50000))
        }

        let prompt = """
        以下は学術論文のテキストです。論文全体の要約を以下のJSON形式で作成してください。

        ■ 論文テキスト:
        \(allText)

        ■ 出力フォーマット:
        {
            "abstractSummary": "論文の概要を100-200文字で要約",
            "keyFindings": ["主要な発見1", "主要な発見2", "主要な発見3"],
            "methodology": "研究手法を50-100文字で説明",
            "figureNotes": ["図表に関する重要なポイント1", "図表に関する重要なポイント2"],
            "keywords": ["キーワード1", "キーワード2", "キーワード3", "キーワード4", "キーワード5"]
        }

        注意:
        - 日本語で出力してください
        - 純粋なJSONのみを出力してください
        - keyFindingsは3-5項目、keywordsは5-10項目にしてください
        """

        let response = try await model.generateContent(prompt)

        guard let text = response.text else {
            throw PaperSummaryError.emptyResponse
        }

        let cleanText = text.replacingOccurrences(of: "```json", with: "")
                            .replacingOccurrences(of: "```", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanText.data(using: .utf8) else {
            throw PaperSummaryError.parseError
        }

        return try JSONDecoder().decode(PaperSummaryResponse.self, from: jsonData)
    }

    // MARK: - Helpers

    private func capturePageImage(page: PDFPage) -> UIImage {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0

        let renderer = UIGraphicsImageRenderer(size: CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        ))

        return renderer.image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            ctx.cgContext.translateBy(x: 0, y: pageRect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
}

// MARK: - Errors

enum PaperSummaryError: LocalizedError {
    case pdfLoadFailed
    case tooManyPages(Int)
    case apiKeyMissing
    case imageProcessingFailed
    case emptyResponse
    case parseError
    case pdfGenerationFailed
    case pdfMergeFailed
    case pdfSaveFailed

    var errorDescription: String? {
        switch self {
        case .pdfLoadFailed:
            return "PDFの読み込みに失敗しました"
        case .tooManyPages(let count):
            return "ページ数が多すぎます（\(count)ページ）。50ページ以下の論文に対応しています"
        case .apiKeyMissing:
            return "APIキーが設定されていません。設定画面でGemini APIキーを入力してください"
        case .imageProcessingFailed:
            return "画像処理に失敗しました"
        case .emptyResponse:
            return "AIからの応答が空でした"
        case .parseError:
            return "AIの応答を解析できませんでした"
        case .pdfGenerationFailed:
            return "要約ページの生成に失敗しました"
        case .pdfMergeFailed:
            return "PDFの合成に失敗しました"
        case .pdfSaveFailed:
            return "PDFの保存に失敗しました"
        }
    }
}

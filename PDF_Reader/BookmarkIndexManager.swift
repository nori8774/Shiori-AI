import Foundation
import SwiftUI
import UIKit
import PDFKit
import Combine
import VecturaKit

// MARK: - Data Models

/// インデックスされたページのメタデータ（個別ページ情報）
struct PageIndexInfo: Codable {
    let pageIndex: Int
    let summary: String
    let markerTexts: [String]?
}

/// PDF単位の統合インデックスメタデータ
struct PDFIndexMetadata: Codable, Identifiable {
    let id: UUID  // VectorDBのドキュメントID
    let pdfFileName: String
    var pages: [PageIndexInfo]  // このPDFのインデックス済みページ一覧
    let createdAt: Date
    var updatedAt: Date

    /// 統合テキスト（全ページの要約を結合）
    var combinedText: String {
        pages.map { page in
            "【P\(page.pageIndex + 1)】\(page.summary)" +
            (page.markerTexts?.map { " [\($0)]" }.joined() ?? "")
        }.joined(separator: "\n\n")
    }
}

/// 検索結果（PDF単位、複数ページを含む）
struct BookmarkSearchResult: Identifiable {
    let id: UUID
    let pdfFileName: String
    let matchedPages: [PageIndexInfo]  // マッチしたPDFの全しおりページ
    let score: Float
}

/// リランキング後のページ検索結果
struct RankedPageResult: Identifiable {
    let id = UUID()
    let pdfFileName: String
    let pageIndex: Int
    let summary: String
    let markerTexts: [String]?
    let score: Float
}

/// 旧形式との互換性のため残す（マイグレーション用）
struct BookmarkIndexMetadata: Codable, Identifiable {
    let id: UUID
    let bookId: UUID?
    let pdfFileName: String
    let pageIndex: Int
    let summary: String
    let markerTexts: [String]?
    let createdAt: Date
}

// MARK: - BookmarkIndexManager

class BookmarkIndexManager: ObservableObject {
    @MainActor static let shared = BookmarkIndexManager()

    @MainActor @Published var isIndexing = false
    @MainActor @Published var indexingProgress: String?
    @MainActor @Published var indexedCount: Int = 0

    private var vectorDB: VecturaKit?
    private var embedder: GeminiEmbedder?

    // PDF単位の統合インデックス（新形式）
    private var pdfIndexStore: [String: PDFIndexMetadata] = [:]  // key: pdfFileName
    private let pdfIndexFileName = "pdf_index_metadata.json"

    // 旧形式（マイグレーション用、読み取り専用）
    private var metadataStore: [UUID: BookmarkIndexMetadata] = [:]
    private let metadataFileName = "bookmark_index_metadata.json"

    // 遅延インデックス用（3分後にembedding）
    private let indexDelaySeconds: TimeInterval = 180  // 3分
    private var pendingIndexTasks: [String: Task<Void, Never>] = [:]  // key: "pdfFileName_pageIndex"
    private let pendingIndexFileName = "pending_index_tasks.json"

    @MainActor
    private init() {
        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        do {
            // Gemini Embedder（日本語対応）
            embedder = try await GeminiEmbedder()
            print("BookmarkIndexManager: Using Gemini Embedder (Japanese optimized)")

            // VecturaKit設定（ハイブリッド検索有効）
            let searchOptions = VecturaConfig.SearchOptions(
                defaultNumResults: 10,
                minThreshold: 0.0,
                hybridWeight: 0.6,  // 60% vector + 40% BM25 キーワードマッチング
                k1: 1.2,
                b: 0.75
            )

            let config = try VecturaConfig(
                name: "pdf-reader-bookmarks-gemini",  // 新しいDB名（既存と分離）
                dimension: 768,  // Gemini Embedding の次元数
                searchOptions: searchOptions
            )

            vectorDB = try await VecturaKit(config: config, embedder: embedder!)

            // メタデータ読み込み（新形式）
            loadPDFIndexMetadata()

            // 旧形式からのマイグレーション確認
            loadMetadata()
            if !metadataStore.isEmpty && pdfIndexStore.isEmpty {
                print("BookmarkIndexManager: Migrating from old format...")
                await migrateFromOldFormat()
            }

            // インデックス済みページ数をカウント
            let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
            await MainActor.run {
                indexedCount = totalPages
            }

            print("BookmarkIndexManager initialized with \(pdfIndexStore.count) PDFs, \(totalPages) pages (Hybrid search enabled)")
        } catch {
            print("BookmarkIndexManager initialization failed: \(error)")
        }
    }

    // MARK: - Delayed Indexing (3分後にembedding)

    /// しおり追加時に呼ばれる：3分後にインデックス作成をスケジュール
    func scheduleIndexing(
        bookId: UUID?,
        pdfFileName: String,
        pageIndex: Int,
        pdfDocument: PDFDocument?
    ) {
        let key = "\(pdfFileName)_\(pageIndex)"

        // 既にこのページがインデックスされている場合はスキップ
        if isPageIndexed(pdfFileName: pdfFileName, pageIndex: pageIndex) {
            print("Bookmark already indexed: \(pdfFileName) page \(pageIndex)")
            return
        }

        // 既存のタスクがあればキャンセル（しおり再追加の場合）
        if let existingTask = pendingIndexTasks[key] {
            existingTask.cancel()
            print("Cancelled existing index task for: \(key)")
        }

        // 保留タスクを保存（アプリ再起動対策）
        savePendingTask(pdfFileName: pdfFileName, pageIndex: pageIndex, bookId: bookId)

        print("Scheduled indexing for \(pdfFileName) page \(pageIndex) in \(Int(indexDelaySeconds)) seconds")

        // 3分後にインデックス作成
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(indexDelaySeconds * 1_000_000_000))

                // キャンセルされていないかチェック
                if Task.isCancelled {
                    print("Index task was cancelled: \(key)")
                    return
                }

                // しおりがまだ存在するか確認
                let bookmarkExists = await MainActor.run {
                    BookmarkManager.shared.isBookmarked(pdfFileName: pdfFileName, pageIndex: pageIndex)
                }

                if bookmarkExists {
                    print("Starting delayed indexing for: \(key)")
                    await indexPageAndRebuildPDFIndex(
                        pdfFileName: pdfFileName,
                        pageIndex: pageIndex,
                        pdfDocument: pdfDocument
                    )
                } else {
                    print("Bookmark was removed, skipping indexing: \(key)")
                }

                // 保留タスクから削除
                removePendingTask(pdfFileName: pdfFileName, pageIndex: pageIndex)

            } catch {
                if error is CancellationError {
                    print("Index task cancelled: \(key)")
                } else {
                    print("Index task error: \(error)")
                }
            }
        }

        pendingIndexTasks[key] = task
    }

    /// しおり削除時に呼ばれる：保留中のインデックスタスクをキャンセル
    func cancelScheduledIndexing(pdfFileName: String, pageIndex: Int) {
        let key = "\(pdfFileName)_\(pageIndex)"

        if let task = pendingIndexTasks[key] {
            task.cancel()
            pendingIndexTasks.removeValue(forKey: key)
            removePendingTask(pdfFileName: pdfFileName, pageIndex: pageIndex)
            print("Cancelled scheduled indexing for: \(key)")
        }
    }

    // MARK: - Indexing (PDF統合版)

    /// ページをインデックスし、PDF全体の統合インデックスを再構築
    private func indexPageAndRebuildPDFIndex(
        pdfFileName: String,
        pageIndex: Int,
        pdfDocument: PDFDocument?
    ) async {
        guard vectorDB != nil else {
            print("VectorDB not initialized")
            return
        }

        // 既にこのページがインデックスされているかチェック
        if isPageIndexed(pdfFileName: pdfFileName, pageIndex: pageIndex) {
            print("Page already indexed: \(pdfFileName) page \(pageIndex)")
            return
        }

        await MainActor.run {
            isIndexing = true
            indexingProgress = "ページ \(pageIndex + 1) のインデックス作成中..."
        }

        do {
            // 1. テキスト取得
            let rawText = await getRawText(pdfFileName: pdfFileName, pageIndex: pageIndex, pdfDocument: pdfDocument)

            guard !rawText.isEmpty else {
                await MainActor.run {
                    indexingProgress = nil
                    isIndexing = false
                }
                print("No text found for page \(pageIndex)")
                return
            }

            // 2. マーカーテキスト取得
            let markerTexts = await MainActor.run {
                getMarkerTexts(pdfFileName: pdfFileName, pageIndex: pageIndex)
            }

            // 3. 検索用要約生成
            await MainActor.run {
                indexingProgress = "要約を生成中..."
            }
            let summary = try await GeminiService.shared.generateSearchSummary(
                rawText: rawText,
                markerTexts: markerTexts
            )

            // 4. 新しいページ情報を作成
            let newPageInfo = PageIndexInfo(
                pageIndex: pageIndex,
                summary: summary,
                markerTexts: markerTexts
            )

            // 5. PDF統合インデックスを更新
            await rebuildPDFIndex(pdfFileName: pdfFileName, addingPage: newPageInfo)

            await MainActor.run {
                let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
                indexedCount = totalPages
                indexingProgress = nil
                isIndexing = false
            }
            print("Indexed page and rebuilt PDF index: \(pdfFileName) page \(pageIndex)")
        } catch {
            await MainActor.run {
                indexingProgress = "エラー: \(error.localizedDescription)"
                isIndexing = false
            }
            print("Indexing failed: \(error)")
        }
    }

    /// PDF統合インデックスを再構築（新しいページを追加）
    private func rebuildPDFIndex(pdfFileName: String, addingPage newPage: PageIndexInfo) async {
        guard let vectorDB = vectorDB else { return }

        await MainActor.run {
            indexingProgress = "PDF統合インデックスを更新中..."
        }

        // 既存のPDFインデックスを取得または新規作成
        var pdfIndex = pdfIndexStore[pdfFileName]
        let isNewPDF = pdfIndex == nil

        if var existingIndex = pdfIndex {
            // 既存のVectorDBエントリを削除
            do {
                try await vectorDB.deleteDocuments(ids: [existingIndex.id])
                print("Deleted old vector entry for \(pdfFileName)")
            } catch {
                print("Failed to delete old vector entry: \(error)")
            }

            // ページを追加（重複チェック）
            if !existingIndex.pages.contains(where: { $0.pageIndex == newPage.pageIndex }) {
                existingIndex.pages.append(newPage)
                existingIndex.pages.sort { $0.pageIndex < $1.pageIndex }
            }
            existingIndex.updatedAt = Date()
            pdfIndex = existingIndex
        } else {
            // 新規PDFインデックス
            pdfIndex = PDFIndexMetadata(
                id: UUID(),
                pdfFileName: pdfFileName,
                pages: [newPage],
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        guard var finalIndex = pdfIndex else { return }

        // 新しいIDでVectorDBに追加
        let newDocumentId = UUID()
        finalIndex = PDFIndexMetadata(
            id: newDocumentId,
            pdfFileName: finalIndex.pdfFileName,
            pages: finalIndex.pages,
            createdAt: finalIndex.createdAt,
            updatedAt: Date()
        )

        do {
            let textToEmbed = finalIndex.combinedText
            print("Embedding combined text for \(pdfFileName): \(textToEmbed.prefix(200))...")

            _ = try await vectorDB.addDocuments(
                texts: [textToEmbed],
                ids: [newDocumentId]
            )

            // メタデータ保存
            pdfIndexStore[pdfFileName] = finalIndex
            savePDFIndexMetadata()

            print("Rebuilt PDF index: \(pdfFileName) with \(finalIndex.pages.count) pages")
        } catch {
            print("Failed to rebuild PDF index: \(error)")
        }
    }

    /// しおりをインデックスに追加（公開API - 遅延インデックスをスケジュール）
    func indexBookmark(
        bookId: UUID?,
        pdfFileName: String,
        pageIndex: Int,
        pdfDocument: PDFDocument?
    ) async {
        scheduleIndexing(
            bookId: bookId,
            pdfFileName: pdfFileName,
            pageIndex: pageIndex,
            pdfDocument: pdfDocument
        )
    }

    // MARK: - Search

    /// セマンティック検索（PDF単位で結果を返す）
    func search(query: String, numResults: Int = 5) async throws -> [BookmarkSearchResult] {
        print("=== SEARCH START ===")
        print("Query: \(query)")
        print("PDFIndexStore count: \(pdfIndexStore.count)")

        guard let vectorDB = vectorDB else {
            print("ERROR: VectorDB is nil")
            throw NSError(domain: "BookmarkIndexManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "検索エンジンが初期化されていません"])
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("ERROR: Empty query")
            return []
        }

        let results = try await vectorDB.search(
            query: .text(query),
            numResults: numResults,
            threshold: 0.0
        )

        print("VectorDB returned \(results.count) results")
        for (index, result) in results.enumerated() {
            print("Result \(index): id=\(result.id), score=\(result.score)")
        }

        var searchResults: [BookmarkSearchResult] = []
        for result in results {
            // PDF単位のインデックスから検索
            if let pdfIndex = pdfIndexStore.values.first(where: { $0.id == result.id }) {
                print("Matched PDF: \(pdfIndex.pdfFileName) with \(pdfIndex.pages.count) pages, score=\(result.score)")
                searchResults.append(BookmarkSearchResult(
                    id: result.id,
                    pdfFileName: pdfIndex.pdfFileName,
                    matchedPages: pdfIndex.pages,
                    score: result.score
                ))
            } else {
                print("WARNING: No PDF metadata found for id \(result.id)")
            }
        }

        let sorted = searchResults.sorted { $0.score > $1.score }
        print("Final results count: \(sorted.count)")
        print("=== SEARCH END ===")
        return sorted
    }

    /// セマンティック検索 + ページ単位リランキング（上位N件を返す）
    func searchWithReranking(query: String, topK: Int = 5) async throws -> [RankedPageResult] {
        print("=== SEARCH WITH RERANKING START ===")
        print("Query: \(query), topK: \(topK)")

        guard let embedder = embedder else {
            print("ERROR: Embedder is nil")
            throw NSError(domain: "BookmarkIndexManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "検索エンジンが初期化されていません"])
        }

        // 1. まずPDF単位で検索（全PDFを対象）
        let pdfResults = try await search(query: query, numResults: 20)

        if pdfResults.isEmpty {
            print("No PDF results found")
            return []
        }

        // 2. 全ページを収集
        var allPages: [(pdfFileName: String, page: PageIndexInfo)] = []
        for result in pdfResults {
            for page in result.matchedPages {
                allPages.append((result.pdfFileName, page))
            }
        }
        print("Total pages to rerank: \(allPages.count)")

        // 3. クエリのembeddingを生成
        let queryEmbedding = try await embedder.embed(text: query)
        print("Query embedding generated: \(queryEmbedding.count) dimensions")

        // 4. 各ページの要約をembeddingしてスコア計算
        var rankedResults: [RankedPageResult] = []

        for (pdfFileName, page) in allPages {
            // ページの要約テキストを作成（マーカーテキストも含める）
            var pageText = page.summary
            if let markers = page.markerTexts, !markers.isEmpty {
                pageText += " " + markers.joined(separator: " ")
            }

            do {
                let pageEmbedding = try await embedder.embed(text: pageText)

                // コサイン類似度を計算
                let score = cosineSimilarity(queryEmbedding, pageEmbedding)

                rankedResults.append(RankedPageResult(
                    pdfFileName: pdfFileName,
                    pageIndex: page.pageIndex,
                    summary: page.summary,
                    markerTexts: page.markerTexts,
                    score: score
                ))
                print("Page \(page.pageIndex + 1) of \(pdfFileName): score=\(score)")
            } catch {
                print("Failed to embed page \(page.pageIndex): \(error)")
            }
        }

        // 5. スコア順にソートして上位N件を返す
        let sorted = rankedResults.sorted { $0.score > $1.score }
        let topResults = Array(sorted.prefix(topK))

        print("=== RERANKING RESULTS ===")
        for (index, result) in topResults.enumerated() {
            print("\(index + 1). \(result.pdfFileName) p.\(result.pageIndex + 1): \(result.score)")
        }
        print("=== SEARCH WITH RERANKING END ===")

        return topResults
    }

    /// コサイン類似度を計算
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    // MARK: - Index Management

    /// インデックスからページを削除し、PDF統合インデックスを再構築
    func removeIndex(pdfFileName: String, pageIndex: Int) async {
        guard var pdfIndex = pdfIndexStore[pdfFileName] else {
            print("No index found for \(pdfFileName)")
            return
        }

        // ページを削除
        pdfIndex.pages.removeAll { $0.pageIndex == pageIndex }

        if pdfIndex.pages.isEmpty {
            // ページがなくなったらPDF全体を削除
            do {
                try await vectorDB?.deleteDocuments(ids: [pdfIndex.id])
                pdfIndexStore.removeValue(forKey: pdfFileName)
                savePDFIndexMetadata()
                print("Removed entire PDF index: \(pdfFileName)")
            } catch {
                print("Failed to remove PDF index: \(error)")
            }
        } else {
            // ページを削除してPDFインデックスを再構築
            guard let vectorDB = vectorDB else { return }

            do {
                // 古いエントリを削除
                try await vectorDB.deleteDocuments(ids: [pdfIndex.id])

                // 新しいIDで再登録
                let newId = UUID()
                let updatedIndex = PDFIndexMetadata(
                    id: newId,
                    pdfFileName: pdfFileName,
                    pages: pdfIndex.pages,
                    createdAt: pdfIndex.createdAt,
                    updatedAt: Date()
                )

                _ = try await vectorDB.addDocuments(
                    texts: [updatedIndex.combinedText],
                    ids: [newId]
                )

                pdfIndexStore[pdfFileName] = updatedIndex
                savePDFIndexMetadata()
                print("Rebuilt PDF index after removing page \(pageIndex): \(pdfFileName)")
            } catch {
                print("Failed to rebuild PDF index: \(error)")
            }
        }

        await MainActor.run {
            let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
            indexedCount = totalPages
        }
    }

    /// PDFファイルの全インデックス削除
    func removeAllIndexes(for pdfFileName: String) async {
        guard let pdfIndex = pdfIndexStore[pdfFileName] else {
            return
        }

        do {
            try await vectorDB?.deleteDocuments(ids: [pdfIndex.id])
            pdfIndexStore.removeValue(forKey: pdfFileName)
            savePDFIndexMetadata()
            print("Removed all indexes for: \(pdfFileName)")
        } catch {
            print("Failed to remove indexes: \(error)")
        }

        await MainActor.run {
            let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
            indexedCount = totalPages
        }
    }

    // MARK: - Private Helpers

    /// ページがインデックス済みかチェック（新形式）
    private func isPageIndexed(pdfFileName: String, pageIndex: Int) -> Bool {
        return pdfIndexStore[pdfFileName]?.pages.contains { $0.pageIndex == pageIndex } ?? false
    }

    /// 旧形式用: メタデータIDを検索
    private func findMetadataId(pdfFileName: String, pageIndex: Int) -> UUID? {
        return metadataStore.first {
            $0.value.pdfFileName == pdfFileName && $0.value.pageIndex == pageIndex
        }?.key
    }

    private func getRawText(pdfFileName: String, pageIndex: Int, pdfDocument: PDFDocument?) async -> String {
        print("getRawText: pdfFileName=\(pdfFileName), pageIndex=\(pageIndex), pdfDocument=\(pdfDocument != nil ? "exists" : "nil")")

        // 1. ReadingLogからテキスト取得を試みる
        let matchingLogs = HistoryManager.shared.logs.filter {
            $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex
        }
        print("getRawText: found \(matchingLogs.count) matching logs")

        if let log = matchingLogs.first {
            print("getRawText: using ReadingLog, rawText length=\(log.rawText.count)")
            return log.rawText
        }

        // 2. 渡されたPDFDocumentから抽出
        if let page = pdfDocument?.page(at: pageIndex) {
            let text = page.string ?? ""
            print("getRawText: extracted from provided PDF page, text length=\(text.count)")
            if !text.isEmpty {
                return text
            }
        }

        // 3. LibraryManagerからPDFを読み込んで抽出（遅延インデックス用）
        let loadedDocument = await MainActor.run { () -> PDFDocument? in
            if let book = LibraryManager.shared.books.first(where: { $0.fileName == pdfFileName }) {
                let url = LibraryManager.shared.getBookURL(book)
                return PDFDocument(url: url)
            }
            return nil
        }

        if let doc = loadedDocument, let page = doc.page(at: pageIndex) {
            let text = page.string ?? ""
            print("getRawText: extracted from loaded PDF, text length=\(text.count)")
            if !text.isEmpty {
                return text
            }
        }

        // 4. 画像ベースPDFの場合、Gemini OCRでテキスト抽出
        print("getRawText: PDF is image-based, attempting Gemini OCR...")

        if let doc = loadedDocument ?? pdfDocument, let page = doc.page(at: pageIndex) {
            // ページを画像としてレンダリング
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            do {
                // Gemini OCR（analyzePageはrawTextを返す）
                let response = try await GeminiService.shared.analyzePage(
                    image: image,
                    instruction: "この画像のテキストを全て読み取ってください。レイアウトは無視して、テキストのみを出力してください。"
                )
                print("getRawText: OCR extracted \(response.rawText.count) chars")
                return response.rawText
            } catch {
                print("getRawText: OCR failed: \(error)")
            }
        }

        print("getRawText: no text found")
        return ""
    }

    private func getMarkerTexts(pdfFileName: String, pageIndex: Int) -> [String]? {
        let markers = SmartMarkerManager.shared.getMarkers(for: pdfFileName, pageIndex: pageIndex)
        let texts = markers.compactMap { $0.text.isEmpty ? nil : $0.text }
        return texts.isEmpty ? nil : texts
    }

    // MARK: - Persistence

    private var pdfIndexFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(pdfIndexFileName)
    }

    private var metadataFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(metadataFileName)
    }

    private var pendingTasksFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(pendingIndexFileName)
    }

    /// PDF統合インデックスを保存（新形式）
    private func savePDFIndexMetadata() {
        do {
            let data = try JSONEncoder().encode(Array(pdfIndexStore.values))
            try data.write(to: pdfIndexFileURL)
            print("Saved PDF index metadata: \(pdfIndexStore.count) PDFs")
        } catch {
            print("Failed to save PDF index metadata: \(error)")
        }
    }

    /// PDF統合インデックスを読み込み（新形式）
    private func loadPDFIndexMetadata() {
        do {
            let data = try Data(contentsOf: pdfIndexFileURL)
            let indexArray = try JSONDecoder().decode([PDFIndexMetadata].self, from: data)
            pdfIndexStore = Dictionary(uniqueKeysWithValues: indexArray.map { ($0.pdfFileName, $0) })
            print("Loaded PDF index metadata: \(pdfIndexStore.count) PDFs")
        } catch {
            pdfIndexStore = [:]
            print("No existing PDF index metadata found or failed to load")
        }
    }

    /// 旧形式メタデータを保存
    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(Array(metadataStore.values))
            try data.write(to: metadataFileURL)
        } catch {
            print("Failed to save metadata: \(error)")
        }
    }

    /// 旧形式メタデータを読み込み
    private func loadMetadata() {
        do {
            let data = try Data(contentsOf: metadataFileURL)
            let metadataArray = try JSONDecoder().decode([BookmarkIndexMetadata].self, from: data)
            metadataStore = Dictionary(uniqueKeysWithValues: metadataArray.map { ($0.id, $0) })
        } catch {
            metadataStore = [:]
        }
    }

    /// 旧形式から新形式へのマイグレーション
    private func migrateFromOldFormat() async {
        print("Starting migration from old format...")

        // PDF名でグループ化
        var pdfGroups: [String: [BookmarkIndexMetadata]] = [:]
        for metadata in metadataStore.values {
            pdfGroups[metadata.pdfFileName, default: []].append(metadata)
        }

        // 各PDFグループを新形式に変換
        for (pdfFileName, pages) in pdfGroups {
            let pageInfos = pages.map { PageIndexInfo(
                pageIndex: $0.pageIndex,
                summary: $0.summary,
                markerTexts: $0.markerTexts
            )}.sorted { $0.pageIndex < $1.pageIndex }

            let newIndex = PDFIndexMetadata(
                id: UUID(),
                pdfFileName: pdfFileName,
                pages: pageInfos,
                createdAt: pages.first?.createdAt ?? Date(),
                updatedAt: Date()
            )

            // VectorDBに追加
            do {
                _ = try await vectorDB?.addDocuments(
                    texts: [newIndex.combinedText],
                    ids: [newIndex.id]
                )
                pdfIndexStore[pdfFileName] = newIndex
                print("Migrated: \(pdfFileName) with \(pageInfos.count) pages")
            } catch {
                print("Failed to migrate \(pdfFileName): \(error)")
            }
        }

        // 新形式を保存
        savePDFIndexMetadata()

        // 旧形式のVectorDBエントリを削除
        let oldIds = Array(metadataStore.keys)
        if !oldIds.isEmpty {
            do {
                try await vectorDB?.deleteDocuments(ids: oldIds)
                print("Deleted \(oldIds.count) old vector entries")
            } catch {
                print("Failed to delete old entries: \(error)")
            }
        }

        // 旧形式のメタデータをクリア
        metadataStore.removeAll()
        saveMetadata()

        print("Migration complete: \(pdfIndexStore.count) PDFs migrated")
    }

    // MARK: - Pending Tasks Persistence

    private struct PendingIndexTask: Codable {
        let pdfFileName: String
        let pageIndex: Int
        let bookId: UUID?
        let scheduledAt: Date
    }

    private func savePendingTask(pdfFileName: String, pageIndex: Int, bookId: UUID?) {
        var tasks = loadPendingTasks()
        let key = "\(pdfFileName)_\(pageIndex)"

        // 既存のタスクを削除
        tasks.removeAll { "\($0.pdfFileName)_\($0.pageIndex)" == key }

        // 新しいタスクを追加
        tasks.append(PendingIndexTask(
            pdfFileName: pdfFileName,
            pageIndex: pageIndex,
            bookId: bookId,
            scheduledAt: Date()
        ))

        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: pendingTasksFileURL)
        } catch {
            print("Failed to save pending tasks: \(error)")
        }
    }

    private func removePendingTask(pdfFileName: String, pageIndex: Int) {
        var tasks = loadPendingTasks()
        let key = "\(pdfFileName)_\(pageIndex)"
        tasks.removeAll { "\($0.pdfFileName)_\($0.pageIndex)" == key }

        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: pendingTasksFileURL)
        } catch {
            print("Failed to save pending tasks: \(error)")
        }
    }

    private func loadPendingTasks() -> [PendingIndexTask] {
        do {
            let data = try Data(contentsOf: pendingTasksFileURL)
            return try JSONDecoder().decode([PendingIndexTask].self, from: data)
        } catch {
            return []
        }
    }

    /// アプリ起動時に保留中のタスクを処理
    func processPendingTasksOnLaunch() async {
        let tasks = loadPendingTasks()
        guard !tasks.isEmpty else { return }

        print("Processing \(tasks.count) pending index tasks from previous session")

        for task in tasks {
            // しおりがまだ存在するか確認
            let bookmarkExists = await MainActor.run {
                BookmarkManager.shared.isBookmarked(pdfFileName: task.pdfFileName, pageIndex: task.pageIndex)
            }

            // 既にインデックスされているか確認（新形式）
            let alreadyIndexed = isPageIndexed(pdfFileName: task.pdfFileName, pageIndex: task.pageIndex)

            if bookmarkExists && !alreadyIndexed {
                // 3分経過しているか確認
                let elapsed = Date().timeIntervalSince(task.scheduledAt)
                if elapsed >= indexDelaySeconds {
                    // 即座にインデックス作成
                    print("Indexing pending task: \(task.pdfFileName) page \(task.pageIndex)")
                    await indexPageAndRebuildPDFIndex(
                        pdfFileName: task.pdfFileName,
                        pageIndex: task.pageIndex,
                        pdfDocument: nil
                    )
                } else {
                    // 残り時間だけ待ってからインデックス
                    let remainingTime = indexDelaySeconds - elapsed
                    print("Rescheduling pending task: \(task.pdfFileName) page \(task.pageIndex) in \(Int(remainingTime))s")
                    scheduleIndexing(
                        bookId: task.bookId,
                        pdfFileName: task.pdfFileName,
                        pageIndex: task.pageIndex,
                        pdfDocument: nil
                    )
                }
            } else {
                // しおりが削除されたか、既にインデックス済み
                removePendingTask(pdfFileName: task.pdfFileName, pageIndex: task.pageIndex)
            }
        }
    }

    // MARK: - Status

    /// インデックス済みかどうか（公開API）
    func isIndexed(pdfFileName: String, pageIndex: Int) -> Bool {
        return isPageIndexed(pdfFileName: pdfFileName, pageIndex: pageIndex)
    }

    /// インデックスされていないしおりをバッチインデックス
    func indexMissingBookmarks(pdfDocument: PDFDocument?, pdfFileName: String) async {
        let bookmarks = BookmarkManager.shared.getBookmarks(for: pdfFileName)
        let unindexed = bookmarks.filter { !isIndexed(pdfFileName: $0.pdfFileName, pageIndex: $0.pageIndex) }

        for bookmark in unindexed {
            await indexBookmark(
                bookId: nil,
                pdfFileName: bookmark.pdfFileName,
                pageIndex: bookmark.pageIndex,
                pdfDocument: pdfDocument
            )
        }
    }

    /// 全インデックスをクリア
    func clearAllIndexes() async {
        print("Clearing all indexes...")

        // PDF統合インデックスをクリア（新形式）
        if let vectorDB = vectorDB {
            let pdfIds = pdfIndexStore.values.map { $0.id }
            if !pdfIds.isEmpty {
                do {
                    try await vectorDB.deleteDocuments(ids: pdfIds)
                    print("Deleted \(pdfIds.count) PDF indexes from vectorDB")
                } catch {
                    print("Failed to delete PDF indexes: \(error)")
                }
            }

            // 旧形式も念のためクリア
            let oldIds = Array(metadataStore.keys)
            if !oldIds.isEmpty {
                do {
                    try await vectorDB.deleteDocuments(ids: oldIds)
                    print("Deleted \(oldIds.count) old documents from vectorDB")
                } catch {
                    print("Failed to delete old documents: \(error)")
                }
            }
        }

        pdfIndexStore.removeAll()
        savePDFIndexMetadata()

        metadataStore.removeAll()
        saveMetadata()

        await MainActor.run {
            indexedCount = 0
        }

        print("All indexes cleared")
    }

    /// 全履歴からインデックスを再構築（履歴ベース）
    func rebuildAllIndexes() async {
        print("rebuildAllIndexes: START")

        // VectorDBが初期化されるまで待機
        var waitCount = 0
        while vectorDB == nil && waitCount < 10 {
            print("rebuildAllIndexes: Waiting for vectorDB initialization... (\(waitCount))")
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機
            waitCount += 1
        }

        guard vectorDB != nil else {
            print("rebuildAllIndexes: VectorDB failed to initialize after waiting")
            await MainActor.run {
                indexingProgress = "検索エンジンの初期化に失敗しました"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                indexingProgress = nil
            }
            return
        }
        print("rebuildAllIndexes: VectorDB is ready")

        await MainActor.run {
            isIndexing = true
            indexingProgress = "インデックスをクリア中..."
            print("rebuildAllIndexes: isIndexing set to true")
        }

        // 既存のインデックスをクリア
        await clearAllIndexes()

        // 全履歴を取得（重複を除去）
        let allLogs = await MainActor.run {
            HistoryManager.shared.logs
        }

        // PDF名とページ番号でユニークな組み合わせを取得
        var uniquePages: [(pdfFileName: String, pageIndex: Int, rawText: String)] = []
        var seenKeys = Set<String>()
        for log in allLogs {
            let key = "\(log.pdfFileName)_\(log.pageIndex)"
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                uniquePages.append((log.pdfFileName, log.pageIndex, log.rawText))
            }
        }

        print("rebuildAllIndexes: Found \(uniquePages.count) unique pages from \(allLogs.count) logs")

        // 履歴がない場合
        if uniquePages.isEmpty {
            await MainActor.run {
                indexingProgress = "履歴が見つかりません"
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                indexingProgress = nil
                isIndexing = false
            }
            print("rebuildAllIndexes: No logs found, exiting")
            return
        }

        for (index, page) in uniquePages.enumerated() {
            await MainActor.run {
                indexingProgress = "インデックス作成中... (\(index + 1)/\(uniquePages.count))"
            }

            // 履歴から直接インデックス作成
            await indexFromRawText(
                pdfFileName: page.pdfFileName,
                pageIndex: page.pageIndex,
                rawText: page.rawText
            )

            // レート制限対策: 少し待機
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        await MainActor.run {
            indexingProgress = nil
            isIndexing = false
        }

        let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
        print("Rebuild complete. Indexed \(pdfIndexStore.count) PDFs, \(totalPages) pages")
    }

    /// rawTextから直接インデックス作成し、PDF統合インデックスを再構築
    private func indexFromRawText(pdfFileName: String, pageIndex: Int, rawText: String) async {
        print("indexFromRawText: START for \(pdfFileName) page \(pageIndex)")

        guard vectorDB != nil else {
            print("indexFromRawText: VectorDB not initialized")
            return
        }

        // 既にインデックスされているかチェック（新形式）
        if isPageIndexed(pdfFileName: pdfFileName, pageIndex: pageIndex) {
            print("indexFromRawText: Already indexed: \(pdfFileName) page \(pageIndex)")
            return
        }

        guard !rawText.isEmpty else {
            print("indexFromRawText: Empty rawText for \(pdfFileName) page \(pageIndex)")
            return
        }
        print("indexFromRawText: rawText length = \(rawText.count) chars")

        do {
            // マーカーテキスト取得
            let markerTexts = await MainActor.run {
                getMarkerTexts(pdfFileName: pdfFileName, pageIndex: pageIndex)
            }

            // 検索用要約生成（レート制限時はリトライ）
            var summary: String?
            var retryCount = 0
            let maxRetries = 3

            while summary == nil && retryCount <= maxRetries {
                do {
                    summary = try await GeminiService.shared.generateSearchSummary(
                        rawText: rawText,
                        markerTexts: markerTexts
                    )
                } catch {
                    let errorString = String(describing: error)
                    let errorLower = errorString.lowercased()
                    let isRateLimit = errorLower.contains("429") ||
                                      errorLower.contains("resource_exhausted") ||
                                      errorLower.contains("resourceexhausted") ||
                                      errorLower.contains("quota")
                    if isRateLimit {
                        retryCount += 1
                        if retryCount <= maxRetries {
                            var waitSeconds: UInt64 = 30
                            if let range = errorString.range(of: #"retry in (\d+\.?\d*)"#, options: .regularExpression) {
                                let matched = String(errorString[range])
                                if let numRange = matched.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                                    if let seconds = Double(matched[numRange]) {
                                        waitSeconds = UInt64(seconds.rounded(.up)) + 2
                                    }
                                }
                            }
                            print("indexFromRawText: Rate limited, waiting \(waitSeconds) seconds before retry \(retryCount)/\(maxRetries)...")
                            await MainActor.run {
                                indexingProgress = "レート制限中... \(waitSeconds)秒待機 (\(retryCount)/\(maxRetries))"
                            }
                            try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                        } else {
                            print("indexFromRawText: Max retries reached, giving up")
                            throw error
                        }
                    } else {
                        throw error
                    }
                }
            }

            guard let finalSummary = summary else {
                print("indexFromRawText: Failed to generate summary after retries")
                return
            }
            print("=== INDEX SUMMARY for page \(pageIndex) ===")
            print(finalSummary)
            print("=== END SUMMARY ===")

            // 新しいページ情報を作成
            let newPageInfo = PageIndexInfo(
                pageIndex: pageIndex,
                summary: finalSummary,
                markerTexts: markerTexts
            )

            // PDF統合インデックスを再構築
            await rebuildPDFIndex(pdfFileName: pdfFileName, addingPage: newPageInfo)

            await MainActor.run {
                let totalPages = pdfIndexStore.values.reduce(0) { $0 + $1.pages.count }
                indexedCount = totalPages
            }

            print("Indexed: \(pdfFileName) page \(pageIndex)")
        } catch {
            print("Failed to index \(pdfFileName) page \(pageIndex): \(error)")
        }
    }

    /// ReadingLogからテキストを取得してインデックス作成（新形式）
    private func indexBookmarkFromReadingLog(pdfFileName: String, pageIndex: Int) async {
        print("indexBookmarkFromReadingLog: START for \(pdfFileName) page \(pageIndex)")

        guard vectorDB != nil else {
            print("indexBookmarkFromReadingLog: VectorDB not initialized")
            return
        }

        // 既にインデックスされているかチェック（新形式）
        if isPageIndexed(pdfFileName: pdfFileName, pageIndex: pageIndex) {
            print("indexBookmarkFromReadingLog: Already indexed: \(pdfFileName) page \(pageIndex)")
            return
        }

        // ReadingLogからテキスト取得
        let logs = await MainActor.run {
            HistoryManager.shared.logs
        }

        guard let log = logs.first(where: {
            $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex
        }) else {
            print("indexBookmarkFromReadingLog: No ReadingLog found for \(pdfFileName) page \(pageIndex)")
            return
        }

        let rawText = log.rawText
        guard !rawText.isEmpty else {
            print("indexBookmarkFromReadingLog: Empty rawText for \(pdfFileName) page \(pageIndex)")
            return
        }

        // indexFromRawTextに委譲（PDF統合インデックスを使用）
        await indexFromRawText(pdfFileName: pdfFileName, pageIndex: pageIndex, rawText: rawText)
    }
}

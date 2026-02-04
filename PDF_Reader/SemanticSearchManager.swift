import Foundation
import SwiftUI
import PDFKit
import Combine
import NaturalLanguage
import VecturaKit
import VecturaNLKit

// MARK: - Data Models

struct TextChunk: Codable, Identifiable {
    let id: UUID
    let bookId: UUID
    let pdfFileName: String
    let pageIndex: Int
    let chunkIndex: Int
    let text: String
    let isMarkerText: Bool  // マーカー箇所かどうか

    init(id: UUID = UUID(), bookId: UUID, pdfFileName: String, pageIndex: Int, chunkIndex: Int, text: String, isMarkerText: Bool = false) {
        self.id = id
        self.bookId = bookId
        self.pdfFileName = pdfFileName
        self.pageIndex = pageIndex
        self.chunkIndex = chunkIndex
        self.text = text
        self.isMarkerText = isMarkerText
    }

    var vectorId: String {
        "\(bookId.uuidString)_\(pageIndex)_\(chunkIndex)"
    }
}

struct SearchResultItem: Identifiable {
    let id = UUID()
    let bookId: UUID
    let pdfFileName: String
    let pageIndex: Int
    let matchedText: String
    let score: Float
    let isMarkerText: Bool  // マーカー箇所かどうか
    let markerColor: MarkerColor?  // マーカーの色

    init(bookId: UUID, pdfFileName: String, pageIndex: Int, matchedText: String, score: Float, isMarkerText: Bool = false, markerColor: MarkerColor? = nil) {
        self.bookId = bookId
        self.pdfFileName = pdfFileName
        self.pageIndex = pageIndex
        self.matchedText = matchedText
        self.score = score
        self.isMarkerText = isMarkerText
        self.markerColor = markerColor
    }
}

// MARK: - Semantic Search Manager

@MainActor
class SemanticSearchManager: ObservableObject {
    static let shared = SemanticSearchManager()

    @Published var isIndexing = false
    @Published var indexingProgress: Float = 0.0
    @Published var indexingBookName: String = ""
    @Published var searchResults: [SearchResultItem] = []
    @Published var isSearching = false

    private var vectorDB: VecturaKit?
    private var embedder: NLContextualEmbedder?
    private var chunks: [TextChunk] = []
    private let chunksFileName = "text_chunks.json"

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var vecturaDirectory: URL {
        documentsDirectory.appendingPathComponent("VecturaKit")
    }

    private init() {
        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    func initialize() async {
        do {
            // Create VecturaKit directory if needed
            if !FileManager.default.fileExists(atPath: vecturaDirectory.path) {
                try FileManager.default.createDirectory(at: vecturaDirectory, withIntermediateDirectories: true)
            }

            // Initialize embedder with Japanese language support
            // Note: NLLanguage.japanese might not be available for embeddings
            // Fall back to English if Japanese is not supported
            if let japaneseEmbedder = try? await NLContextualEmbedder(language: .japanese) {
                embedder = japaneseEmbedder
            } else {
                print("Japanese embedder not available, falling back to English")
                if let englishEmbedder = try? await NLContextualEmbedder(language: .english) {
                    embedder = englishEmbedder
                } else {
                    print("English embedder also failed")
                    return
                }
            }

            guard let embedder = embedder else {
                print("Failed to create embedder")
                return
            }

            // Get dimension from embedder model info
            let modelInfo = await embedder.modelInfo
            let dimension = modelInfo.dimension

            // Initialize VecturaKit with embedder dimension (nil for auto-detect)
            let config = try VecturaConfig(
                name: "pdf-reader-search",
                dimension: dimension
            )
            vectorDB = try await VecturaKit(config: config, embedder: embedder)

            // Load existing chunks
            loadChunks()

            print("SemanticSearchManager initialized successfully")
        } catch {
            print("Failed to initialize SemanticSearchManager: \(error)")
        }
    }

    // MARK: - Indexing

    func indexBook(_ book: Book) async throws {
        guard let vectorDB = vectorDB else {
            throw SearchError.notInitialized
        }

        isIndexing = true
        indexingProgress = 0.0
        indexingBookName = book.fileName

        defer {
            isIndexing = false
            indexingProgress = 0.0
            indexingBookName = ""
        }

        let fileURL = LibraryManager.shared.getBookURL(book)
        guard let document = PDFDocument(url: fileURL) else {
            throw SearchError.pdfLoadFailed
        }

        let pageCount = document.pageCount
        var newChunks: [TextChunk] = []
        var texts: [String] = []
        var ids: [UUID] = []

        // Extract text from each page
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageText = extractText(from: page, pageIndex: pageIndex, book: book)
            let pageChunks = chunkText(pageText, bookId: book.id, pdfFileName: book.fileName, pageIndex: pageIndex)

            for chunk in pageChunks {
                newChunks.append(chunk)
                texts.append(chunk.text)
                ids.append(chunk.id)  // TextChunk.id (UUID) を使用
            }

            indexingProgress = Float(pageIndex + 1) / Float(pageCount)
        }

        // Add to vector database
        if !texts.isEmpty {
            _ = try await vectorDB.addDocuments(texts: texts, ids: ids)
        }

        // Save chunks
        chunks.append(contentsOf: newChunks)
        saveChunks()

        // Update book index status
        LibraryManager.shared.markBookAsIndexed(book)
    }

    func indexAllBooks() async {
        let books = LibraryManager.shared.books.filter { !$0.isIndexed }

        for book in books {
            do {
                try await indexBook(book)
            } catch {
                print("Failed to index \(book.fileName): \(error)")
            }
        }
    }

    // MARK: - Search

    /// 検索を実行（本棚フィルタ対応）
    /// - Parameters:
    ///   - query: 検索クエリ
    ///   - limit: 結果の最大数
    ///   - bookshelfId: フィルタする本棚ID（nilなら全体検索）
    func search(query: String, limit: Int = 20, bookshelfId: UUID? = nil) async throws -> [SearchResultItem] {
        guard let vectorDB = vectorDB else {
            throw SearchError.notInitialized
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        isSearching = true
        defer { isSearching = false }

        // 本棚フィルタがある場合、対象の本のIDを取得
        var targetBookIds: Set<UUID>? = nil
        if let shelfId = bookshelfId {
            let booksInShelf = LibraryManager.shared.getBooks(for: shelfId)
            targetBookIds = Set(booksInShelf.map { $0.id })
        }

        // フィルタがある場合は多めに取得してからフィルタリング
        let fetchLimit = targetBookIds != nil ? limit * 3 : limit
        let results = try await vectorDB.search(query: .text(query), numResults: fetchLimit)

        var searchResults: [SearchResultItem] = []

        for result in results {
            // result.id と chunk.id は両方 UUID 型
            guard let chunk = chunks.first(where: { $0.id == result.id }) else {
                continue
            }

            // 本棚フィルタが指定されている場合、対象の本のみ含める
            if let targetIds = targetBookIds {
                guard targetIds.contains(chunk.bookId) else { continue }
            }

            // マーカー情報を取得
            let markers = SmartMarkerManager.shared.getMarkers(for: chunk.pdfFileName, pageIndex: chunk.pageIndex)
            let matchingMarker = markers.first { marker in
                chunk.text.contains(marker.text) || marker.text.contains(chunk.text)
            }

            let item = SearchResultItem(
                bookId: chunk.bookId,
                pdfFileName: chunk.pdfFileName,
                pageIndex: chunk.pageIndex,
                matchedText: chunk.text,
                score: result.score,  // result.score は Float 型
                isMarkerText: chunk.isMarkerText || matchingMarker != nil,
                markerColor: matchingMarker?.color
            )
            searchResults.append(item)

            // 必要な数に達したら終了
            if searchResults.count >= limit { break }
        }

        // マーカー付きの結果を優先してソート
        searchResults.sort { item1, item2 in
            if item1.isMarkerText != item2.isMarkerText {
                return item1.isMarkerText  // マーカー付きを先に
            }
            return item1.score > item2.score  // スコアが高い（類似度が高い）順
        }

        self.searchResults = searchResults
        return searchResults
    }

    // MARK: - Text Extraction & Chunking

    private func extractText(from page: PDFPage, pageIndex: Int, book: Book) -> String {
        // First try PDFKit native text extraction
        if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        // Fallback: Check if we have Gemini OCR text from reading logs
        if let log = HistoryManager.shared.logs.first(where: {
            $0.pdfFileName == book.fileName && $0.pageIndex == pageIndex
        }) {
            return log.rawText
        }

        return ""
    }

    private func chunkText(
        _ text: String,
        bookId: UUID,
        pdfFileName: String,
        pageIndex: Int,
        targetSize: Int = 300,
        maxSize: Int = 500,
        overlap: Int = 50
    ) -> [TextChunk] {
        guard !text.isEmpty else { return [] }

        var chunks: [TextChunk] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。.！？!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var currentChunk = ""
        var chunkIndex = 0

        for sentence in sentences {
            let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + "。" + sentence

            if potentialChunk.count > maxSize {
                // Save current chunk if not empty
                if !currentChunk.isEmpty {
                    let chunk = TextChunk(
                        id: UUID(),
                        bookId: bookId,
                        pdfFileName: pdfFileName,
                        pageIndex: pageIndex,
                        chunkIndex: chunkIndex,
                        text: currentChunk
                    )
                    chunks.append(chunk)
                    chunkIndex += 1

                    // Keep overlap
                    let overlapText = String(currentChunk.suffix(overlap))
                    currentChunk = overlapText + "。" + sentence
                } else {
                    // Single sentence is too long, split it
                    let chunk = TextChunk(
                        id: UUID(),
                        bookId: bookId,
                        pdfFileName: pdfFileName,
                        pageIndex: pageIndex,
                        chunkIndex: chunkIndex,
                        text: String(sentence.prefix(maxSize))
                    )
                    chunks.append(chunk)
                    chunkIndex += 1
                    currentChunk = String(sentence.suffix(max(0, sentence.count - maxSize + overlap)))
                }
            } else if potentialChunk.count >= targetSize {
                let chunk = TextChunk(
                    id: UUID(),
                    bookId: bookId,
                    pdfFileName: pdfFileName,
                    pageIndex: pageIndex,
                    chunkIndex: chunkIndex,
                    text: potentialChunk
                )
                chunks.append(chunk)
                chunkIndex += 1

                // Keep overlap
                currentChunk = String(potentialChunk.suffix(overlap))
            } else {
                currentChunk = potentialChunk
            }
        }

        // Don't forget the last chunk
        if !currentChunk.isEmpty {
            let chunk = TextChunk(
                id: UUID(),
                bookId: bookId,
                pdfFileName: pdfFileName,
                pageIndex: pageIndex,
                chunkIndex: chunkIndex,
                text: currentChunk
            )
            chunks.append(chunk)
        }

        return chunks
    }

    // MARK: - Persistence

    private func saveChunks() {
        let url = documentsDirectory.appendingPathComponent(chunksFileName)
        do {
            let data = try JSONEncoder().encode(chunks)
            try data.write(to: url)
        } catch {
            print("Failed to save chunks: \(error)")
        }
    }

    private func loadChunks() {
        let url = documentsDirectory.appendingPathComponent(chunksFileName)
        do {
            let data = try Data(contentsOf: url)
            chunks = try JSONDecoder().decode([TextChunk].self, from: data)
        } catch {
            chunks = []
        }
    }

    // MARK: - Utility

    func removeIndex(for book: Book) {
        chunks.removeAll { $0.bookId == book.id }
        saveChunks()

        // Note: VecturaKit doesn't have a direct delete API in current version
        // For full cleanup, would need to reinitialize the database
    }

    func hasIndex(for book: Book) -> Bool {
        chunks.contains { $0.bookId == book.id }
    }

    var indexedBookCount: Int {
        Set(chunks.map { $0.bookId }).count
    }

    var totalChunkCount: Int {
        chunks.count
    }
}

// MARK: - Errors

enum SearchError: LocalizedError {
    case notInitialized
    case pdfLoadFailed
    case indexingFailed
    case searchFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "検索エンジンが初期化されていません"
        case .pdfLoadFailed:
            return "PDFの読み込みに失敗しました"
        case .indexingFailed:
            return "インデックス作成に失敗しました"
        case .searchFailed:
            return "検索に失敗しました"
        }
    }
}

import Foundation
import SwiftUI
import PDFKit
import Combine

struct Bookmark: Identifiable, Codable {
    var id = UUID()
    let pdfFileName: String
    let pageIndex: Int
    let createdAt: Date
}

class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()
    
    @Published var bookmarks: [Bookmark] = []
    
    private let fileName = "bookmarks.json"
    
    init() {
        loadBookmarks()
    }
    
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
    
    func addBookmark(pdfFileName: String, pageIndex: Int, bookId: UUID? = nil, pdfDocument: PDFDocument? = nil) {
        if !bookmarks.contains(where: { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex }) {
            let newBookmark = Bookmark(pdfFileName: pdfFileName, pageIndex: pageIndex, createdAt: Date())
            bookmarks.insert(newBookmark, at: 0)
            saveBookmarks()

            // バックグラウンドでインデックス作成
            Task {
                await BookmarkIndexManager.shared.indexBookmark(
                    bookId: bookId,
                    pdfFileName: pdfFileName,
                    pageIndex: pageIndex,
                    pdfDocument: pdfDocument
                )
            }
        }
    }
    
    func removeBookmark(pdfFileName: String, pageIndex: Int) {
        if let index = bookmarks.firstIndex(where: { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex }) {
            bookmarks.remove(at: index)
            saveBookmarks()

            // 保留中のインデックスタスクをキャンセル（3分以内なら無料枠節約）
            BookmarkIndexManager.shared.cancelScheduledIndexing(pdfFileName: pdfFileName, pageIndex: pageIndex)

            // インデックスも削除
            Task {
                await BookmarkIndexManager.shared.removeIndex(pdfFileName: pdfFileName, pageIndex: pageIndex)
            }
        }
    }
    
    func deleteBookmark(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        saveBookmarks()
    }
    
    func isBookmarked(pdfFileName: String, pageIndex: Int) -> Bool {
        return bookmarks.contains(where: { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex })
    }
    
    func getBookmarks(for pdfFileName: String) -> [Bookmark] {
        return bookmarks.filter { $0.pdfFileName == pdfFileName }
    }
    
    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: fileURL)
        } catch {
            print("しおり保存エラー: \(error)")
        }
    }
    
    private func loadBookmarks() {
        do {
            let data = try Data(contentsOf: fileURL)
            bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            bookmarks = []
        }
    }
}

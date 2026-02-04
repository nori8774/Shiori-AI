import SwiftUI
import PDFKit
import Combine

// 本のデータモデル
struct Book: Identifiable, Codable {
    var id = UUID()
    let fileName: String
    let importDate: Date
    // 開き方向の設定（nil = 未設定、true = 右開き、false = 左開き）
    var isRightToLeft: Bool?
    // セマンティック検索用インデックス作成済みフラグ
    var isIndexed: Bool = false
    // 所属する本棚のID（nilなら未分類）
    var bookshelfId: UUID?
}

class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var books: [Book] = []
    
    private let fileName = "library_books.json"
    
    init() {
        loadBooks()
    }
    
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func importPDF(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.copyItem(at: url, to: destinationURL)
            }
            
            // サムネイル生成
            if let document = PDFDocument(url: destinationURL),
               let page = document.page(at: 0) {
                let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox)
                saveThumbnail(image: thumbnail, id: destinationURL.lastPathComponent)
            }
            
            // 新規作成時は設定なし(nil)
            let newBook = Book(fileName: url.lastPathComponent, importDate: Date(), isRightToLeft: nil)
            
            DispatchQueue.main.async {
                self.books.insert(newBook, at: 0)
                self.saveBooks()
            }
        } catch {
            print("インポート失敗: \(error)")
        }
    }
    
    // 本の設定（開き方向）を更新して保存する
    func updateBookDirection(book: Book, isRightToLeft: Bool) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            var updatedBook = books[index]
            updatedBook.isRightToLeft = isRightToLeft
            books[index] = updatedBook
            saveBooks()
        }
    }

    // 本をインデックス済みとしてマーク
    func markBookAsIndexed(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            var updatedBook = books[index]
            updatedBook.isIndexed = true
            books[index] = updatedBook
            saveBooks()
        }
    }

    // 本のインデックスフラグをリセット
    func markBookAsUnindexed(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            var updatedBook = books[index]
            updatedBook.isIndexed = false
            books[index] = updatedBook
            saveBooks()
        }
    }

    // MARK: - Bookshelf Operations

    // 本の本棚を変更
    func moveBookToShelf(_ book: Book, shelfId: UUID?) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            var updatedBook = books[index]
            updatedBook.bookshelfId = shelfId
            books[index] = updatedBook
            saveBooks()
        }
    }

    // 指定した本棚に所属する本を取得
    func getBooks(for shelfId: UUID?) -> [Book] {
        if let shelfId = shelfId {
            return books.filter { $0.bookshelfId == shelfId }
        } else {
            // shelfIdがnilなら全ての本を返す
            return books
        }
    }

    // 本棚が削除された時、その本棚に所属していた本のbookshelfIdをnilに
    func clearBookshelfForBooks(bookshelfId: UUID) {
        for (index, book) in books.enumerated() {
            if book.bookshelfId == bookshelfId {
                var updatedBook = book
                updatedBook.bookshelfId = nil
                books[index] = updatedBook
            }
        }
        saveBooks()
    }

    // PDFを直接保存（論文要約PDF生成時に使用）
    func savePDFDirectly(data: Data, fileName: String, bookshelfId: UUID?) -> Book? {
        let destinationURL = documentsDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: destinationURL)

            // サムネイル生成
            if let document = PDFDocument(data: data),
               let page = document.page(at: 0) {
                let thumbnail = page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox)
                saveThumbnail(image: thumbnail, id: fileName)
            }

            let newBook = Book(
                fileName: fileName,
                importDate: Date(),
                isRightToLeft: false,
                isIndexed: false,
                bookshelfId: bookshelfId
            )

            DispatchQueue.main.async {
                self.books.insert(newBook, at: 0)
                self.saveBooks()
            }

            return newBook
        } catch {
            print("PDF保存失敗: \(error)")
            return nil
        }
    }

    func deleteBook(at offsets: IndexSet) {
        offsets.forEach { index in
            let book = books[index]
            let fileURL = documentsDirectory.appendingPathComponent(book.fileName)
            try? FileManager.default.removeItem(at: fileURL)
            deleteThumbnail(id: book.fileName)
        }
        books.remove(atOffsets: offsets)
        saveBooks()
    }
    
    func getBookURL(_ book: Book) -> URL {
        return documentsDirectory.appendingPathComponent(book.fileName)
    }
    
    func getThumbnail(for book: Book) -> UIImage? {
        let path = documentsDirectory.appendingPathComponent("thumb_\(book.fileName).jpg")
        if let data = try? Data(contentsOf: path) {
            return UIImage(data: data)
        }
        return nil
    }
    
    private func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: documentsDirectory.appendingPathComponent(fileName))
        }
    }
    
    private func loadBooks() {
        let url = documentsDirectory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Book].self, from: data) {
            books = loaded
        }
    }
    
    private func saveThumbnail(image: UIImage, id: String) {
        if let data = image.jpegData(compressionQuality: 0.7) {
            let path = documentsDirectory.appendingPathComponent("thumb_\(id).jpg")
            try? data.write(to: path)
        }
    }
    
    private func deleteThumbnail(id: String) {
        let path = documentsDirectory.appendingPathComponent("thumb_\(id).jpg")
        try? FileManager.default.removeItem(at: path)
    }
}

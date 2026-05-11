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
    // 最後に読んだページ（読書位置の記憶用）
    var lastReadPage: Int = 0
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
    
    /// ファイル形式を判定してインポート
    func importFile(from url: URL) {
        if url.pathExtension.lowercased() == "ebk" {
            importEBK(from: url)
        } else {
            importPDF(from: url)
        }
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

    /// 青空文庫.ebkファイルをPDFに変換してインポート
    func importEBK(from url: URL, fontSize: EBKFontSize = .medium) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            print("[EBK] 読み込み開始: \(url.lastPathComponent)")
            let data = try Data(contentsOf: url)
            print("[EBK] ファイルサイズ: \(data.count) bytes")

            let parser = EBKParser()
            let content = try parser.parse(data: data)
            print("[EBK] パース完了: \(content.metadata.title) by \(content.metadata.author)")
            print("[EBK] 本文: \(content.bodyText.count) chars, ルビ: \(content.rubyAnnotations.count)")

            // PDFに変換
            print("[EBK] PDF変換開始（文字サイズ: \(fontSize.rawValue)）...")
            let converter = EBKToPDFConverter(fontSize: fontSize)
            let pdfData = converter.convert(content: content)
            print("[EBK] PDF変換完了: \(pdfData.count) bytes")

            // ファイル名: "著者 - タイトル.pdf"
            let pdfFileName = "\(content.metadata.author) - \(content.metadata.title).pdf"
            let destinationURL = documentsDirectory.appendingPathComponent(pdfFileName)

            try pdfData.write(to: destinationURL)
            print("[EBK] PDF保存完了: \(pdfFileName)")

            // サムネイル生成（書籍風の表紙）
            let thumbnail = generateBookCoverThumbnail(
                title: content.metadata.title,
                author: content.metadata.author
            )
            saveThumbnail(image: thumbnail, id: pdfFileName)
            print("[EBK] サムネイル生成完了")

            // 青空文庫はデフォルト右開き（縦書き）
            let newBook = Book(fileName: pdfFileName, importDate: Date(), isRightToLeft: true)

            DispatchQueue.main.async {
                self.books.insert(newBook, at: 0)
                self.saveBooks()
                print("[EBK] ライブラリ追加完了")
            }
        } catch {
            print("EBKインポート失敗: \(error)")
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

    // 最後に読んだページを更新
    func updateLastReadPage(book: Book, pageIndex: Int) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index].lastReadPage = pageIndex
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
    
    /// 青空文庫用の書籍風サムネイル生成（縦書き、白黒）
    private func generateBookCoverThumbnail(title: String, author: String) -> UIImage {
        let size = CGSize(width: 300, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            // 背景（白）
            UIColor.white.setFill()
            ctx.fill(rect)

            // 枠線
            UIColor.black.setStroke()
            let borderRect = rect.insetBy(dx: 8, dy: 8)
            let borderPath = UIBezierPath(rect: borderRect)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // 内側の飾り枠
            let innerRect = rect.insetBy(dx: 14, dy: 14)
            let innerPath = UIBezierPath(rect: innerRect)
            innerPath.lineWidth = 0.5
            innerPath.stroke()

            // タイトル（縦書き：中央に上から下へ）
            let titleFont = UIFont(name: "HiraMinProN-W6", size: 28)
                ?? UIFont.boldSystemFont(ofSize: 28)
            let titleChars = Array(title)
            let titleX = size.width / 2 - 14  // 中央
            let titleStartY: CGFloat = 40
            let titleCharSpacing: CGFloat = 34

            // タイトルが長い場合は2列に
            let maxCharsPerCol = Int((size.height - 80) / titleCharSpacing)
            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.alignment = .center

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor.black
            ]

            if titleChars.count <= maxCharsPerCol {
                // 1列
                for (i, ch) in titleChars.enumerated() {
                    let y = titleStartY + CGFloat(i) * titleCharSpacing
                    let str = String(ch)
                    let attrStr = NSAttributedString(string: str, attributes: titleAttrs)
                    let strSize = attrStr.size()
                    attrStr.draw(at: CGPoint(x: titleX - strSize.width / 2, y: y))
                }
            } else {
                // 2列（右から左）
                let col1X = size.width / 2 + 10
                let col2X = size.width / 2 - 38

                for (i, ch) in titleChars.enumerated() {
                    let col = i / maxCharsPerCol
                    let row = i % maxCharsPerCol
                    let x = col == 0 ? col1X : col2X
                    let y = titleStartY + CGFloat(row) * titleCharSpacing
                    let str = String(ch)
                    let attrStr = NSAttributedString(string: str, attributes: titleAttrs)
                    let strSize = attrStr.size()
                    attrStr.draw(at: CGPoint(x: x - strSize.width / 2, y: y))
                }
            }

            // 著者名（縦書き：左寄りに上から下へ）
            let authorFont = UIFont(name: "HiraMinProN-W3", size: 16)
                ?? UIFont.systemFont(ofSize: 16)
            let authorAttrs: [NSAttributedString.Key: Any] = [
                .font: authorFont,
                .foregroundColor: UIColor.darkGray
            ]
            let authorChars = Array(author)
            let authorX = size.width - 50
            let authorStartY: CGFloat = 60

            for (i, ch) in authorChars.enumerated() {
                let y = authorStartY + CGFloat(i) * 22
                let str = String(ch)
                let attrStr = NSAttributedString(string: str, attributes: authorAttrs)
                let strSize = attrStr.size()
                attrStr.draw(at: CGPoint(x: authorX - strSize.width / 2, y: y))
            }
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

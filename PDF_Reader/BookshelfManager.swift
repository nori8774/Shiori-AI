import SwiftUI
import Combine

// MARK: - Bookshelf Model

struct Bookshelf: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String           // SF Symbolsアイコン名
    var colorHex: String       // カラーコード
    let isSystemShelf: Bool    // システム本棚（削除不可）
    var sortOrder: Int         // 表示順序
    let createdAt: Date

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    static func == (lhs: Bookshelf, rhs: Bookshelf) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - System Shelf IDs (固定UUID)

enum SystemShelfID {
    // 「すべて」は仮想本棚なのでIDは不要
    static let summaries = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

// MARK: - Bookshelf Manager

class BookshelfManager: ObservableObject {
    static let shared = BookshelfManager()

    @Published var bookshelves: [Bookshelf] = []
    @Published var selectedShelfId: UUID? = nil  // nilは「すべて」

    private let fileName = "bookshelves.json"

    private init() {
        loadBookshelves()
        initializeSystemShelvesIfNeeded()
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - System Shelves Initialization

    private func initializeSystemShelvesIfNeeded() {
        // 「要約」本棚が存在しない場合は作成
        if !bookshelves.contains(where: { $0.id == SystemShelfID.summaries }) {
            let summaryShelf = Bookshelf(
                id: SystemShelfID.summaries,
                name: "要約",
                icon: "doc.text.magnifyingglass",
                colorHex: "#34C759",
                isSystemShelf: true,
                sortOrder: 0,
                createdAt: Date()
            )
            bookshelves.insert(summaryShelf, at: 0)
            saveBookshelves()
        }
    }

    // MARK: - CRUD Operations

    func createBookshelf(name: String, icon: String = "folder", colorHex: String = "#007AFF") -> Bookshelf {
        let maxOrder = bookshelves.map { $0.sortOrder }.max() ?? 0
        let newShelf = Bookshelf(
            id: UUID(),
            name: name,
            icon: icon,
            colorHex: colorHex,
            isSystemShelf: false,
            sortOrder: maxOrder + 1,
            createdAt: Date()
        )
        bookshelves.append(newShelf)
        sortBookshelves()
        saveBookshelves()
        return newShelf
    }

    func updateBookshelf(_ shelf: Bookshelf, name: String? = nil, icon: String? = nil, colorHex: String? = nil) {
        guard let index = bookshelves.firstIndex(where: { $0.id == shelf.id }) else { return }

        var updated = bookshelves[index]
        if let name = name { updated.name = name }
        if let icon = icon { updated.icon = icon }
        if let colorHex = colorHex { updated.colorHex = colorHex }

        bookshelves[index] = updated
        saveBookshelves()
    }

    func deleteBookshelf(_ shelf: Bookshelf) {
        // システム本棚は削除不可
        guard !shelf.isSystemShelf else { return }

        bookshelves.removeAll { $0.id == shelf.id }

        // この本棚に所属していた本はbookshelfIdをnilに
        LibraryManager.shared.clearBookshelfForBooks(bookshelfId: shelf.id)

        saveBookshelves()
    }

    func reorderBookshelves(from source: IndexSet, to destination: Int) {
        bookshelves.move(fromOffsets: source, toOffset: destination)

        // sortOrderを更新
        for (index, _) in bookshelves.enumerated() {
            bookshelves[index].sortOrder = index
        }

        saveBookshelves()
    }

    // MARK: - Selection

    func selectShelf(_ shelf: Bookshelf?) {
        selectedShelfId = shelf?.id
    }

    func selectAllBooks() {
        selectedShelfId = nil
    }

    var selectedShelf: Bookshelf? {
        guard let id = selectedShelfId else { return nil }
        return bookshelves.first { $0.id == id }
    }

    // MARK: - Helpers

    func getBookshelf(by id: UUID) -> Bookshelf? {
        return bookshelves.first { $0.id == id }
    }

    func getSummaryShelf() -> Bookshelf? {
        return bookshelves.first { $0.id == SystemShelfID.summaries }
    }

    func moveBookshelves(from source: IndexSet, to destination: Int) {
        reorderBookshelves(from: source, to: destination)
    }

    func bookCount(for shelf: Bookshelf) -> Int {
        return LibraryManager.shared.books.filter { $0.bookshelfId == shelf.id }.count
    }

    // MARK: - Persistence

    private func sortBookshelves() {
        bookshelves.sort { $0.sortOrder < $1.sortOrder }
    }

    private func saveBookshelves() {
        do {
            let data = try JSONEncoder().encode(bookshelves)
            try data.write(to: documentsDirectory.appendingPathComponent(fileName))
        } catch {
            print("本棚の保存に失敗: \(error)")
        }
    }

    private func loadBookshelves() {
        let url = documentsDirectory.appendingPathComponent(fileName)
        do {
            let data = try Data(contentsOf: url)
            bookshelves = try JSONDecoder().decode([Bookshelf].self, from: data)
            sortBookshelves()
        } catch {
            bookshelves = []
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#007AFF"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Preset Colors for Bookshelf

struct BookshelfColors {
    static let presets: [(name: String, hex: String)] = [
        ("ブルー", "#007AFF"),
        ("グリーン", "#34C759"),
        ("オレンジ", "#FF9500"),
        ("レッド", "#FF3B30"),
        ("パープル", "#AF52DE"),
        ("ピンク", "#FF2D55"),
        ("ティール", "#5AC8FA"),
        ("インディゴ", "#5856D6")
    ]
}

// MARK: - Preset Icons for Bookshelf

struct BookshelfIcons {
    static let presets: [(name: String, icon: String)] = [
        ("フォルダ", "folder"),
        ("本", "book"),
        ("論文", "doc.text"),
        ("星", "star"),
        ("ハート", "heart"),
        ("フラグ", "flag"),
        ("タグ", "tag"),
        ("ブックマーク", "bookmark"),
        ("卒業", "graduationcap"),
        ("電球", "lightbulb"),
        ("脳", "brain"),
        ("コード", "chevron.left.forwardslash.chevron.right")
    ]
}

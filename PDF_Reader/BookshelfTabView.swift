import SwiftUI

// MARK: - Bookshelf Tab View (横スクロールタブ)

struct BookshelfTabView: View {
    @ObservedObject var bookshelfManager = BookshelfManager.shared
    @State private var showNewShelfSheet = false
    @State private var showEditShelfSheet = false
    @State private var shelfToEdit: Bookshelf?
    @State private var showManagerSheet = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 「すべて」タブ（仮想本棚）
                    BookshelfTabItem(
                        name: "すべて",
                        icon: "books.vertical",
                        color: .blue,
                        isSelected: bookshelfManager.selectedShelfId == nil,
                        onTap: {
                            bookshelfManager.selectAllBooks()
                        },
                        onLongPress: nil
                    )

                    // 各本棚タブ
                    ForEach(bookshelfManager.bookshelves) { shelf in
                        BookshelfTabItem(
                            name: shelf.name,
                            icon: shelf.icon,
                            color: shelf.color,
                            isSelected: bookshelfManager.selectedShelfId == shelf.id,
                            onTap: {
                                bookshelfManager.selectShelf(shelf)
                            },
                            onLongPress: shelf.isSystemShelf ? nil : {
                                shelfToEdit = shelf
                                showEditShelfSheet = true
                            }
                        )
                    }

                    // 新規本棚追加ボタン
                    Button(action: { showNewShelfSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                            Text("追加")
                                .font(.caption)
                        }
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // 本棚管理ボタン（右端に固定）
            Button(action: { showManagerSheet = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(10)
            }
            .padding(.trailing, 8)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showNewShelfSheet) {
            BookshelfEditorView(mode: .create)
        }
        .sheet(isPresented: $showEditShelfSheet) {
            if let shelf = shelfToEdit {
                BookshelfEditorView(mode: .edit(shelf))
            }
        }
        .sheet(isPresented: $showManagerSheet) {
            BookshelfManagerView()
        }
    }
}

// MARK: - Bookshelf Tab Item

struct BookshelfTabItem: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? color : color.opacity(0.15))
            .cornerRadius(16)
        }
        .onLongPressGesture {
            onLongPress?()
        }
    }
}

// MARK: - Bookshelf Editor View (作成・編集)

struct BookshelfEditorView: View {
    enum Mode {
        case create
        case edit(Bookshelf)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookshelfManager = BookshelfManager.shared

    @State private var name: String = ""
    @State private var selectedIcon: String = "folder"
    @State private var selectedColorHex: String = "#007AFF"
    @State private var showDeleteConfirm = false

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var editingShelf: Bookshelf? {
        if case .edit(let shelf) = mode { return shelf }
        return nil
    }

    var body: some View {
        NavigationView {
            Form {
                // 本棚名
                Section(header: Text("本棚名")) {
                    TextField("本棚の名前", text: $name)
                }

                // アイコン選択
                Section(header: Text("アイコン")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(BookshelfIcons.presets, id: \.icon) { preset in
                            Button(action: { selectedIcon = preset.icon }) {
                                Image(systemName: preset.icon)
                                    .font(.title2)
                                    .foregroundColor(selectedIcon == preset.icon ? .white : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(selectedIcon == preset.icon ? Color(hex: selectedColorHex) ?? .blue : Color.gray.opacity(0.15))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // カラー選択
                Section(header: Text("カラー")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(BookshelfColors.presets, id: \.hex) { preset in
                            Button(action: { selectedColorHex = preset.hex }) {
                                Circle()
                                    .fill(Color(hex: preset.hex) ?? .blue)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColorHex == preset.hex ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.2), lineWidth: selectedColorHex == preset.hex ? 1 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // 削除（編集時のみ）
                if isEditing, let shelf = editingShelf, !shelf.isSystemShelf {
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirm = true }) {
                            HStack {
                                Spacer()
                                Text("この本棚を削除")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "本棚を編集" : "新規本棚")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if case .edit(let shelf) = mode {
                    name = shelf.name
                    selectedIcon = shelf.icon
                    selectedColorHex = shelf.colorHex
                }
            }
            .alert("本棚を削除", isPresented: $showDeleteConfirm) {
                Button("削除", role: .destructive) {
                    if let shelf = editingShelf {
                        bookshelfManager.deleteBookshelf(shelf)
                        dismiss()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この本棚を削除しますか？\n中の本は「すべて」に残ります。")
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if case .edit(let shelf) = mode {
            bookshelfManager.updateBookshelf(shelf, name: trimmedName, icon: selectedIcon, colorHex: selectedColorHex)
        } else {
            _ = bookshelfManager.createBookshelf(name: trimmedName, icon: selectedIcon, colorHex: selectedColorHex)
        }
    }
}

// MARK: - Bookshelf Picker (本の移動用)

struct BookshelfPickerView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookshelfManager = BookshelfManager.shared
    @ObservedObject var libraryManager = LibraryManager.shared

    var body: some View {
        NavigationView {
            List {
                // 未分類
                Button(action: {
                    libraryManager.moveBookToShelf(book, shelfId: nil)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.gray)
                        Text("未分類")
                            .foregroundColor(.primary)
                        Spacer()
                        if book.bookshelfId == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }

                // 各本棚
                ForEach(bookshelfManager.bookshelves) { shelf in
                    Button(action: {
                        libraryManager.moveBookToShelf(book, shelfId: shelf.id)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: shelf.icon)
                                .foregroundColor(shelf.color)
                            Text(shelf.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if book.bookshelfId == shelf.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("本棚を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Import Bookshelf Picker View (インポート直後用)

struct ImportBookshelfPickerView: View {
    let book: Book
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookshelfManager = BookshelfManager.shared
    @ObservedObject var libraryManager = LibraryManager.shared
    @State private var showNewShelfSheet = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // ヘッダー説明
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text("本棚を選択")
                        .font(.headline)
                    Text("「\(book.fileName)」をどの本棚に追加しますか？")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)

                List {
                    // 未分類
                    Button(action: {
                        libraryManager.moveBookToShelf(book, shelfId: nil)
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "tray")
                                .font(.title3)
                                .foregroundColor(.gray)
                                .frame(width: 32)
                            Text("未分類")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    // 各本棚
                    ForEach(bookshelfManager.bookshelves) { shelf in
                        Button(action: {
                            libraryManager.moveBookToShelf(book, shelfId: shelf.id)
                            isPresented = false
                        }) {
                            HStack {
                                Image(systemName: shelf.icon)
                                    .font(.title3)
                                    .foregroundColor(shelf.color)
                                    .frame(width: 32)
                                Text(shelf.name)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // 新規本棚作成
                    Button(action: { showNewShelfSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.green)
                                .frame(width: 32)
                            Text("新しい本棚を作成...")
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("本棚に追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("スキップ") {
                        isPresented = false
                    }
                }
            }
            .sheet(isPresented: $showNewShelfSheet) {
                BookshelfEditorView(mode: .create)
            }
        }
    }
}

// MARK: - Bookshelf Manager View (本棚一覧管理画面)

struct BookshelfManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookshelfManager = BookshelfManager.shared
    @State private var showNewShelfSheet = false
    @State private var shelfToEdit: Bookshelf?
    @State private var showEditSheet = false

    var body: some View {
        NavigationView {
            List {
                // 説明セクション
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("本棚を追加・編集・並べ替えできます。長押しで編集、スワイプで削除できます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // すべて（仮想本棚）
                Section(header: Text("仮想本棚")) {
                    HStack {
                        Image(systemName: "books.vertical")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("すべて")
                                .font(.body)
                            Text("すべての本を表示します")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("システム")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 4)
                }

                // ユーザー作成本棚
                Section(header: Text("本棚")) {
                    if bookshelfManager.bookshelves.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("本棚がありません")
                                    .foregroundColor(.secondary)
                                Text("下のボタンから追加できます")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        ForEach(bookshelfManager.bookshelves) { shelf in
                            HStack {
                                Image(systemName: shelf.icon)
                                    .font(.title3)
                                    .foregroundColor(shelf.color)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shelf.name)
                                        .font(.body)
                                    Text("\(bookshelfManager.bookCount(for: shelf))冊")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if shelf.isSystemShelf {
                                    Text("システム")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !shelf.isSystemShelf {
                                    shelfToEdit = shelf
                                    showEditSheet = true
                                }
                            }
                        }
                        .onDelete(perform: deleteShelves)
                        .onMove(perform: moveShelves)
                    }
                }

                // 新規本棚追加
                Section {
                    Button(action: { showNewShelfSheet = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.green)
                                .frame(width: 32)
                            Text("新しい本棚を作成")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("本棚の管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .sheet(isPresented: $showNewShelfSheet) {
                BookshelfEditorView(mode: .create)
            }
            .sheet(isPresented: $showEditSheet) {
                if let shelf = shelfToEdit {
                    BookshelfEditorView(mode: .edit(shelf))
                }
            }
        }
    }

    private func deleteShelves(at offsets: IndexSet) {
        for index in offsets {
            let shelf = bookshelfManager.bookshelves[index]
            if !shelf.isSystemShelf {
                bookshelfManager.deleteBookshelf(shelf)
            }
        }
    }

    private func moveShelves(from source: IndexSet, to destination: Int) {
        bookshelfManager.moveBookshelves(from: source, to: destination)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        BookshelfTabView()
        Spacer()
    }
}

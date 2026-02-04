import SwiftUI

struct SearchView: View {
    @ObservedObject var searchManager = SemanticSearchManager.shared
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var bookshelfManager = BookshelfManager.shared

    @State private var searchQuery = ""
    @State private var showIndexingAlert = false
    @State private var errorMessage: String?
    @State private var searchScope: SearchScope = .all

    enum SearchScope: Equatable {
        case all
        case currentShelf
    }

    // Callback when user taps a search result
    var onResultSelected: ((SearchResultItem) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                searchBar

                // Search Scope Picker (本棚が選択されている場合のみ表示)
                if bookshelfManager.selectedShelfId != nil {
                    searchScopePicker
                }

                // Index Status
                indexStatusSection

                // Results or Placeholder
                if searchManager.isSearching {
                    loadingView
                } else if !searchQuery.isEmpty && searchManager.searchResults.isEmpty {
                    noResultsView
                } else if searchManager.searchResults.isEmpty {
                    placeholderView
                } else {
                    resultsList
                }
            }
            .navigationTitle("検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .alert("インデックス作成", isPresented: $showIndexingAlert) {
                Button("作成する") {
                    Task {
                        await searchManager.indexAllBooks()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("全ての書籍のインデックスを作成します。\nこれには数分かかる場合があります。")
            }
            .alert(item: Binding<AlertItem?>(
                get: { errorMessage.map { AlertItem(message: $0) } },
                set: { _ in errorMessage = nil }
            )) { item in
                Alert(title: Text("エラー"), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("キーワードで検索...", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchManager.searchResults = []
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    // MARK: - Index Status Section

    private var indexStatusSection: some View {
        VStack(spacing: 8) {
            if searchManager.isIndexing {
                // Indexing in progress
                VStack(spacing: 8) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("インデックス作成中: \(searchManager.indexingBookName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: searchManager.indexingProgress)
                        .progressViewStyle(.linear)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                // Index stats
                HStack {
                    let unindexedCount = libraryManager.books.filter { !$0.isIndexed }.count
                    let indexedCount = libraryManager.books.filter { $0.isIndexed }.count

                    if indexedCount > 0 {
                        Label("\(indexedCount)冊インデックス済み", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if unindexedCount > 0 {
                        Button(action: { showIndexingAlert = true }) {
                            Label("\(unindexedCount)冊未インデックス", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()

                    if unindexedCount > 0 {
                        Button("全てインデックス") {
                            showIndexingAlert = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(searchManager.searchResults) { result in
                SearchResultRow(result: result)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onResultSelected?(result)
                        dismiss()
                    }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Placeholder Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("検索中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("「\(searchQuery)」に一致する結果がありません")
                .foregroundColor(.secondary)
            Text("別のキーワードで試してみてください")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            Text("キーワードを入力して検索")
                .foregroundColor(.secondary)
            Text(searchScopeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search Scope Picker

    private var searchScopePicker: some View {
        Picker("検索範囲", selection: $searchScope) {
            Text("すべての本棚").tag(SearchScope.all)
            if let shelf = bookshelfManager.selectedShelf {
                Text("「\(shelf.name)」のみ").tag(SearchScope.currentShelf)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var searchScopeDescription: String {
        if searchScope == .currentShelf, let shelf = bookshelfManager.selectedShelf {
            return "「\(shelf.name)」内から関連する内容を見つけます"
        }
        return "全ての書籍から関連する内容を見つけます"
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // 検索スコープに応じて本棚IDを指定
        let shelfId: UUID? = (searchScope == .currentShelf) ? bookshelfManager.selectedShelfId : nil

        Task {
            do {
                _ = try await searchManager.search(query: searchQuery, bookshelfId: shelfId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Book name and page
            HStack {
                // マーカーアイコン（マーカー箇所の場合）
                if result.isMarkerText {
                    Circle()
                        .fill(result.markerColor?.swiftUIColor ?? Color.yellow.opacity(0.5))
                        .frame(width: 12, height: 12)
                }

                Image(systemName: "doc.text")
                    .foregroundColor(.blue)

                Text(result.pdfFileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                // マーカーバッジ
                if result.isMarkerText {
                    Text("マーカー")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(result.markerColor?.swiftUIColor ?? Color.yellow)
                        .cornerRadius(4)
                }

                Text("p.\(result.pageIndex + 1)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
            }

            // Matched text preview
            Text(result.matchedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Score indicator
            HStack {
                Text("関連度")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(scoreColor)
                            .frame(width: geometry.size.width * CGFloat(normalizedScore), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 8)
    }

    private var normalizedScore: Float {
        // VecturaKit returns distance (lower is better)
        // Normalize to 0-1 range for display (higher is better)
        max(0, min(1, 1 - result.score))
    }

    private var scoreColor: Color {
        if normalizedScore > 0.7 {
            return .green
        } else if normalizedScore > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    SearchView()
}

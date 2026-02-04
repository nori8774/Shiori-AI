import SwiftUI
import PDFKit

struct SemanticSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var indexManager = BookmarkIndexManager.shared

    @State private var searchQuery = ""
    @State private var searchResults: [RankedPageResult] = []  // リランキング結果を使用
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    // ページジャンプ用のコールバック（dismissしない版も追加）
    var onPageSelected: ((String, Int) -> Void)?
    var keepOpenAfterSelection: Bool = true  // デフォルトで検索結果を保持

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 検索バー
                searchBar

                Divider()

                // コンテンツ
                if isSearching {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if searchResults.isEmpty && hasSearched {
                    emptyResultsView
                } else if searchResults.isEmpty {
                    instructionView
                } else {
                    resultsList
                }
            }
            .navigationTitle("しおり検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 検索結果クリアボタン
                        if !searchResults.isEmpty {
                            Button(action: {
                                searchResults = []
                                searchQuery = ""
                                hasSearched = false
                            }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                        }

                        if indexManager.isIndexing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("\(indexManager.indexedCount)件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Menu {
                            Button(action: rebuildIndexes) {
                                Label("インデックス再構築", systemImage: "arrow.clockwise")
                            }
                            .disabled(indexManager.isIndexing)

                            Button(role: .destructive, action: clearIndexes) {
                                Label("インデックス削除", systemImage: "trash")
                            }
                            .disabled(indexManager.isIndexing)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Views

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("何について書いてあったページを探す？", text: $searchQuery)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchResults = []
                    hasSearched = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            // 検索ボタン追加
            Button(action: {
                performSearch()
            }) {
                Text("検索")
                    .fontWeight(.medium)
            }
            .disabled(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("検索中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("再試行") {
                performSearch()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("該当するしおりが見つかりませんでした")
                .foregroundColor(.secondary)
            Text("別のキーワードで試してみてください")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var instructionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))

            VStack(spacing: 8) {
                Text("しおりページを検索")
                    .font(.headline)

                Text("しおりを付けたページの中から\n関連する内容を探します")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if indexManager.indexedCount == 0 {
                VStack(spacing: 8) {
                    Text("インデックスされたしおりがありません")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("しおりを追加すると自動的にインデックスされます")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button(action: rebuildIndexes) {
                        Label("履歴から再構築", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding(.top, 8)
            } else {
                Button(action: rebuildIndexes) {
                    Label("インデックス再構築", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }

            if let progress = indexManager.indexingProgress {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults) { result in
                    RankedPageResultCard(result: result) {
                        // ページジャンプ
                        onPageSelected?(result.pdfFileName, result.pageIndex)
                        // keepOpenAfterSelectionがfalseの場合のみdismiss
                        if !keepOpenAfterSelection {
                            dismiss()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func performSearch() {
        print("performSearch() called")
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Query after trim: '\(query)'")
        guard !query.isEmpty else {
            print("Query is empty, returning")
            return
        }

        // 検索開始時に前回の結果をクリア
        searchResults = []
        isSearching = true
        errorMessage = nil
        hasSearched = true
        print("Starting search task...")

        Task {
            do {
                print("Calling indexManager.searchWithReranking...")
                // リランキング付き検索（上位5件）
                let results = try await indexManager.searchWithReranking(query: query, topK: 5)
                print("Search returned \(results.count) results")
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                print("Search error: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }

    private func rebuildIndexes() {
        print("rebuildIndexes: button tapped")
        Task {
            print("rebuildIndexes: starting Task")
            await indexManager.rebuildAllIndexes()
            print("rebuildIndexes: Task completed")
        }
    }

    private func clearIndexes() {
        Task {
            await indexManager.clearAllIndexes()
        }
    }
}

// MARK: - Ranked Page Result Card (リランキング版)

struct RankedPageResultCard: View {
    let result: RankedPageResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // PDF名とページ番号
                HStack {
                    Image(systemName: "book.closed")
                        .foregroundColor(.blue)

                    Text(result.pdfFileName.replacingOccurrences(of: ".pdf", with: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    // ページ番号
                    Text("p.\(result.pageIndex + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue.opacity(0.1))
                        )

                    // スコア表示
                    Text(String(format: "%.0f%%", result.score * 100))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(scoreColor(result.score).opacity(0.2))
                        )

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // 要約
                Text(result.summary)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // マーカーテキスト（あれば）
                if let markerTexts = result.markerTexts, !markerTexts.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "highlighter")
                            .font(.caption2)
                            .foregroundColor(.orange)

                        Text(markerTexts.joined(separator: " / "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func scoreColor(_ score: Float) -> Color {
        if score >= 0.7 {
            return .green
        } else if score >= 0.5 {
            return .orange
        } else {
            return .gray
        }
    }
}

#Preview {
    SemanticSearchView()
}

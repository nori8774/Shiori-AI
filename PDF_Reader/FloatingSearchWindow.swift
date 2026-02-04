import SwiftUI
import Combine

/// フローティング検索ウィンドウの状態管理
class FloatingSearchState: ObservableObject {
    static let shared = FloatingSearchState()

    @Published var isVisible = false
    @Published var isMinimized = false
    @Published var searchQuery = ""
    @Published var searchResults: [RankedPageResult] = []
    @Published var hasSearched = false
    @Published var isSearching = false
    @Published var errorMessage: String?

    // ウィンドウ位置とサイズ
    @Published var position: CGPoint = CGPoint(x: 100, y: 100)
    @Published var size: CGSize = CGSize(width: 350, height: 400)

    private init() {}

    func show() {
        isVisible = true
        isMinimized = false
    }

    func hide() {
        isVisible = false
    }

    func toggle() {
        if isVisible {
            isMinimized.toggle()
        } else {
            show()
        }
    }

    func clearResults() {
        searchResults = []
        searchQuery = ""
        hasSearched = false
        errorMessage = nil
    }
}

/// フローティング検索ウィンドウ
struct FloatingSearchWindow: View {
    @ObservedObject var state = FloatingSearchState.shared
    @ObservedObject var indexManager = BookmarkIndexManager.shared

    var onPageSelected: ((String, Int) -> Void)?

    // ドラッグ用
    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        if state.isVisible {
            VStack(spacing: 0) {
                // ヘッダー（ドラッグハンドル）
                headerView

                if !state.isMinimized {
                    // 検索バー
                    searchBar

                    Divider()

                    // コンテンツ
                    contentView
                }
            }
            .frame(width: state.isMinimized ? 200 : state.size.width,
                   height: state.isMinimized ? 44 : state.size.height)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .position(
                x: state.position.x + dragOffset.width,
                y: state.position.y + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        state.position.x += value.translation.width
                        state.position.y += value.translation.height
                    }
            )
            .animation(.easeInOut(duration: 0.2), value: state.isMinimized)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // ドラッグインジケーター
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 4)

            Spacer()

            Text("しおり検索")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Spacer()

            // 最小化/展開ボタン
            Button(action: {
                state.isMinimized.toggle()
            }) {
                Image(systemName: state.isMinimized ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 8)

            // 閉じるボタン（検索結果は保持）
            Button(action: {
                state.hide()
            }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .cornerRadius(12, corners: [.topLeft, .topRight])
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)

            TextField("検索...", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }

            if !state.searchQuery.isEmpty {
                Button(action: {
                    state.clearResults()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Button(action: performSearch) {
                Text("検索")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .disabled(state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Content

    private var contentView: some View {
        Group {
            if state.isSearching {
                VStack {
                    ProgressView()
                    Text("検索中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.searchResults.isEmpty && state.hasSearched {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("結果なし")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.circle")
                        .font(.title)
                        .foregroundColor(.blue.opacity(0.6))
                    Text("しおりページを検索")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(indexManager.indexedCount)件")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(state.searchResults) { result in
                    CompactResultCard(result: result) {
                        onPageSelected?(result.pdfFileName, result.pageIndex)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        state.searchResults = []
        state.isSearching = true
        state.errorMessage = nil
        state.hasSearched = true

        Task {
            do {
                let results = try await indexManager.searchWithReranking(query: query, topK: 5)
                await MainActor.run {
                    state.searchResults = results
                    state.isSearching = false
                }
            } catch {
                await MainActor.run {
                    state.errorMessage = error.localizedDescription
                    state.isSearching = false
                }
            }
        }
    }
}

// MARK: - Compact Result Card

struct CompactResultCard: View {
    let result: RankedPageResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // ページ番号
                Text("p.\(result.pageIndex + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    // PDF名
                    Text(result.pdfFileName.replacingOccurrences(of: ".pdf", with: ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // 要約
                    Text(result.summary)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // スコア
                Text(String(format: "%.0f%%", result.score * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        FloatingSearchWindow()
    }
}

import SwiftUI
import Combine

struct HistoryView: View {
    @ObservedObject var historyManager = HistoryManager.shared
    @ObservedObject var bookmarkManager = BookmarkManager.shared
    
    // 表示モード（0: AI要約, 1: しおり）
    @State private var selectedTab = 0
    
    // 本棚から開くためのコールバック（しおりタップ時にジャンプするため）
    // ※ 簡易実装として、今回は「タップしたら閉じる」挙動にします
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            // タブ切り替え
            Picker("表示", selection: $selectedTab) {
                Text("AI要約").tag(0)
                Text("しおり").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if selectedTab == 0 {
                // === AI要約リスト ===
                List {
                    ForEach(historyManager.logs) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("📄 \(log.pdfFileName) (p.\(log.pageIndex + 1))")
                                    .font(.caption).foregroundColor(.gray)
                                Spacer()
                                Text(log.date, style: .date).font(.caption2).foregroundColor(.secondary)
                            }
                            Text(log.summary).font(.body).lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: historyManager.deleteLog)
                }
            } else {
                // === しおりリスト ===
                List {
                    if bookmarkManager.bookmarks.isEmpty {
                        Text("しおりはまだありません").foregroundColor(.gray)
                    } else {
                        ForEach(bookmarkManager.bookmarks) { bookmark in
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.red)
                                VStack(alignment: .leading) {
                                    Text(bookmark.pdfFileName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(bookmark.pageIndex + 1)ページ目")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text(bookmark.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: bookmarkManager.deleteBookmark)
                    }
                }
            }
        }
        .navigationTitle("読書ノート")
        .navigationBarItems(trailing: EditButton())
    }
}

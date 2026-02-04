import Foundation
import SwiftUI
import Combine  // ← これが足りていませんでした！追加してください

// 保存するデータの形（読書ログ）
struct ReadingLog: Codable, Identifiable {
    var id = UUID()
    let pdfFileName: String // ファイル名
    let pageIndex: Int      // ページ番号（0始まり）
    let summary: String     // AI要約
    let rawText: String     // 原文
    let date: Date          // 保存日時
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published var logs: [ReadingLog] = []
    
    private let fileName = "reading_logs.json"
    
    init() {
        loadLogs()
    }
    
    // 保存先のパス取得
    private var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(fileName)
    }
    
    // ログを追加して保存
    func addLog(pdfName: String, pageIndex: Int, summary: String, rawText: String) {
        let newLog = ReadingLog(
            pdfFileName: pdfName,
            pageIndex: pageIndex,
            summary: summary,
            rawText: rawText,
            date: Date()
        )
        
        // 新しいものを先頭に
        logs.insert(newLog, at: 0)
        saveLogs()
    }
    
    // ログの削除
    func deleteLog(at offsets: IndexSet) {
        logs.remove(atOffsets: offsets)
        saveLogs()
    }
    
    // ファイルへの書き込み
    private func saveLogs() {
        do {
            let data = try JSONEncoder().encode(logs)
            try data.write(to: fileURL)
        } catch {
            print("保存に失敗しました: \(error)")
        }
    }
    
    // ファイルからの読み込み
    private func loadLogs() {
        do {
            let data = try Data(contentsOf: fileURL)
            logs = try JSONDecoder().decode([ReadingLog].self, from: data)
        } catch {
            // ファイルがない場合は空のままでOK
            logs = []
        }
    }
}

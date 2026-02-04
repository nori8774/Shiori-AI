//
//  PDF_ReaderApp.swift
//  PDF_Reader
//
//  Created by Norimasa Yamamoto on 2025/12/14.
//

import SwiftUI

@main
struct PDF_ReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // アプリ起動時に保留中のインデックスタスクを処理
                    await BookmarkIndexManager.shared.processPendingTasksOnLaunch()
                }
        }
    }
}

import Foundation
import Security

class KeychainHelper {
    // シングルトンインスタンス（どこからでも KeychainHelper.standard で呼べるようにする）
    static let standard = KeychainHelper()
    private init() {}
    
    // データの保存（更新も兼ねる）
    func save(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // まず既存のデータを削除（重複防止）
        SecItemDelete(query as CFDictionary)
        
        // 新規追加
        SecItemAdd(query as CFDictionary, nil)
    }
    
    // データの読み出し
    func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
    
    // データの削除（ログアウト時などに使用）
    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

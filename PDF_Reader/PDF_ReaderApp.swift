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
    static let standard = KeychainHelper()
    private init() {}

    // データの保存（更新も兼ねる）
    func save(service: String, account: String, data: Data) {
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst: Keychainエンタイトルメント(-34018)を回避、ファイルベースで保存
        saveToFile(service: service, account: account, data: data)
        #else
        // iOS: Keychain を使用
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
        #endif
    }

    // データの読み出し
    func read(service: String, account: String) -> Data? {
        #if targetEnvironment(macCatalyst)
        return readFromFile(service: service, account: account)
        #else
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
        if status != errSecItemNotFound {
            print("Keychain read error: \(status)")
        }
        return nil
        #endif
    }

    // データの削除
    func delete(service: String, account: String) {
        #if targetEnvironment(macCatalyst)
        deleteFile(service: service, account: account)
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }

    // MARK: - Mac Catalyst ファイルベース保存（アプリサンドボックス内）

    private func storageURL(service: String, account: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SecureStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(service)_\(account).dat")
    }

    private func saveToFile(service: String, account: String, data: Data) {
        let url = storageURL(service: service, account: account)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("KeychainHelper: Saved to file (Mac fallback)")
        } catch {
            print("KeychainHelper file save error: \(error)")
        }
    }

    private func readFromFile(service: String, account: String) -> Data? {
        let url = storageURL(service: service, account: account)
        return try? Data(contentsOf: url)
    }

    private func deleteFile(service: String, account: String) {
        let url = storageURL(service: service, account: account)
        try? FileManager.default.removeItem(at: url)
    }
}

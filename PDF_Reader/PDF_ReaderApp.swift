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
        if status != errSecItemNotFound {
            print("Keychain read error: \(status)")
        }
        return nil
    }

    // データの削除
    func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

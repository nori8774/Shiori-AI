# PDF Reader アプリ - 現状ドキュメント

## 概要

iPad向けのPDFリーダーアプリ。書籍形式のPDFを快適に読むために設計されており、AI機能（Google Gemini）を活用した要約・翻訳機能を搭載している。

---

## アーキテクチャ

**パターン**: MVVM + Singleton Managers

**フレームワーク**:
- SwiftUI - UI構築
- PDFKit - PDF表示・操作
- Security - Keychain (APIキー保存)
- GoogleGenerativeAI - AI機能 (Swift Package Manager経由)

---

## ファイル構成

```
PDF_Reader/
├── PDF_ReaderApp.swift      # アプリエントリーポイント + KeychainHelper
├── ContentView.swift        # メインUI (ライブラリ/閲覧モード)
├── PDFKitView.swift         # PDF表示コンポーネント
├── BookmarkManager.swift    # ブックマーク管理
├── HistoryManager.swift     # 読書履歴管理
├── HistoryView.swift        # 履歴/ブックマーク表示UI
├── GeminiService.swift      # Gemini AI連携
├── LibraryManager.swift     # ライブラリ/書籍管理
├── DocumentPicker.swift     # ファイル選択UI
├── SettingsView.swift       # 設定画面
└── PDFExtensions.swift      # PDFKit拡張
```

---

## 実装済み機能

### 1. ライブラリ管理
| 機能 | 実装場所 |
|------|----------|
| PDFインポート | DocumentPicker, LibraryManager |
| サムネイル自動生成 | LibraryManager |
| 書籍削除 | ContentView, LibraryManager |
| グリッド表示 | ContentView |

### 2. PDF閲覧
| 機能 | 実装場所 |
|------|----------|
| PDF表示 | PDFKitView |
| スワイプでページ移動 | PDFKitView (Coordinator) |
| 単ページ/見開き表示切替 | ContentView, PDFKitView |
| 右綴じ（縦書き）対応 | PDFKitView |
| 左綴じ（横書き）対応 | PDFKitView |
| テキスト選択 | PDFKitView (PDFKit標準機能) |
| ハイライト（黄色マーカー） | PDFKitView |

### 3. ブックマーク
| 機能 | 実装場所 |
|------|----------|
| ブックマーク追加/削除 | BookmarkManager |
| ブックマーク一覧表示 | HistoryView |
| ブックマーク済みページ表示 | ContentView (リボン表示) |

### 4. AI機能（Google Gemini連携）
| 機能 | 実装場所 |
|------|----------|
| ページ要約（3つの要点） | GeminiService, ContentView |
| 日本語翻訳 | GeminiService, ContentView |
| カスタム質問 | GeminiService, ContentView |
| 解析履歴保存 | HistoryManager |

### 5. 設定
| 機能 | 実装場所 |
|------|----------|
| Gemini APIキー設定 | SettingsView |
| APIキーのKeychain保存 | KeychainHelper |

---

## データモデル

### Book（書籍）
```swift
struct Book: Identifiable, Codable {
    var id: UUID
    let fileName: String
    let importDate: Date
    var isRightToLeft: Bool?  // nil=未設定, true=右綴じ, false=左綴じ
}
```

### Bookmark（ブックマーク）
```swift
struct Bookmark: Identifiable, Codable {
    var id: UUID
    let pdfFileName: String
    let pageIndex: Int
    let createdAt: Date
}
```

### ReadingLog（読書履歴）
```swift
struct ReadingLog: Codable, Identifiable {
    var id: UUID
    let pdfFileName: String
    let pageIndex: Int
    let summary: String      // AI生成の要約
    let rawText: String      // OCRテキスト
    let date: Date
}
```

---

## データ保存

### ファイルストレージ（Documents/）
```
~/Documents/
├── library_books.json        # 書籍メタデータ
├── bookmarks.json            # ブックマーク
├── reading_logs.json         # AI解析履歴
├── {書籍名}.pdf              # インポートしたPDF
└── thumb_{書籍名}.jpg        # サムネイル画像
```

### セキュアストレージ（iOS Keychain）
- サービス: `com.myapp.gemini`
- キー: `gemini_api_key`
- 用途: Gemini APIキーの安全な保存

---

## 外部API

### Google Gemini API
- **モデル**: `gemini-2.5-flash`
- **認証**: Keychainに保存したAPIキー
- **入力**: ページのスナップショット画像（JPEG、圧縮率0.5）
- **出力**: JSON形式（rawText + summary）

**対応操作**:
1. 画像からのOCR（テキスト抽出）
2. 要約（3つの箇条書き）
3. 日本語翻訳
4. カスタム質問への回答

---

## ユーザーフロー

```
1. 初期設定
   └─ 設定画面 → Gemini APIキー入力 → 保存

2. 書籍インポート
   └─ +ボタン → ファイル選択 → PDFコピー → サムネイル生成

3. 書籍を開く
   └─ ライブラリから選択 → 綴じ方向選択ダイアログ → 閲覧開始

4. 閲覧操作
   ├─ スワイプ: ページ移動
   ├─ ブックマークボタン: 栞追加/削除
   ├─ マーカーツール: テキストハイライト
   └─ 表示設定: 単ページ/見開き切替

5. AI解析
   └─ AI解析メニュー → 要約/翻訳/質問 → 結果表示 → 履歴保存

6. 履歴確認
   └─ 履歴アイコン → AI要約タブ / ブックマークタブ
```

---

## 技術スタック

| カテゴリ | 技術 |
|----------|------|
| UI | SwiftUI |
| PDF処理 | PDFKit (Apple) |
| AI/ML | Google Generative AI (Gemini 2.5 Flash) |
| 状態管理 | @ObservableObject, @Published, Combine |
| 非同期処理 | async/await |
| データ保存 | JSON + iOS Keychain |
| ファイルアクセス | FileManager, Security-scoped URLs |

---

## セキュリティ

- **APIキー**: iOS Keychainで安全に保存
- **ファイルアクセス**: Security-scoped resource accessを使用
- **データ保存**: アプリのサンドボックス内に限定
- **入力**: SecureFieldでAPIキーをマスク表示

---

## 作成日
2026年1月13日

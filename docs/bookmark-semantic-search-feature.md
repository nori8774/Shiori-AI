# しおりセマンティック検索機能 仕様書

## 概要

しおりを付けたページの要約をベクトル化し、「あれどこに書いてあったっけ？」という自然言語クエリで全ライブラリ横断のセマンティック検索を実現する機能。フローティングウィンドウUIにより、PDFを読みながら検索結果を参照できる。

---

## 技術選定

- **Google Gemini Embedding API** - text-embedding-004モデル（768次元）
- **VecturaKit** - オンデバイスベクトルDB
- **Apple NaturalLanguage** - 日本語テキスト処理
- **iOS 17.0+** - ターゲットバージョン

---

## 機能一覧

### 1. しおりページのインデックス化

#### 1.1 インデックス対象
- しおりを付けたページのみ（全ページではない）
- ページの要約テキスト（Gemini AIで生成）
- マーカーで引いたテキスト

#### 1.2 インデックス構造（PDF単位統合）
- 同一PDFの全しおりページを1つのVectorDBドキュメントとして統合
- 検索時はPDF単位でマッチ → ページ単位でリランキング
- メリット：PDF単位のスコア計算が高速、関連ページがまとめて返る

#### 1.3 遅延インデックス（API無料枠節約）
- しおり追加から3分後にインデックス処理を実行
- 3分以内にしおりを削除した場合はインデックス処理をキャンセル
- アプリ終了時に保留中のタスクを永続化し、次回起動時に処理

---

### 2. セマンティック検索

#### 2.1 検索フロー
1. クエリをGemini Embedding APIでベクトル化
2. VecturaKitでPDF単位の類似検索
3. マッチしたPDFの全しおりページを収集
4. ページ単位でクエリとの類似度を再計算（リランキング）
5. 上位N件（デフォルト5件）を返す

#### 2.2 リランキング
- クエリとページ要約のコサイン類似度を計算
- マーカーテキストも要約に加えてスコア計算
- スコア順にソートして上位結果を表示

---

### 3. フローティング検索ウィンドウ

#### 3.1 特徴
- **ドラッグ移動可能**: 画面上の任意の位置に配置
- **最小化可能**: タイトルバーのみの表示に折りたたみ
- **結果保持**: ウィンドウを閉じても検索結果を保持
- **明示的クリア**: 検索バーの×ボタンで結果をクリア

#### 3.2 ウィンドウ状態
| 状態 | 説明 |
|------|------|
| 非表示 | ウィンドウ非表示（検索結果は保持） |
| 最小化 | タイトルバーのみ表示 |
| 展開 | 検索バー + 結果リスト表示 |

#### 3.3 操作
- **表示/最小化切替**: ナビバーの検索ボタンタップ
- **PDF内検索**: 検索ボタン長押し（従来の検索機能）
- **ウィンドウを閉じる**: ヘッダーの×ボタン
- **結果クリア**: 検索バーの×ボタン

#### 3.4 検索結果カード
- PDF名（.pdf拡張子なし）
- ページ番号
- 要約テキスト（3行まで）
- マッチスコア（パーセント表示）
- タップで該当ページにジャンプ

---

## データモデル

### PageIndexInfo（ページ情報）
```swift
struct PageIndexInfo: Codable {
    let pageIndex: Int
    let summary: String
    let markerTexts: [String]?
}
```

### PDFIndexEntry（PDF単位インデックス）
```swift
struct PDFIndexEntry: Codable {
    let id: UUID
    let pdfFileName: String
    var pages: [PageIndexInfo]    // しおりページの配列
    var lastUpdated: Date
}
```

### RankedPageResult（リランキング結果）
```swift
struct RankedPageResult: Identifiable {
    let id = UUID()
    let pdfFileName: String
    let pageIndex: Int
    let summary: String
    let markerTexts: [String]?
    let score: Float
}
```

### FloatingSearchState（UI状態）
```swift
class FloatingSearchState: ObservableObject {
    static let shared = FloatingSearchState()

    @Published var isVisible = false
    @Published var isMinimized = false
    @Published var searchQuery = ""
    @Published var searchResults: [RankedPageResult] = []
    @Published var position: CGPoint
    @Published var size: CGSize
}
```

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                      ContentView                             │
│  (フローティング検索ウィンドウをオーバーレイ)               │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  FloatingSearchWindow                        │
│  - ドラッグ可能なウィンドウ                                  │
│  - 検索バー + 結果リスト                                     │
│  - 最小化/展開切替                                           │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                  BookmarkIndexManager                        │
│  - PDF単位統合インデックス管理                               │
│  - Gemini Embedding連携                                      │
│  - VecturaKit操作                                            │
│  - リランキング検索                                          │
└────────────────────────────┬────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
┌─────────────▼─────────────┐ ┌─────────────▼─────────────┐
│      VecturaKit           │ │   GeminiEmbedder          │
│    (ベクトルDB)           │ │   (Embedding API)         │
└───────────────────────────┘ └───────────────────────────┘
```

---

## ファイル構成

### 新規ファイル

| ファイル | 役割 |
|---------|------|
| `BookmarkIndexManager.swift` | インデックス管理、検索エンジン |
| `FloatingSearchWindow.swift` | フローティングウィンドウUI |
| `SemanticSearchView.swift` | フルスクリーン検索UI（非推奨、互換用） |

### 既存ファイル変更

| ファイル | 変更内容 |
|---------|---------|
| `ContentView.swift` | フローティングウィンドウ統合、検索ボタン動作変更 |
| `BookmarkManager.swift` | しおり削除時のインデックス連携 |
| `PDF_ReaderApp.swift` | 起動時の保留タスク処理 |

---

## 主要メソッド

### BookmarkIndexManager

```swift
/// PDF単位でインデックスを構築/更新
func indexFromRawText(pdfFileName: String, pageIndex: Int, rawText: String) async

/// PDF単位で検索（VecturaKit使用）
func search(query: String, numResults: Int) async throws -> [BookmarkSearchResult]

/// ページ単位リランキング検索
func searchWithReranking(query: String, topK: Int) async throws -> [RankedPageResult]

/// インデックス削除
func removeIndex(pdfFileName: String, pageIndex: Int) async

/// 遅延インデックス（3分後に実行）
func scheduleDelayedIndexing(pdfFileName: String, pageIndex: Int, rawText: String)

/// 保留タスクのキャンセル
func cancelScheduledIndexing(pdfFileName: String, pageIndex: Int)

/// 起動時の保留タスク処理
func processPendingTasksOnLaunch() async
```

### FloatingSearchState

```swift
/// ウィンドウ表示
func show()

/// ウィンドウ非表示（結果保持）
func hide()

/// 表示/最小化切替
func toggle()

/// 検索結果クリア
func clearResults()
```

---

## コサイン類似度計算

```swift
private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    var dotProduct: Float = 0
    var normA: Float = 0
    var normB: Float = 0

    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }

    let denominator = sqrt(normA) * sqrt(normB)
    guard denominator > 0 else { return 0 }

    return dotProduct / denominator
}
```

---

## 永続化

### インデックスデータ
- `Documents/pdf_index_metadata.json` - PDF単位のインデックスメタデータ
- VecturaKitのローカルDB - ベクトルデータ

### 保留タスク
- `Documents/pending_index_tasks.json` - 3分待機中のタスク

---

## UI/UXフロー

```
1. しおり追加
   └─ ページにしおりを付ける
   └─ ReadingLogの要約をインデックス用に取得
   └─ 3分間の保留キューに追加
   └─ 3分後、Gemini Embeddingでベクトル化
   └─ VecturaKitに保存

2. セマンティック検索
   └─ ナビバーの検索ボタンをタップ
   └─ フローティングウィンドウ表示
   └─ 検索ワード入力 → 検索実行
   └─ 結果カードをタップ → 該当ページにジャンプ
   └─ PDFで内容確認 → 違っていれば別の結果をタップ
   └─ 新しい検索をしたい場合は×ボタンでクリア

3. ウィンドウ操作
   └─ ドラッグで位置変更
   └─ ヘッダーの折りたたみボタンで最小化
   └─ ヘッダーの×で非表示（結果保持）
   └─ 検索ボタン再タップで再表示
```

---

## 検証方法

1. **インデックス作成**: しおり追加後3分でログに「indexFromRawText」が出力されることを確認
2. **検索実行**: 自然言語クエリで関連ページが返ることを確認
3. **リランキング**: 結果がスコア順（高い順）に並んでいることを確認
4. **ページジャンプ**: 検索結果タップで正しいページに移動することを確認
5. **結果保持**: ウィンドウを閉じて再度開いても結果が残っていることを確認
6. **ドラッグ移動**: ウィンドウをドラッグして位置変更できることを確認
7. **最小化**: 折りたたみボタンでタイトルバーのみになることを確認
8. **複数PDF**: 異なるPDFからの検索結果が混在表示されることを確認

---

## 技術的考慮点

### Gemini Embedding API
- モデル: `text-embedding-004`
- 次元数: 768
- 無料枠: 1分あたり1,500リクエスト
- 遅延インデックスで無料枠を節約

### VecturaKit設定
```swift
let config = VecturaConfig(
    name: "bookmark-search",
    dimension: 768,
    searchOptions: .init(
        defaultNumResults: 20,
        minThreshold: 0.3
    )
)
```

### パフォーマンス最適化
- PDF単位統合でベクトル数を削減
- リランキングは上位候補のみ対象
- 検索結果は上位5件に制限

---

## 将来の拡張候補

1. **オフライン検索**: Apple NLEmbeddingでのフォールバック
2. **検索履歴**: よく使うクエリの保存
3. **本棚フィルタ**: 特定の本棚内のみ検索
4. **マーカー色フィルタ**: 特定の色のマーカーページのみ検索

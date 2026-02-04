# PDF Reader - プロジェクトメモ

## 技術スタック

- **プラットフォーム**: iPadOS
- **言語**: Swift 5.x
- **UI**: SwiftUI
- **PDF処理**: PDFKit (Apple)
- **AI**: Google Generative AI (Gemini 2.5 Flash, text-embedding-004)
- **ベクトルDB**: VecturaKit（オンデバイス）
- **開発環境**: Xcode
- **パッケージ管理**: Swift Package Manager

## プロジェクト概要

iPad向けPDFリーダーアプリ。書籍形式のPDFを快適に読むために設計されており、以下の特徴を持つ：

- 右綴じ（縦書き）・左綴じ（横書き）両対応
- Google Gemini AIによる要約・翻訳・質問機能
- ブックマーク・読書履歴管理
- しおりページのセマンティック検索（Gemini Embedding + VecturaKit）
- スマートマーカー（Apple Pencil対応）

## 基本原則：仕様駆動開発

1. **まずドキュメント**: 永続ドキュメント（`docs/`）で「何を作るか」を定義
2. **作業を計画**: ステアリングファイル（`.steering/`）で「今回何をするか」を計画
3. **実装**: tasklist.mdに従い、進捗を更新しながら実装
4. **検証**: テストし、動作を確認
5. **更新**: 必要に応じてドキュメントを更新

## 重要なルール

### ドキュメント作成時
- 1ファイルずつ作成する
- 次のドキュメントに進む前にユーザー承認を得る

### 新規実装前
1. CLAUDE.mdを読む
2. 関連する永続ドキュメントを読む
3. Grepで既存の類似実装を検索
4. 既存パターンを理解してから実装

### ステアリングファイル管理
- 作業ごとに`.steering/[YYYYMMDD]-[タスク名]/`を作成
- 含めるファイル: requirements.md, design.md, tasklist.md
- `Skill('steering')`を使用して3つのフェーズ（計画、実装、振り返り）を管理

### ドキュメント管理の原則
- **永続ドキュメント**（`docs/`）: プロジェクトの「北極星」、頻繁には更新しない
- **ステアリングドキュメント**（`.steering/`）: タスク固有、作業セッションごとに作成、履歴として保持

## ディレクトリ構造

```
PDF-Reader/
├── CLAUDE.md                     # このファイル（プロジェクトルール）
├── CURRENT_STATUS.md             # 現状ドキュメント
├── docs/                         # 永続仕様ドキュメント
│   ├── ideas/                    # アイデア・要件ブレスト
│   ├── bookmark-semantic-search-feature.md  # しおり検索機能
│   ├── smart-marker-feature.md   # スマートマーカー機能
│   ├── bookshelf-feature.md      # 本棚機能
│   ├── paper-summary-feature.md  # 論文要約機能
│   ├── product-requirements.md   # PRD
│   ├── functional-design.md      # 機能設計
│   ├── architecture.md           # アーキテクチャ設計
│   ├── repository-structure.md   # リポジトリ構造
│   ├── development-guidelines.md # 開発ガイドライン
│   └── glossary.md               # 用語集
├── .steering/                    # 作業セッションドキュメント
│   └── [YYYYMMDD]-[タスク名]/
│       ├── requirements.md       # 作業要件
│       ├── design.md             # 設計
│       └── tasklist.md           # タスクリスト
├── .claude/                      # Claude Code設定
│   ├── settings.json             # 権限設定
│   ├── commands/                 # カスタムコマンド
│   ├── agents/                   # サブエージェント
│   └── skills/                   # スキル定義
├── PDF_Reader/                   # アプリソースコード
│   ├── PDF_ReaderApp.swift       # エントリーポイント
│   ├── ContentView.swift         # メインUI
│   ├── PDFKitView.swift          # PDF表示
│   ├── BookmarkManager.swift     # ブックマーク管理
│   ├── BookmarkIndexManager.swift # しおり検索インデックス管理
│   ├── FloatingSearchWindow.swift # フローティング検索ウィンドウ
│   ├── SemanticSearchView.swift  # セマンティック検索UI（互換用）
│   ├── HistoryManager.swift      # 履歴管理
│   ├── HistoryView.swift         # 履歴UI
│   ├── GeminiService.swift       # AI連携（要約・翻訳・Embedding）
│   ├── LibraryManager.swift      # ライブラリ管理
│   ├── DocumentPicker.swift      # ファイル選択
│   ├── SettingsView.swift        # 設定画面
│   ├── SmartMarkerManager.swift  # スマートマーカー管理
│   └── PDFExtensions.swift       # PDFKit拡張
└── PDF_Reader.xcodeproj/         # Xcodeプロジェクト
```

## 開発ワークフロー

### 1. 機能追加時
```
/add-feature [機能名]
```
1. ステアリングディレクトリ作成
2. 永続ドキュメント確認
3. 既存パターン調査
4. 要件・設計・タスクリスト作成
5. 実装
6. 検証
7. 振り返り記録

### 2. ドキュメントレビュー時
```
/review-docs [パス]
```
doc-reviewerエージェントによる品質レビュー

### 3. プロジェクトセットアップ時
```
/setup-project
```
6つの永続仕様ドキュメントを対話的に作成

## コーディング規約

### Swift スタイル
- Swift API Design Guidelinesに従う
- キャメルケース（型名は大文字始まり、変数・関数は小文字始まり）
- 明確で説明的な命名
- 適切なアクセス修飾子（private, internal, public）

### SwiftUI パターン
- @State: ビュー内ローカル状態
- @ObservedObject: 外部から注入されるオブジェクト
- @StateObject: ビューが所有するオブジェクト
- Singletonパターン: 共有マネージャー（LibraryManager.shared等）

### エラーハンドリング
- do-try-catchで適切にエラー処理
- ユーザー向けエラーメッセージは日本語で

### データ永続化
- JSONファイル: 設定・メタデータ（Documents/内）
- Keychain: 機密情報（APIキー）

## App Store リリース準備

### 必要な作業
1. App Iconの準備（全サイズ）
2. Launch Screenの設定
3. Info.plistの設定
   - Bundle Identifier
   - App Name
   - Privacy descriptions（ファイルアクセス等）
4. Apple Developer Programへの登録
5. App Store Connectでのアプリ登録
6. スクリーンショット・説明文の準備
7. TestFlightでのベータテスト
8. App Store審査提出

## 注意事項

- XcodeでのビルドはXcode上で行う（VSCodeはコード編集用）
- Swift Package Managerの依存関係はXcodeで管理
- シミュレーターでのテストはXcode上で実行

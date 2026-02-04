# スマートマーカー機能 仕様書

## 概要

Apple Pencilを使ってPDF上にマーカーを引く機能。フリーハンドで引いてもテキスト行に自動スナップし、マーカー箇所はAIで自動要約されセマンティック検索に活用される。

---

## 機能一覧

### 1. スマートマーカー（コア機能）

#### 1.1 Apple Pencil連携
- PencilKitを使用してフリーハンド描画を受け付ける
- Vision frameworkでテキスト行を検出
- 描画位置から最も近いテキスト行にスナップ
- スナップ後、該当テキスト領域にハイライトを適用

#### 1.2 マーカーの色（5色）
| 色 | 用途例 | カラーコード |
|----|--------|-------------|
| 黄色 | 重要ポイント | #FFEB3B |
| ピンク | 疑問・要確認 | #F48FB1 |
| 青 | 定義・用語 | #64B5F6 |
| 緑 | 例・事例 | #81C784 |
| オレンジ | 結論・まとめ | #FFB74D |

#### 1.3 マーカーの太さ（3種類）
| 種類 | 高さ | 用途 |
|------|------|------|
| 細 | 2pt | アンダーライン風 |
| 中 | 8pt | 標準ハイライト |
| 太 | 行高さ全体 | 1行全体をマーク |

#### 1.4 マーカー操作
- **追加**: Apple Pencilで線を引く → 自動スナップ → ハイライト適用
- **削除**: マーカー部分を長押し → 削除メニュー表示
- **色変更**: マーカー部分をタップ → カラーピッカー表示

---

### 2. AI連携（マーカー箇所サマリー + 検索優先）

#### 2.1 自動しおり
- マーカーを引くと自動的にそのページにしおりが追加される
- しおりには「マーカーあり」フラグを付与

#### 2.2 マーカー箇所の自動要約
- マーカーを引いた後、バックグラウンドでGeminiに送信
- プロンプト: 「以下のハイライト箇所を中心に、このページの要点を要約してください」
- 要約結果をReadingLogに保存

#### 2.3 セマンティック検索との連携
- マーカー箇所のテキストは検索インデックスで重み付けを高くする
- 検索結果にマーカー色を表示（どの色でマークしたか分かる）

---

### 3. ページめくりアニメーション（オプション）

#### 3.1 概要
- スワイプ時に紙がめくれるような3Dアニメーション
- 設定でON/OFF切り替え可能

#### 3.2 実装方針
- Core Animationを使用
- CATransform3Dで回転効果
- ページの端が丸まる効果

---

## データモデル

### Marker（マーカー）
```swift
struct Marker: Identifiable, Codable {
    let id: UUID
    let bookId: UUID
    let pdfFileName: String
    let pageIndex: Int
    let color: MarkerColor
    let thickness: MarkerThickness
    let bounds: CGRect           // マーカーの矩形領域
    let text: String             // マーカー下のテキスト
    let createdAt: Date
}

enum MarkerColor: String, Codable, CaseIterable {
    case yellow, pink, blue, green, orange

    var uiColor: UIColor { ... }
}

enum MarkerThickness: String, Codable, CaseIterable {
    case thin, medium, thick

    var height: CGFloat { ... }
}
```

### MarkerSummary（マーカー要約）
```swift
struct MarkerSummary: Identifiable, Codable {
    let id: UUID
    let bookId: UUID
    let pageIndex: Int
    let markerTexts: [String]    // そのページのマーカーテキスト一覧
    let summary: String          // AI生成の要約
    let createdAt: Date
}
```

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                      PDFKitView                              │
│  (PencilKit描画レイヤーをオーバーレイ)                        │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    MarkerToolbar                             │
│  色選択 / 太さ選択 / 消しゴムモード                           │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                    SmartMarkerManager                        │
│  - PencilKit描画の受信                                       │
│  - Visionでテキスト行検出                                    │
│  - スナップ処理                                              │
│  - マーカーデータ永続化                                      │
└────────────────────────────┬────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
┌─────────────▼─────────────┐ ┌─────────────▼─────────────┐
│    MarkerStorage          │ │   MarkerSummaryService    │
│    (JSON永続化)           │ │   (Gemini連携)            │
└───────────────────────────┘ └───────────────────────────┘
```

---

## 新規ファイル

| ファイル | 役割 |
|---------|------|
| `SmartMarkerManager.swift` | マーカー管理のコアロジック |
| `MarkerToolbar.swift` | 色・太さ選択UI |
| `MarkerOverlayView.swift` | PencilKit描画レイヤー |
| `TextLineDetector.swift` | Visionでテキスト行検出 |
| `MarkerSummaryService.swift` | マーカー要約のGemini連携 |
| `PageTurnAnimator.swift` | ページめくりアニメーション |

---

## 既存ファイル変更

| ファイル | 変更内容 |
|---------|---------|
| `PDFKitView.swift` | マーカーオーバーレイ統合、描画イベント処理 |
| `ContentView.swift` | MarkerToolbar表示、マーカーモード切替 |
| `BookmarkManager.swift` | マーカー連動のしおり自動追加 |
| `SemanticSearchManager.swift` | マーカーテキストの重み付け検索 |
| `SettingsView.swift` | ページめくりアニメーションのON/OFF設定 |

---

## 実装フェーズ

### Phase 1: スマートマーカー基盤
1. SmartMarkerManager作成（データモデル、永続化）
2. MarkerOverlayView作成（PencilKit描画レイヤー）
3. TextLineDetector作成（Visionでテキスト検出）
4. スナップロジック実装
5. PDFKitViewへの統合

### Phase 2: マーカーUI
1. MarkerToolbar作成（色・太さ選択）
2. ContentViewへのツールバー統合
3. マーカー削除・色変更機能
4. マーカー表示（保存済みマーカーの描画）

### Phase 3: AI連携
1. マーカー追加時の自動しおり
2. MarkerSummaryService作成
3. マーカー箇所のGemini要約
4. SemanticSearchManagerでのマーカー重み付け

### Phase 4: ページめくりアニメーション
1. PageTurnAnimator作成
2. PDFKitViewへの統合
3. SettingsViewでのON/OFF設定

---

## 技術的考慮点

### Visionでのテキスト行検出
```swift
// VNRecognizeTextRequestを使用
let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
    for observation in observations {
        let boundingBox = observation.boundingBox
        // 正規化座標からPDF座標に変換
    }
}
request.recognitionLevel = .fast  // 速度優先
```

### PencilKitとPDFKitの連携
- PDFViewの上にPKCanvasViewをオーバーレイ
- 描画終了時にストロークを解析
- ストロークの中心点から最近接のテキスト行を検出
- PKCanvasViewをクリアし、PDFAnnotationとして永続化

### マーカーの永続化
- アプリ内JSONファイルで管理（元PDFは変更しない）
- PDF表示時にマーカーデータを読み込み、PDFAnnotationとして描画
- 削除時はJSONから削除 + Annotationを除去

---

## UI/UXフロー

```
1. マーカーモード開始
   └─ ツールバーのマーカーボタンタップ
   └─ MarkerToolbar表示（画面下部）

2. マーカーを引く
   └─ Apple Pencilで線を引く
   └─ 描画終了を検知
   └─ Visionでテキスト行検出
   └─ 最近接の行にスナップ
   └─ ハイライトAnnotation追加
   └─ マーカーデータ保存
   └─ しおり自動追加

3. AI要約（バックグラウンド）
   └─ マーカーテキストを収集
   └─ Geminiに送信
   └─ 要約をMarkerSummaryとして保存
   └─ セマンティック検索インデックス更新

4. マーカー削除
   └─ マーカー箇所を長押し
   └─ 削除確認ダイアログ
   └─ Annotation除去 + JSONから削除
```

---

## 検証方法

1. **マーカー追加**: Apple Pencilで線を引き、テキストにスナップすることを確認
2. **色・太さ変更**: ツールバーで選択後、正しく反映されることを確認
3. **マーカー削除**: 長押しで削除できることを確認
4. **永続化**: アプリ再起動後もマーカーが表示されることを確認
5. **自動しおり**: マーカー追加でしおりが付くことを確認
6. **AI要約**: マーカー箇所の要約がReadingLogに保存されることを確認
7. **検索連携**: マーカー箇所が検索結果で優先表示されることを確認
8. **ページめくり**: 設定ONでアニメーションが動作することを確認

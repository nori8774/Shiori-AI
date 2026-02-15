# プライバシーポリシー / Privacy Policy

最終更新日: 2026年2月14日
Last Updated: February 14, 2026

---

## 日本語

### はじめに

Shiori - AI PDF Reader（以下「本アプリ」）は、ユーザーのプライバシーを尊重し、個人情報の保護に努めています。本プライバシーポリシーでは、本アプリがどのような情報を収集し、どのように使用するかを説明します。

### 収集する情報

#### 1. PDFファイル
- ユーザーがインポートしたPDFファイルは、**端末内のみ**に保存されます
- 外部サーバーへのアップロードは行いません

#### 2. AI機能使用時のデータ送信

**重要**: 本アプリのAI機能を使用する際、以下のデータが**Google Gemini API**に送信されます。

| 機能 | 送信されるデータ | 用途 |
|-----|----------------|-----|
| 翻訳 | PDFページの画像 | OCR（文字認識）および翻訳処理 |
| 要約 | PDFページの画像 | OCR（文字認識）および要約生成 |
| 論文要約 | 論文全ページの画像 | OCR（文字認識）および全体要約生成 |
| 音声読み上げ | PDFページの画像 | OCR（文字認識）によるテキスト抽出 |
| しおり検索 | ページのテキストデータ | ベクトル化（意味検索用インデックス作成） |

**送信先**: Google Gemini API (Google LLC)
- Googleのプライバシーポリシー: https://policies.google.com/privacy

**同意の取得**: AI機能を初めて使用する際に、データ送信について明示的な同意を求めます。同意しない場合、AI機能は使用できませんが、PDF閲覧などの基本機能は引き続きご利用いただけます。

**同意の取り消し**: 設定画面からいつでも同意を取り消すことができます。取り消し後はAI機能が使用できなくなります。

#### 3. APIキー
- ユーザーが入力したGoogle Gemini APIキーは、端末内のKeychain（暗号化されたセキュアな領域）に保存されます
- 外部に送信されることはありません

#### 4. 読書データ
- しおり、マーカー、読書履歴などのデータは**端末内のみ**に保存されます
- セマンティック検索用のベクトルデータも端末内に保存されます

### 第三者サービス

本アプリは以下の第三者サービスを利用しています：

#### Google Gemini API
- **提供元**: Google LLC
- **使用目的**: AI機能（翻訳、要約、音声読み上げ用テキスト抽出、セマンティック検索）
- **送信データ**: PDFページの画像、テキストデータ
- **プライバシーポリシー**: https://policies.google.com/privacy
- **データ処理**: 送信されたデータはAI処理のためにのみ使用され、本アプリの開発者がアクセスすることはありません

### データの保持

- すべてのユーザーデータは端末内に保存されます
- アプリを削除すると、すべてのデータが削除されます
- Google Gemini APIに送信されたデータの保持については、Googleのプライバシーポリシーをご確認ください

### お子様のプライバシー

本アプリは、13歳未満のお子様から意図的に個人情報を収集することはありません。

### プライバシーポリシーの変更

本プライバシーポリシーは、必要に応じて更新されることがあります。重要な変更がある場合は、アプリ内またはApp Storeの説明で通知します。

### お問い合わせ

プライバシーに関するご質問がある場合は、以下までご連絡ください：

- GitHub: https://github.com/nori8774/Shiori-AI

---

## English

### Introduction

Shiori - AI PDF Reader ("the App") respects your privacy and is committed to protecting your personal information. This Privacy Policy explains what information we collect and how we use it.

### Information We Collect

#### 1. PDF Files
- PDF files you import are stored **only on your device**
- We do not upload files to external servers

#### 2. Data Transmission for AI Features

**Important**: When you use AI features in the App, the following data is sent to **Google Gemini API**.

| Feature | Data Sent | Purpose |
|---------|-----------|---------|
| Translation | PDF page images | OCR (text recognition) and translation |
| Summarization | PDF page images | OCR (text recognition) and summary generation |
| Paper Summary | All paper page images | OCR (text recognition) and full paper summary |
| Text-to-Speech | PDF page images | Text extraction via OCR |
| Bookmark Search | Page text data | Vectorization (semantic search indexing) |

**Recipient**: Google Gemini API (Google LLC)
- Google's Privacy Policy: https://policies.google.com/privacy

**Consent**: Before using AI features for the first time, we will ask for your explicit consent to data transmission. If you do not consent, AI features will be unavailable, but basic features like PDF viewing will remain accessible.

**Revoking Consent**: You can revoke your consent at any time from the Settings screen. After revocation, AI features will become unavailable.

#### 3. API Key
- Your Google Gemini API key is stored in the device's Keychain (encrypted secure storage)
- It is never transmitted externally

#### 4. Reading Data
- Bookmarks, markers, and reading history are stored **only on your device**
- Vector data for semantic search is also stored locally

### Third-Party Services

The App uses the following third-party services:

#### Google Gemini API
- **Provider**: Google LLC
- **Purpose**: AI features (translation, summarization, text extraction for TTS, semantic search)
- **Data Sent**: PDF page images, text data
- **Privacy Policy**: https://policies.google.com/privacy
- **Data Processing**: Transmitted data is used solely for AI processing and is not accessed by the App developer

### Data Retention

- All user data is stored on your device
- Deleting the App will delete all data
- For retention of data sent to Google Gemini API, please refer to Google's Privacy Policy

### Children's Privacy

The App does not knowingly collect personal information from children under 13.

### Changes to This Policy

This Privacy Policy may be updated as needed. We will notify you of significant changes through the App or App Store description.

### Contact Us

If you have questions about privacy, please contact us at:

- GitHub: https://github.com/nori8774/Shiori-AI

---

© 2026 Shiori - AI PDF Reader

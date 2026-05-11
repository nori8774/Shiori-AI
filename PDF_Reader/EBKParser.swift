import Foundation

// MARK: - Data Models

struct EBKMetadata {
    let title: String
    let author: String
}

struct EBKRubyAnnotation {
    let location: Int   // baseText内の位置
    let length: Int     // baseTextの文字数
    let reading: String // ふりがな
}

struct EBKContent {
    let metadata: EBKMetadata
    let bodyText: String                    // ルビ除去済みの本文
    let rubyAnnotations: [EBKRubyAnnotation] // ルビ情報
    let chapterBreaks: [Int]                // 章区切りの文字位置
}

// MARK: - Parser

class EBKParser {

    enum ParseError: LocalizedError {
        case invalidFormat
        case noBodyText
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "有効な.ebkファイルではありません"
            case .noBodyText: return "本文テキストが見つかりません"
            case .decodingFailed: return "テキストのデコードに失敗しました"
            }
        }
    }

    func parse(data: Data) throws -> EBKContent {
        // 1. ヘッダー検証
        guard data.count > 0x100,
              data[8] == 0x62, data[9] == 0x6F, data[10] == 0x6F, data[11] == 0x6B // "book"
        else {
            throw ParseError.invalidFormat
        }

        // 2. メタデータ抽出
        let metadata = extractMetadata(from: data)

        // 3. 本文TEXTブロック検出
        guard let bodyData = findBodyTextBlock(in: data) else {
            throw ParseError.noBodyText
        }

        // 4. Shift_JIS → String変換
        guard let rawText = decodeShiftJIS(bodyData) else {
            throw ParseError.decodingFailed
        }

        // 5. マークアップ処理
        let content = processMarkup(rawText: rawText, metadata: metadata)
        return content
    }

    // MARK: - Metadata Extraction

    private func extractMetadata(from data: Data) -> EBKMetadata {
        let title = readShiftJISString(from: data, lengthOffset: 0x5C, stringOffset: 0x5D)
        let author = readShiftJISString(from: data, lengthOffset: 0x9C, stringOffset: 0x9D)
        return EBKMetadata(title: title, author: author)
    }

    private func readShiftJISString(from data: Data, lengthOffset: Int, stringOffset: Int) -> String {
        guard lengthOffset < data.count else { return "" }
        let length = Int(data[lengthOffset])
        guard length > 0, stringOffset + length <= data.count else { return "" }
        let bytes = data[stringOffset..<stringOffset + length]
        return String(data: Data(bytes), encoding: .shiftJIS) ?? ""
    }

    // MARK: - Body Text Block Detection

    private func findBodyTextBlock(in data: Data) -> Data? {
        // TEXT marker = 0x54455854
        let textMarker: [UInt8] = [0x54, 0x45, 0x58, 0x54]

        struct TextBlock {
            let offset: Int
            let type: UInt32
            let contentStart: Int
            let contentEnd: Int
            var size: Int { contentEnd - contentStart }
        }

        // すべてのTEXTブロック（type >= 0x80）を収集
        var blocks: [TextBlock] = []
        var searchPos = 0

        while searchPos < data.count - 8 {
            guard let idx = findBytes(textMarker, in: data, from: searchPos) else { break }
            guard idx + 8 <= data.count else { break }

            let typeValue = readUInt32BE(data, at: idx + 4)
            if typeValue >= 0x80 {
                blocks.append(TextBlock(offset: idx, type: typeValue, contentStart: idx + 8, contentEnd: 0))
            }
            searchPos = idx + 4
        }

        // 各ブロックの終端を設定
        for i in 0..<blocks.count {
            if i + 1 < blocks.count {
                blocks[i] = TextBlock(
                    offset: blocks[i].offset,
                    type: blocks[i].type,
                    contentStart: blocks[i].contentStart,
                    contentEnd: blocks[i + 1].offset
                )
            } else {
                blocks[i] = TextBlock(
                    offset: blocks[i].offset,
                    type: blocks[i].type,
                    contentStart: blocks[i].contentStart,
                    contentEnd: data.count
                )
            }
        }

        // 脚注・奥付を除外し、最大のブロックを返す
        let candidates = blocks.filter { block in
            let sampleSize = min(50, block.size)
            guard sampleSize > 0 else { return false }
            let sample = Data(data[block.contentStart..<block.contentStart + sampleSize])
            let text = String(data: sample, encoding: .shiftJIS) ?? ""
            let isFootnote = text.hasPrefix("脚注")
            let isColophon = text.contains("奥付")
            return !isFootnote && !isColophon && block.size > 100
        }

        guard let largest = candidates.max(by: { $0.size < $1.size }) else {
            return nil
        }

        return Data(data[largest.contentStart..<largest.contentEnd])
    }

    // MARK: - Text Decoding

    private func decodeShiftJIS(_ data: Data) -> String? {
        // 末尾のバイナリメタデータ（null バイト等）をトリムしてからデコード
        var trimmedData = data
        while !trimmedData.isEmpty && trimmedData.last == 0x00 {
            trimmedData.removeLast()
        }

        // Shift_JIS (Windows-31J / CP932) で変換
        if let text = String(data: trimmedData, encoding: .shiftJIS) {
            return text
        }

        // 末尾の不正バイトを少しずつ削ってリトライ
        for _ in 0..<20 {
            guard !trimmedData.isEmpty else { return nil }
            trimmedData.removeLast()
            if let text = String(data: trimmedData, encoding: .shiftJIS) {
                return text
            }
        }

        // 最終手段: CFStringで lossy 変換
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)
        )
        if let cfString = CFStringCreateWithBytes(
            nil,
            [UInt8](data),
            data.count,
            CFStringEncoding(cfEncoding),
            true  // isExternalRepresentation = true で不正バイトを置換
        ) {
            return cfString as String
        }

        return nil
    }

    // MARK: - Markup Processing

    private func processMarkup(rawText: String, metadata: EBKMetadata) -> EBKContent {
        var rubyAnnotations: [EBKRubyAnnotation] = []
        var chapterBreaks: [Int] = []

        var cleanText = rawText

        // 1. ルビ抽出と除去
        // パターン: \x11 R <base> \x14 r <reading> \x11 r
        let rubyPattern = try! NSRegularExpression(pattern: "\\x11R(.+?)\\x14r(.+?)\\x11r")
        let nsString = cleanText as NSString
        var rubyMatches: [(range: NSRange, base: String, reading: String)] = []

        rubyPattern.enumerateMatches(in: cleanText, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            guard let match = match else { return }
            let base = nsString.substring(with: match.range(at: 1))
            let reading = nsString.substring(with: match.range(at: 2))
            rubyMatches.append((range: match.range, base: base, reading: reading))
        }

        // ルビマッチを後ろから置換（位置がずれないように）
        for rubyMatch in rubyMatches.reversed() {
            let replaceRange = Range(rubyMatch.range, in: cleanText)!
            cleanText.replaceSubrange(replaceRange, with: rubyMatch.base)
        }

        // ルビのアノテーション位置を再計算
        // 置換後のテキストに対してルビ位置を計算する必要がある
        // → 全置換後に再スキャンする方が確実

        // 2. 見出しタグの処理
        // <H1 ...>text or <H1> / <H2 >text / <H2>
        let headingPattern = try! NSRegularExpression(pattern: "\\x11<H[12][^>]*>")
        cleanText = headingPattern.stringByReplacingMatches(
            in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length),
            withTemplate: "\n\n"
        )

        // 3. フォントタグの除去 <F ...>
        let fontPattern = try! NSRegularExpression(pattern: "\\x11<F[^>]*>")
        cleanText = fontPattern.stringByReplacingMatches(
            in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length),
            withTemplate: ""
        )

        // 4. 画像タグの除去 <I ...>
        let imagePattern = try! NSRegularExpression(pattern: "\\x11<I[^>]*>")
        cleanText = imagePattern.stringByReplacingMatches(
            in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length),
            withTemplate: ""
        )

        // 5. その他のタグ除去（DC1付き）
        let otherTagPattern = try! NSRegularExpression(pattern: "\\x11<[^>]*>")
        cleanText = otherTagPattern.stringByReplacingMatches(
            in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length),
            withTemplate: ""
        )

        // 6. 残っている制御文字の除去
        cleanText = cleanText.replacingOccurrences(of: "\u{11}", with: "")
        cleanText = cleanText.replacingOccurrences(of: "\u{14}", with: "")
        cleanText = cleanText.replacingOccurrences(of: "\u{00}", with: "")
        cleanText = cleanText.replacingOccurrences(of: "\u{01}", with: "")

        // 7. 改行の正規化
        cleanText = cleanText.replacingOccurrences(of: "\r\n", with: "\n")
        cleanText = cleanText.replacingOccurrences(of: "\r", with: "\n")

        // 8. 連続空行の削減（3行以上→2行）
        let multiNewlinePattern = try! NSRegularExpression(pattern: "\\n{4,}")
        cleanText = multiNewlinePattern.stringByReplacingMatches(
            in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length),
            withTemplate: "\n\n\n"
        )

        // 9. 末尾のゴミバイト（デコード失敗の置換文字等）を除去
        while cleanText.hasSuffix("\u{FFFD}") || cleanText.last == "B" || cleanText.last == "<" {
            cleanText.removeLast()
        }

        // 先頭・末尾の空白を除去
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 10. ルビアノテーションを再構築（クリーンテキストに対して）
        // 再度ルビの位置をクリーンテキスト内で特定
        // （パフォーマンス考慮で、元のrubyMatchesのbase文字列を使って位置を探す）
        var searchStartIndex = cleanText.startIndex
        for rubyMatch in rubyMatches {
            if let range = cleanText.range(of: rubyMatch.base, range: searchStartIndex..<cleanText.endIndex) {
                let location = cleanText.distance(from: cleanText.startIndex, to: range.lowerBound)
                rubyAnnotations.append(EBKRubyAnnotation(
                    location: location,
                    length: rubyMatch.base.count,
                    reading: rubyMatch.reading
                ))
                searchStartIndex = range.lowerBound
                // 次の検索を少し先から（同じ文字の繰り返し対策）
                if let nextIdx = cleanText.index(range.lowerBound, offsetBy: 1, limitedBy: cleanText.endIndex) {
                    searchStartIndex = nextIdx
                }
            }
        }

        // 11. 章区切りの検出（連続改行が多い箇所）
        let chapterPattern = try! NSRegularExpression(pattern: "\\n{3}")
        let chapterMatches = chapterPattern.matches(in: cleanText, range: NSRange(location: 0, length: (cleanText as NSString).length))
        for match in chapterMatches {
            chapterBreaks.append(match.range.location)
        }

        return EBKContent(
            metadata: metadata,
            bodyText: cleanText,
            rubyAnnotations: rubyAnnotations,
            chapterBreaks: chapterBreaks
        )
    }

    // MARK: - Binary Helpers

    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) << 24
             | UInt32(data[offset + 1]) << 16
             | UInt32(data[offset + 2]) << 8
             | UInt32(data[offset + 3])
    }

    private func findBytes(_ pattern: [UInt8], in data: Data, from start: Int) -> Int? {
        guard pattern.count > 0 else { return nil }
        let end = data.count - pattern.count
        guard start <= end else { return nil }

        for i in start...end {
            var found = true
            for j in 0..<pattern.count {
                if data[i + j] != pattern[j] {
                    found = false
                    break
                }
            }
            if found { return i }
        }
        return nil
    }
}

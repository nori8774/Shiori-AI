import UIKit
import CoreText

enum EBKFontSize: String, CaseIterable {
    case small = "小"
    case medium = "中"
    case large = "大"

    var bodyFontSize: CGFloat {
        switch self {
        case .small:  return 14
        case .medium: return 18
        case .large:  return 22
        }
    }

    var rubyFontSize: CGFloat {
        switch self {
        case .small:  return 6
        case .medium: return 7.5
        case .large:  return 9
        }
    }
}

class EBKToPDFConverter {

    // ページサイズ（A5相当、ポイント単位）
    private let pageWidth: CGFloat = 420
    private let pageHeight: CGFloat = 595

    // マージン
    private let marginTop: CGFloat = 40
    private let marginBottom: CGFloat = 40
    private let marginLeft: CGFloat = 35
    private let marginRight: CGFloat = 35

    // フォント設定（外部から指定）
    private let bodyFontSize: CGFloat
    private let rubyFontSize: CGFloat
    private let columnGap: CGFloat = 6     // カラム間（ルビスペース含む）
    private let rubyGap: CGFloat = 1.5     // ルビと本文の間隔
    private let charSpacing: CGFloat = 2   // 文字間

    init(fontSize: EBKFontSize = .medium) {
        self.bodyFontSize = fontSize.bodyFontSize
        self.rubyFontSize = fontSize.rubyFontSize
    }

    // 計算プロパティ
    private var textAreaWidth: CGFloat { pageWidth - marginLeft - marginRight }
    private var textAreaHeight: CGFloat { pageHeight - marginTop - marginBottom }
    private var charsPerColumn: Int { Int(textAreaHeight / (bodyFontSize + charSpacing)) }
    private var columnWidth: CGFloat { bodyFontSize + rubyFontSize + rubyGap + columnGap }
    private var columnsPerPage: Int { Int(textAreaWidth / columnWidth) }

    func convert(content: EBKContent) -> Data {
        // ルビ辞書を構築（高速ルックアップ用）
        let rubyDict = buildRubyDictionary(content: content)

        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, [
            kCGPDFContextTitle as String: content.metadata.title as CFString,
            kCGPDFContextAuthor as String: content.metadata.author as CFString
        ])

        let bodyText = Array(content.bodyText)
        let totalChars = bodyText.count
        var charIndex = 0
        var pageCount = 0

        while charIndex < totalChars {
            UIGraphicsBeginPDFPage()
            guard let context = UIGraphicsGetCurrentContext() else { break }

            charIndex = drawPage(
                context: context,
                bodyText: bodyText,
                startIndex: charIndex,
                rubyDict: rubyDict
            )
            pageCount += 1
        }

        UIGraphicsEndPDFContext()
        print("[EBK] PDF生成: \(pageCount) ページ")
        return pdfData as Data
    }

    // MARK: - Page Drawing

    private func drawPage(
        context: CGContext,
        bodyText: [Character],
        startIndex: Int,
        rubyDict: [Int: RubyInfo]
    ) -> Int {
        let bodyFont = CTFontCreateWithName("HiraMinProN-W3" as CFString, bodyFontSize, nil)
        let rubyFont = CTFontCreateWithName("HiraMinProN-W3" as CFString, rubyFontSize, nil)

        var charIndex = startIndex
        let totalChars = bodyText.count

        for col in 0..<columnsPerPage {
            if charIndex >= totalChars { break }

            // カラムのX位置（右から左）
            let colX = pageWidth - marginRight - CGFloat(col + 1) * columnWidth + columnGap / 2

            var row = 0

            while row < charsPerColumn && charIndex < totalChars {
                let ch = bodyText[charIndex]

                // 改行処理
                if ch == "\n" {
                    charIndex += 1
                    // 連続改行 → 次のカラムへ（段落区切り）
                    if charIndex < totalChars && bodyText[charIndex] == "\n" {
                        charIndex += 1
                        break // 次のカラムへ
                    }
                    // 単独改行 → 次のカラムへ
                    break
                }

                // 文字のY位置（上から下）
                let charY = marginTop + CGFloat(row) * (bodyFontSize + charSpacing)

                // 本文の文字を描画
                drawCharacter(
                    context: context,
                    character: ch,
                    font: bodyFont,
                    x: colX,
                    y: charY,
                    fontSize: bodyFontSize
                )

                // ルビ描画（この位置にルビがある場合）
                if let reading = findRuby(at: charIndex, bodyText: bodyText, rubyDict: rubyDict) {
                    drawRuby(
                        context: context,
                        reading: reading.text,
                        baseLength: reading.length,
                        font: rubyFont,
                        x: colX + bodyFontSize + rubyGap,
                        y: charY,
                        row: row
                    )
                }

                charIndex += 1
                row += 1
            }
        }

        return charIndex
    }

    // MARK: - Character Drawing (UIKit座標系で直接描画)

    private func drawCharacter(
        context: CGContext,
        character: Character,
        font: CTFont,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat
    ) {
        let str = String(character)
        let uiFont = UIFont(name: "HiraMinProN-W3", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)

        // 縦書き用の文字回転が必要な文字かチェック
        let needsRotation = needsVerticalRotation(character)

        // 縦書き用の句読点位置調整
        var drawX = x
        var drawY = y
        if isPunctuation(character) {
            drawX = x + fontSize * 0.5
            drawY = y - fontSize * 0.3
        }

        if needsRotation {
            // 長音符、括弧等は90度回転して描画
            context.saveGState()
            let centerX = drawX + fontSize / 2
            let centerY = drawY + fontSize / 2
            context.translateBy(x: centerX, y: centerY)
            context.rotate(by: .pi / 2)
            context.translateBy(x: -centerX, y: -centerY)

            let attrStr = NSAttributedString(string: str, attributes: [
                .font: uiFont,
                .foregroundColor: UIColor.black
            ])
            attrStr.draw(at: CGPoint(x: drawX, y: drawY))

            context.restoreGState()
        } else {
            let attrStr = NSAttributedString(string: str, attributes: [
                .font: uiFont,
                .foregroundColor: UIColor.black
            ])
            let strSize = attrStr.size()
            // 文字を列の中央に配置
            let centeredX = drawX + (fontSize - strSize.width) / 2
            attrStr.draw(at: CGPoint(x: centeredX, y: drawY))
        }
    }

    // MARK: - Ruby Drawing (UIKit座標系で直接描画)

    private func drawRuby(
        context: CGContext,
        reading: String,
        baseLength: Int,
        font: CTFont,
        x: CGFloat,
        y: CGFloat,
        row: Int
    ) {
        let rubyChars = Array(reading)
        let uiFont = UIFont(name: "HiraMinProN-W3", size: rubyFontSize) ?? UIFont.systemFont(ofSize: rubyFontSize)
        let baseHeight = CGFloat(baseLength) * (bodyFontSize + charSpacing)
        let totalRubyHeight = CGFloat(rubyChars.count) * rubyFontSize

        // ルビをベーステキストの中央に配置
        let rubyStartY: CGFloat
        if totalRubyHeight < baseHeight {
            rubyStartY = y + (baseHeight - totalRubyHeight) / 2
        } else {
            rubyStartY = y
        }

        let rubySpacing = totalRubyHeight <= baseHeight
            ? (baseHeight / CGFloat(rubyChars.count))
            : rubyFontSize

        for (i, rubyChar) in rubyChars.enumerated() {
            let rubyY = rubyStartY + CGFloat(i) * rubySpacing
            let str = String(rubyChar)

            let attrStr = NSAttributedString(string: str, attributes: [
                .font: uiFont,
                .foregroundColor: UIColor.gray
            ])
            attrStr.draw(at: CGPoint(x: x, y: rubyY))
        }
    }

    // MARK: - Ruby Dictionary

    private struct RubyInfo {
        let text: String
        let length: Int
    }

    private func buildRubyDictionary(content: EBKContent) -> [Int: RubyInfo] {
        var dict: [Int: RubyInfo] = [:]
        for ruby in content.rubyAnnotations {
            dict[ruby.location] = RubyInfo(text: ruby.reading, length: ruby.length)
        }
        return dict
    }

    private func findRuby(at index: Int, bodyText: [Character], rubyDict: [Int: RubyInfo]) -> RubyInfo? {
        return rubyDict[index]
    }

    // MARK: - Vertical Text Helpers

    /// 縦書き時に90度回転が必要な文字
    private func needsVerticalRotation(_ ch: Character) -> Bool {
        switch ch {
        case "ー", "〜", "～", "—", "–", "―", "…", "‥",
             "（", "）", "(", ")", "「", "」", "『", "』",
             "【", "】", "〔", "〕", "｛", "｝", "{", "}",
             "＜", "＞", "<", ">",
             "＝", "｜":
            return true
        default:
            return false
        }
    }

    /// 句読点（縦書き時に右上寄せ）
    private func isPunctuation(_ ch: Character) -> Bool {
        switch ch {
        case "、", "。", "，", "．", "・":
            return true
        default:
            return false
        }
    }
}

import UIKit
import PDFKit

// MARK: - Paper Summary Model

struct PaperSummary: Codable, Identifiable {
    let id: UUID
    let originalBookId: UUID       // 元の論文のBook ID
    var summaryBookId: UUID?       // 要約付きPDFのBook ID（生成後に設定）
    let title: String              // 論文タイトル
    let authors: [String]          // 著者
    let abstractSummary: String    // 概要
    let keyFindings: [String]      // 主要な発見
    let methodology: String        // 研究手法
    let figureNotes: [String]      // 図表メモ
    let keywords: [String]         // キーワード
    let createdAt: Date
}

// MARK: - PDF Generator

class PDFGenerator {
    static let shared = PDFGenerator()

    private init() {}

    // MARK: - Generate Summary Page

    /// 論文要約ページをPDFとして生成
    func generateSummaryPage(summary: PaperSummary, originalFileName: String) -> PDFDocument? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4サイズ
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()
            drawSummaryContent(summary: summary, originalFileName: originalFileName, in: pageRect, context: context.cgContext)
        }

        return PDFDocument(data: data)
    }

    /// 要約内容を描画
    private func drawSummaryContent(summary: PaperSummary, originalFileName: String, in rect: CGRect, context: CGContext) {
        let margin: CGFloat = 40
        var yPosition: CGFloat = margin

        // ヘッダー背景
        context.setFillColor(UIColor.systemPurple.withAlphaComponent(0.1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: rect.width, height: 80))

        // タイトル: AI要約
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.systemPurple
        ]
        let headerText = "AI要約"
        headerText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
        yPosition += 40

        // 生成日
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd HH:mm"
        let dateText = "生成日: \(dateFormatter.string(from: summary.createdAt))"
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray
        ]
        dateText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
        yPosition += 30

        // 区切り線
        context.setStrokeColor(UIColor.systemPurple.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: margin, y: yPosition))
        context.addLine(to: CGPoint(x: rect.width - margin, y: yPosition))
        context.strokePath()
        yPosition += 20

        // 論文タイトル
        yPosition = drawSection(
            title: "論文タイトル",
            content: summary.title,
            at: yPosition,
            in: rect,
            margin: margin
        )

        // 著者
        if !summary.authors.isEmpty {
            yPosition = drawSection(
                title: "著者",
                content: summary.authors.joined(separator: ", "),
                at: yPosition,
                in: rect,
                margin: margin
            )
        }

        // 概要
        yPosition = drawSection(
            title: "概要 (Abstract)",
            content: summary.abstractSummary,
            at: yPosition,
            in: rect,
            margin: margin
        )

        // 主要な発見・結論
        if !summary.keyFindings.isEmpty {
            let findingsText = summary.keyFindings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            yPosition = drawSection(
                title: "主要な発見・結論",
                content: findingsText,
                at: yPosition,
                in: rect,
                margin: margin
            )
        }

        // 研究手法
        if !summary.methodology.isEmpty {
            yPosition = drawSection(
                title: "研究手法",
                content: summary.methodology,
                at: yPosition,
                in: rect,
                margin: margin
            )
        }

        // 図表のポイント
        if !summary.figureNotes.isEmpty {
            let figureText = summary.figureNotes.map { "・\($0)" }.joined(separator: "\n")
            yPosition = drawSection(
                title: "図表のポイント",
                content: figureText,
                at: yPosition,
                in: rect,
                margin: margin
            )
        }

        // キーワード
        if !summary.keywords.isEmpty {
            yPosition = drawSection(
                title: "キーワード",
                content: summary.keywords.joined(separator: " / "),
                at: yPosition,
                in: rect,
                margin: margin
            )
        }

        // フッター
        drawFooter(in: rect, margin: margin, context: context)
    }

    /// セクションを描画
    private func drawSection(title: String, content: String, at yPosition: CGFloat, in rect: CGRect, margin: CGFloat) -> CGFloat {
        var y = yPosition

        // セクションタイトル
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.systemPurple
        ]
        let titleText = "■ \(title)"
        titleText.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttributes)
        y += 18

        // セクション内容
        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]
        let contentWidth = rect.width - margin * 2
        let contentRect = CGRect(x: margin + 10, y: y, width: contentWidth - 10, height: 200)

        let attributedContent = NSAttributedString(string: content, attributes: contentAttributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedContent)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedContent.length),
            nil,
            CGSize(width: contentWidth - 10, height: CGFloat.greatestFiniteMagnitude),
            nil
        )

        let path = CGPath(rect: CGRect(x: contentRect.minX, y: rect.height - y - suggestedSize.height, width: contentWidth - 10, height: suggestedSize.height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedContent.length), path, nil)

        let context = UIGraphicsGetCurrentContext()!
        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()

        y += suggestedSize.height + 15

        return y
    }

    /// フッターを描画
    private func drawFooter(in rect: CGRect, margin: CGFloat, context: CGContext) {
        let footerY = rect.height - 30

        // 区切り線
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: footerY - 10))
        context.addLine(to: CGPoint(x: rect.width - margin, y: footerY - 10))
        context.strokePath()

        // フッターテキスト
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        let footerText = "Generated by PDF Reader + Gemini AI"
        let footerSize = footerText.size(withAttributes: footerAttributes)
        footerText.draw(
            at: CGPoint(x: (rect.width - footerSize.width) / 2, y: footerY),
            withAttributes: footerAttributes
        )
    }

    // MARK: - Merge PDFs

    /// 元のPDFの表紙の後ろに要約ページを挿入
    func insertSummaryPage(into originalURL: URL, summaryPage: PDFPage) -> PDFDocument? {
        guard let original = PDFDocument(url: originalURL) else { return nil }

        let newDocument = PDFDocument()

        // 1ページ目（表紙）をコピー
        if let coverPage = original.page(at: 0) {
            newDocument.insert(coverPage, at: 0)
        }

        // 要約ページを挿入
        newDocument.insert(summaryPage, at: 1)

        // 残りのページをコピー
        for i in 1..<original.pageCount {
            if let page = original.page(at: i) {
                newDocument.insert(page, at: newDocument.pageCount)
            }
        }

        return newDocument
    }

    /// 新しいファイル名を生成（元の名前_要約.pdf）
    func generateSummaryFileName(from originalFileName: String) -> String {
        let nameWithoutExtension = (originalFileName as NSString).deletingPathExtension
        return "\(nameWithoutExtension)_要約.pdf"
    }
}

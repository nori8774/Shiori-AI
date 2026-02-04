import Foundation
import SwiftUI
import PDFKit
import Combine

// MARK: - Data Models

enum MarkerColor: String, Codable, CaseIterable {
    case yellow
    case pink
    case blue
    case green
    case purple

    var uiColor: UIColor {
        switch self {
        case .yellow: return UIColor(red: 1.0, green: 0.92, blue: 0.23, alpha: 0.5)
        case .pink: return UIColor(red: 0.96, green: 0.56, blue: 0.69, alpha: 0.5)
        case .blue: return UIColor(red: 0.39, green: 0.71, blue: 0.96, alpha: 0.5)
        case .green: return UIColor(red: 0.51, green: 0.78, blue: 0.52, alpha: 0.5)
        case .purple: return UIColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 0.5)
        }
    }

    var swiftUIColor: Color {
        Color(uiColor)
    }

    var displayName: String {
        switch self {
        case .yellow: return "黄色"
        case .pink: return "ピンク"
        case .blue: return "青"
        case .green: return "緑"
        case .purple: return "紫"
        }
    }

    var iconName: String {
        "circle.fill"
    }
}

enum MarkerThickness: String, Codable, CaseIterable {
    case thin
    case medium
    case thick

    var height: CGFloat {
        switch self {
        case .thin: return 2.0
        case .medium: return 8.0
        case .thick: return 20.0
        }
    }

    var displayName: String {
        switch self {
        case .thin: return "細"
        case .medium: return "中"
        case .thick: return "太"
        }
    }
}

struct Marker: Identifiable, Codable {
    let id: UUID
    let bookId: UUID
    let pdfFileName: String
    let pageIndex: Int
    let color: MarkerColor
    let thickness: MarkerThickness
    let bounds: CodableRect
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        pdfFileName: String,
        pageIndex: Int,
        color: MarkerColor,
        thickness: MarkerThickness,
        bounds: CGRect,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.pdfFileName = pdfFileName
        self.pageIndex = pageIndex
        self.color = color
        self.thickness = thickness
        self.bounds = CodableRect(rect: bounds)
        self.text = text
        self.createdAt = createdAt
    }

    var cgRectBounds: CGRect {
        bounds.cgRect
    }
}

// CGRectをCodableにするためのラッパー
struct CodableRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct MarkerSummary: Identifiable, Codable {
    let id: UUID
    let bookId: UUID
    let pageIndex: Int
    let markerTexts: [String]
    let summary: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        pageIndex: Int,
        markerTexts: [String],
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.pageIndex = pageIndex
        self.markerTexts = markerTexts
        self.summary = summary
        self.createdAt = createdAt
    }
}

// MARK: - Smart Marker Manager

// マーカー認識モード
enum MarkerRecognitionMode: String, Codable, CaseIterable {
    case textLine   // テキスト行認識（従来モード）
    case freeform   // 図形認識（描いた線を直線化）

    var displayName: String {
        switch self {
        case .textLine: return "テキスト認識"
        case .freeform: return "フリーハンド"
        }
    }

    var description: String {
        switch self {
        case .textLine: return "テキスト行に沿ってハイライト"
        case .freeform: return "描いた線を直線化してハイライト"
        }
    }

    var iconName: String {
        switch self {
        case .textLine: return "text.alignleft"
        case .freeform: return "pencil.line"
        }
    }
}

@MainActor
class SmartMarkerManager: ObservableObject {
    static let shared = SmartMarkerManager()

    @Published var markers: [Marker] = []
    @Published var summaries: [MarkerSummary] = []
    @Published var selectedColor: MarkerColor = .yellow
    @Published var selectedThickness: MarkerThickness = .medium
    @Published var isMarkerMode: Bool = false
    @Published var recognitionMode: MarkerRecognitionMode = .freeform  // デフォルトをフリーハンドに

    private let markersFileName = "markers.json"
    private let summariesFileName = "marker_summaries.json"

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        loadMarkers()
        loadSummaries()
    }

    // MARK: - Marker Operations

    func addMarker(
        bookId: UUID,
        pdfFileName: String,
        pageIndex: Int,
        bounds: CGRect,
        text: String
    ) -> Marker {
        let marker = Marker(
            bookId: bookId,
            pdfFileName: pdfFileName,
            pageIndex: pageIndex,
            color: selectedColor,
            thickness: selectedThickness,
            bounds: bounds,
            text: text
        )

        markers.append(marker)
        saveMarkers()

        // 自動しおり追加
        addAutoBookmark(pdfFileName: pdfFileName, pageIndex: pageIndex)

        // バックグラウンドでAI要約を実行
        Task {
            await generateSummaryIfNeeded(bookId: bookId, pageIndex: pageIndex)
        }

        return marker
    }

    func removeMarker(_ marker: Marker) {
        markers.removeAll { $0.id == marker.id }
        saveMarkers()
    }

    func removeMarker(at id: UUID) {
        markers.removeAll { $0.id == id }
        saveMarkers()
    }

    func updateMarkerColor(_ marker: Marker, newColor: MarkerColor) {
        if let index = markers.firstIndex(where: { $0.id == marker.id }) {
            let updatedMarker = Marker(
                id: marker.id,
                bookId: marker.bookId,
                pdfFileName: marker.pdfFileName,
                pageIndex: marker.pageIndex,
                color: newColor,
                thickness: marker.thickness,
                bounds: marker.cgRectBounds,
                text: marker.text,
                createdAt: marker.createdAt
            )
            markers[index] = updatedMarker
            saveMarkers()
        }
    }

    func updateMarkerThickness(_ marker: Marker, newThickness: MarkerThickness) {
        if let index = markers.firstIndex(where: { $0.id == marker.id }) {
            let updatedMarker = Marker(
                id: marker.id,
                bookId: marker.bookId,
                pdfFileName: marker.pdfFileName,
                pageIndex: marker.pageIndex,
                color: marker.color,
                thickness: newThickness,
                bounds: marker.cgRectBounds,
                text: marker.text,
                createdAt: marker.createdAt
            )
            markers[index] = updatedMarker
            saveMarkers()
        }
    }

    // MARK: - Query

    func getMarkers(for bookId: UUID) -> [Marker] {
        markers.filter { $0.bookId == bookId }
    }

    func getMarkers(for bookId: UUID, pageIndex: Int) -> [Marker] {
        markers.filter { $0.bookId == bookId && $0.pageIndex == pageIndex }
    }

    func getMarkers(for pdfFileName: String) -> [Marker] {
        markers.filter { $0.pdfFileName == pdfFileName }
    }

    func getMarkers(for pdfFileName: String, pageIndex: Int) -> [Marker] {
        markers.filter { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex }
    }

    func hasMarkers(for pdfFileName: String, pageIndex: Int) -> Bool {
        markers.contains { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex }
    }

    /// ページのマーカー色を取得（しおり表示用）
    /// - 単一色の場合：その色を返す
    /// - 複数色の場合：nilを返す（白色で表示）
    func getMarkerColor(for pdfFileName: String, pageIndex: Int) -> MarkerColor? {
        let pageMarkers = getMarkers(for: pdfFileName, pageIndex: pageIndex)
        guard !pageMarkers.isEmpty else { return nil }

        let colors = Set(pageMarkers.map { $0.color })
        if colors.count == 1 {
            return colors.first
        }
        return nil  // 複数色の場合はnil
    }

    func getMarkerTexts(for bookId: UUID, pageIndex: Int) -> [String] {
        getMarkers(for: bookId, pageIndex: pageIndex).map { $0.text }
    }

    // MARK: - Auto Bookmark

    private func addAutoBookmark(pdfFileName: String, pageIndex: Int) {
        let bookmarkManager = BookmarkManager.shared
        if !bookmarkManager.isBookmarked(pdfFileName: pdfFileName, pageIndex: pageIndex) {
            bookmarkManager.addBookmark(pdfFileName: pdfFileName, pageIndex: pageIndex)
        }
    }

    // MARK: - AI Summary

    func generateSummaryIfNeeded(bookId: UUID, pageIndex: Int) async {
        let pageMarkers = getMarkers(for: bookId, pageIndex: pageIndex)
        guard !pageMarkers.isEmpty else { return }

        // 既存の要約があり、マーカーテキストが変わっていなければスキップ
        let markerTexts = pageMarkers.map { $0.text }
        if let existingSummary = summaries.first(where: {
            $0.bookId == bookId && $0.pageIndex == pageIndex
        }) {
            if Set(existingSummary.markerTexts) == Set(markerTexts) {
                return
            }
            // マーカーが変わった場合は古い要約を削除
            summaries.removeAll { $0.id == existingSummary.id }
        }

        // Geminiで要約生成
        do {
            let summary = try await generateMarkerSummary(
                bookId: bookId,
                pageIndex: pageIndex,
                markerTexts: markerTexts
            )
            summaries.append(summary)
            saveSummaries()
        } catch {
            print("Failed to generate marker summary: \(error)")
        }
    }

    private func generateMarkerSummary(
        bookId: UUID,
        pageIndex: Int,
        markerTexts: [String]
    ) async throws -> MarkerSummary {
        let combinedText = markerTexts.joined(separator: "\n\n")
        let instruction = """
        以下はユーザーがマーカーを引いた重要な箇所です。
        これらの箇所を中心に、内容の要点を簡潔にまとめてください。

        マーカー箇所:
        \(combinedText)
        """

        // GeminiServiceを使って要約生成
        // 注意: 実際にはページ画像も送る方が良いかもしれないが、
        // テキストのみで簡易要約を生成
        let summaryText = try await generateTextSummary(instruction: instruction, text: combinedText)

        return MarkerSummary(
            bookId: bookId,
            pageIndex: pageIndex,
            markerTexts: markerTexts,
            summary: summaryText
        )
    }

    private func generateTextSummary(instruction: String, text: String) async throws -> String {
        // 簡易実装: テキストの先頭100文字 + "..." を返す
        // 実際にはGeminiServiceを拡張してテキストのみの要約APIを呼ぶ
        // TODO: GeminiService.shared.summarizeText() を実装
        let preview = String(text.prefix(100))
        return "【マーカー箇所の要約】\n\(preview)..."
    }

    // MARK: - Persistence

    private func saveMarkers() {
        let url = documentsDirectory.appendingPathComponent(markersFileName)
        do {
            let data = try JSONEncoder().encode(markers)
            try data.write(to: url)
        } catch {
            print("Failed to save markers: \(error)")
        }
    }

    private func loadMarkers() {
        let url = documentsDirectory.appendingPathComponent(markersFileName)
        do {
            let data = try Data(contentsOf: url)
            markers = try JSONDecoder().decode([Marker].self, from: data)
        } catch {
            markers = []
        }
    }

    private func saveSummaries() {
        let url = documentsDirectory.appendingPathComponent(summariesFileName)
        do {
            let data = try JSONEncoder().encode(summaries)
            try data.write(to: url)
        } catch {
            print("Failed to save summaries: \(error)")
        }
    }

    private func loadSummaries() {
        let url = documentsDirectory.appendingPathComponent(summariesFileName)
        do {
            let data = try Data(contentsOf: url)
            summaries = try JSONDecoder().decode([MarkerSummary].self, from: data)
        } catch {
            summaries = []
        }
    }

    // MARK: - PDF Annotation Integration

    func createAnnotation(for marker: Marker) -> PDFAnnotation {
        let bounds = marker.cgRectBounds
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.color = marker.color.uiColor
        return annotation
    }

    func applyMarkers(to page: PDFPage, pageIndex: Int, pdfFileName: String) {
        let pageMarkers = getMarkers(for: pdfFileName, pageIndex: pageIndex)
        for marker in pageMarkers {
            let annotation = createAnnotation(for: marker)
            page.addAnnotation(annotation)
        }
    }

    func removeAnnotations(from page: PDFPage, for marker: Marker) {
        let annotations = page.annotations
        for annotation in annotations {
            if annotation.bounds == marker.cgRectBounds {
                page.removeAnnotation(annotation)
            }
        }
    }

    // MARK: - Cleanup

    func removeAllMarkers(for bookId: UUID) {
        markers.removeAll { $0.bookId == bookId }
        summaries.removeAll { $0.bookId == bookId }
        saveMarkers()
        saveSummaries()
    }

    /// 指定したページのすべてのマーカーを削除
    func removeAllMarkers(for pdfFileName: String, pageIndex: Int) {
        markers.removeAll { $0.pdfFileName == pdfFileName && $0.pageIndex == pageIndex }
        saveMarkers()
    }

    /// 指定したPDFのすべてのマーカーを削除
    func removeAllMarkers(for pdfFileName: String) {
        markers.removeAll { $0.pdfFileName == pdfFileName }
        saveMarkers()
    }

    /// PDFページからマーカーのアノテーションを全て削除
    func clearAnnotations(from page: PDFPage) {
        let annotations = page.annotations.filter { $0.type == "Highlight" }
        for annotation in annotations {
            page.removeAnnotation(annotation)
        }
    }

    /// PDFドキュメントからすべてのマーカーアノテーションを削除
    func clearAllAnnotations(from document: PDFDocument) {
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                clearAnnotations(from: page)
            }
        }
    }
}

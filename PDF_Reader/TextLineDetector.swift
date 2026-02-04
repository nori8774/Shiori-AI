import Foundation
import Vision
import UIKit
import PDFKit

// MARK: - Detected Text Line

struct DetectedTextLine {
    let text: String
    let boundingBox: CGRect  // 正規化座標 (0-1)
    let confidence: Float
}

// MARK: - Text Line Detector

class TextLineDetector {

    // MARK: - Public Methods

    /// PDFページからテキスト行を検出
    /// - Parameters:
    ///   - page: PDFページ
    ///   - completion: 検出結果のコールバック
    func detectTextLines(from page: PDFPage, completion: @escaping ([DetectedTextLine]) -> Void) {
        // ページを画像に変換
        guard let image = renderPageToImage(page) else {
            completion([])
            return
        }

        detectTextLines(from: image, completion: completion)
    }

    /// UIImageからテキスト行を検出
    /// - Parameters:
    ///   - image: 入力画像
    ///   - completion: 検出結果のコールバック
    func detectTextLines(from image: UIImage, completion: @escaping ([DetectedTextLine]) -> Void) {
        guard let cgImage = image.cgImage else {
            completion([])
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            let lines = observations.compactMap { observation -> DetectedTextLine? in
                guard let topCandidate = observation.topCandidates(1).first else {
                    return nil
                }
                return DetectedTextLine(
                    text: topCandidate.string,
                    boundingBox: observation.boundingBox,
                    confidence: topCandidate.confidence
                )
            }

            DispatchQueue.main.async {
                completion(lines)
            }
        }

        // 高速モードで検出（精度よりも速度優先）
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Text detection failed: \(error)")
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    /// Async/await版のテキスト行検出
    func detectTextLines(from page: PDFPage) async -> [DetectedTextLine] {
        await withCheckedContinuation { continuation in
            detectTextLines(from: page) { lines in
                continuation.resume(returning: lines)
            }
        }
    }

    // MARK: - Snap to Text Line

    /// 描画位置から最も近いテキスト行を見つける
    /// - Parameters:
    ///   - point: 描画の中心点（正規化座標 0-1）
    ///   - textLines: 検出されたテキスト行の配列
    ///   - threshold: スナップする最大距離（正規化座標）
    /// - Returns: 最も近いテキスト行、またはnil
    func findNearestTextLine(
        to point: CGPoint,
        in textLines: [DetectedTextLine],
        threshold: CGFloat = 0.1
    ) -> DetectedTextLine? {
        var nearestLine: DetectedTextLine?
        var minDistance: CGFloat = .infinity

        for line in textLines {
            let lineCenter = CGPoint(
                x: line.boundingBox.midX,
                y: line.boundingBox.midY
            )
            let distance = hypot(point.x - lineCenter.x, point.y - lineCenter.y)

            if distance < minDistance && distance < threshold {
                minDistance = distance
                nearestLine = line
            }
        }

        return nearestLine
    }

    /// 描画ストロークから最も近いテキスト行を見つける
    /// - Parameters:
    ///   - stroke: ストロークの点の配列（正規化座標 0-1）
    ///   - textLines: 検出されたテキスト行の配列
    /// - Returns: ストロークと交差または最近接するテキスト行の配列
    func findTextLinesIntersecting(
        stroke: [CGPoint],
        in textLines: [DetectedTextLine]
    ) -> [DetectedTextLine] {
        guard !stroke.isEmpty else { return [] }

        var intersectingLines: [DetectedTextLine] = []

        for line in textLines {
            let expandedBounds = line.boundingBox.insetBy(dx: -0.02, dy: -0.02)

            // ストロークの点がテキスト行の領域内にあるかチェック
            let intersects = stroke.contains { point in
                expandedBounds.contains(point)
            }

            if intersects {
                intersectingLines.append(line)
            }
        }

        // 交差するものがなければ、最も近い行を探す
        if intersectingLines.isEmpty {
            let strokeCenter = CGPoint(
                x: stroke.map { $0.x }.reduce(0, +) / CGFloat(stroke.count),
                y: stroke.map { $0.y }.reduce(0, +) / CGFloat(stroke.count)
            )
            if let nearest = findNearestTextLine(to: strokeCenter, in: textLines) {
                intersectingLines.append(nearest)
            }
        }

        return intersectingLines
    }

    // MARK: - Coordinate Conversion

    /// Vision座標（左下原点、Y軸上向き）からPDF座標に変換
    /// - Parameters:
    ///   - visionRect: Vision座標系の矩形（正規化 0-1）
    ///   - pageSize: PDFページのサイズ
    /// - Returns: PDF座標系の矩形
    func convertToPDFCoordinates(
        visionRect: CGRect,
        pageSize: CGSize
    ) -> CGRect {
        // Vision: 左下原点、Y軸上向き、正規化 (0-1)
        // PDF: 左下原点、Y軸上向き
        return CGRect(
            x: visionRect.origin.x * pageSize.width,
            y: visionRect.origin.y * pageSize.height,
            width: visionRect.width * pageSize.width,
            height: visionRect.height * pageSize.height
        )
    }

    /// 画面座標からVision正規化座標に変換
    /// - Parameters:
    ///   - screenPoint: 画面座標の点
    ///   - viewSize: ビューのサイズ
    /// - Returns: Vision正規化座標
    func convertToNormalizedCoordinates(
        screenPoint: CGPoint,
        viewSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: screenPoint.x / viewSize.width,
            y: 1.0 - (screenPoint.y / viewSize.height)  // Y軸反転
        )
    }

    // MARK: - Private Methods

    private func renderPageToImage(_ page: PDFPage) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0  // Retina対応

        let size = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }

        return image
    }
}

// MARK: - Stroke Straightening (フリーハンドマーカー用)

struct StraightenedStroke {
    let startPoint: CGPoint  // 正規化座標
    let endPoint: CGPoint    // 正規化座標
    let orientation: StrokeOrientation
    let boundingBox: CGRect  // 正規化座標
}

enum StrokeOrientation {
    case horizontal  // 横書き用（水平線）
    case vertical    // 縦書き用（垂直線）
}

extension TextLineDetector {

    /// ストロークを直線化して境界ボックスを計算
    /// - Parameters:
    ///   - strokePoints: 描画されたストロークの点（正規化座標 0-1）
    ///   - thickness: マーカーの太さ（正規化座標での幅）
    /// - Returns: 直線化されたストローク情報
    func straightenStroke(
        _ strokePoints: [CGPoint],
        thickness: CGFloat = 0.02
    ) -> StraightenedStroke? {
        guard strokePoints.count >= 2 else { return nil }

        // 始点と終点を取得
        let startPoint = strokePoints.first!
        let endPoint = strokePoints.last!

        // ストロークの主方向を判定
        let deltaX = abs(endPoint.x - startPoint.x)
        let deltaY = abs(endPoint.y - startPoint.y)
        let orientation: StrokeOrientation = deltaX > deltaY ? .horizontal : .vertical

        // 方向に応じて直線化
        let straightStart: CGPoint
        let straightEnd: CGPoint
        let boundingBox: CGRect

        switch orientation {
        case .horizontal:
            // 水平線：Y座標は平均、X座標は始点・終点のまま
            let avgY = (startPoint.y + endPoint.y) / 2
            straightStart = CGPoint(x: min(startPoint.x, endPoint.x), y: avgY)
            straightEnd = CGPoint(x: max(startPoint.x, endPoint.x), y: avgY)

            boundingBox = CGRect(
                x: straightStart.x,
                y: avgY - thickness / 2,
                width: straightEnd.x - straightStart.x,
                height: thickness
            )

        case .vertical:
            // 垂直線：X座標は平均、Y座標は始点・終点のまま
            let avgX = (startPoint.x + endPoint.x) / 2
            straightStart = CGPoint(x: avgX, y: min(startPoint.y, endPoint.y))
            straightEnd = CGPoint(x: avgX, y: max(startPoint.y, endPoint.y))

            boundingBox = CGRect(
                x: avgX - thickness / 2,
                y: straightStart.y,
                width: thickness,
                height: straightEnd.y - straightStart.y
            )
        }

        return StraightenedStroke(
            startPoint: straightStart,
            endPoint: straightEnd,
            orientation: orientation,
            boundingBox: boundingBox
        )
    }

    /// 直線化されたストロークをPDF座標に変換
    /// - Parameters:
    ///   - straightenedStroke: 直線化されたストローク
    ///   - pageSize: PDFページのサイズ
    ///   - isRightToLeft: 右開き（縦書き）モードか
    /// - Returns: PDF座標系の境界ボックス
    func convertStraightenedStrokeToPDF(
        _ straightenedStroke: StraightenedStroke,
        pageSize: CGSize,
        isRightToLeft: Bool
    ) -> CGRect {
        var box = straightenedStroke.boundingBox

        // 正規化座標からPDF座標に変換
        var pdfRect = CGRect(
            x: box.origin.x * pageSize.width,
            y: box.origin.y * pageSize.height,
            width: box.width * pageSize.width,
            height: box.height * pageSize.height
        )

        // 右開き（縦書き）モードの場合、X座標を反転
        if isRightToLeft {
            pdfRect = CGRect(
                x: pageSize.width - pdfRect.origin.x - pdfRect.width,
                y: pdfRect.origin.y,
                width: pdfRect.width,
                height: pdfRect.height
            )
        }

        return pdfRect
    }
}

// MARK: - CGRect Extension

extension CGRect {
    /// 矩形の中心点
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    /// 2つの矩形間の距離
    func distance(to other: CGRect) -> CGFloat {
        hypot(center.x - other.center.x, center.y - other.center.y)
    }
}

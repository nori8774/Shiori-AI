import SwiftUI
import PencilKit
import PDFKit

// Note: PKCanvasViewの標準実装を使用
// drawingPolicy = .pencilOnly により、Apple Pencilのみで描画可能
// 指タッチの透過は別の方法で実装する必要がある場合は、
// PKCanvasViewのサブクラスではなく、ジェスチャー認識器のdelegate設定で対応

// 現在の実装: 通常のPKCanvasViewを使用し、drawingPolicyで制御

// MARK: - Marker Overlay View (SwiftUI)

struct MarkerOverlayView: View {
    @ObservedObject var markerManager = SmartMarkerManager.shared

    let pdfView: PDFView
    let currentBook: Book?
    let currentPageIndex: Int
    let isRightToLeft: Bool  // 縦書き（右開き）モード

    @State private var canvasView = PKCanvasView()

    var body: some View {
        // ContentViewでisMarkerMode時のみ表示されるため、ここでは常にキャンバスを表示
        MarkerCanvasRepresentable(
            canvasView: $canvasView,
            pdfView: pdfView,
            currentBook: currentBook,
            currentPageIndex: currentPageIndex,
            isMarkerMode: markerManager.isMarkerMode,
            selectedColor: markerManager.selectedColor,
            selectedThickness: markerManager.selectedThickness,
            isRightToLeft: isRightToLeft
        )
    }
}

// MARK: - Canvas Representable (UIKit Bridge)

struct MarkerCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    let pdfView: PDFView
    let currentBook: Book?
    let currentPageIndex: Int
    let isMarkerMode: Bool
    let selectedColor: MarkerColor
    let selectedThickness: MarkerThickness
    let isRightToLeft: Bool  // 縦書き（右開き）モード

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .pencilOnly  // Apple Pencilのみ

        // PKCanvasView内のスクロールを無効化（ページ送りと干渉しないように）
        canvasView.isScrollEnabled = false

        // ツール設定
        updateTool()

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.isUserInteractionEnabled = isMarkerMode
        context.coordinator.parent = self  // 親を更新
        updateTool()
    }

    private func updateTool() {
        let inkingTool = PKInkingTool(
            .marker,
            color: selectedColor.uiColor.withAlphaComponent(0.8),
            width: selectedThickness.height * 2
        )
        canvasView.tool = inkingTool
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: MarkerCanvasRepresentable
        let textLineDetector = TextLineDetector()  // ストローク直線化に使用

        init(_ parent: MarkerCanvasRepresentable) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // 描画が完了したらスナップ処理を実行
            guard !canvasView.drawing.strokes.isEmpty else { return }

            processStrokes(canvasView.drawing.strokes, canvasView: canvasView)
        }

        private func processStrokes(_ strokes: [PKStroke], canvasView: PKCanvasView) {
            guard let book = parent.currentBook else { return }
            guard let currentPage = parent.pdfView.currentPage else { return }
            guard let document = parent.pdfView.document else { return }

            // PDFViewから直接現在のページインデックスを取得（より正確）
            var pageIndex = document.index(for: currentPage)

            // 最後のストロークを処理
            guard let lastStroke = strokes.last else { return }

            // ストロークの点を取得
            let strokePoints = lastStroke.path.map { point in
                CGPoint(x: point.location.x, y: point.location.y)
            }

            // キャンバスをクリア（すぐにクリアして描画の残りを消す）
            DispatchQueue.main.async {
                canvasView.drawing = PKDrawing()
            }

            // PDFページのサイズとスケール
            let pageRect = currentPage.bounds(for: .mediaBox)
            let pdfView = parent.pdfView
            let scaleFactor = pdfView.scaleFactor
            let viewSize = canvasView.bounds.size

            // 見開きモードかどうかを判定
            let isTwoUp = pdfView.displayMode == .twoUp
            let isRTL = parent.isRightToLeft

            // PDFViewでのページ表示領域を計算
            let scaledPageWidth = pageRect.width * scaleFactor
            let scaledPageHeight = pageRect.height * scaleFactor

            // オフセットの計算
            let offsetX: CGFloat
            let offsetY: CGFloat

            // 実際にマーカーを追加するページを決定
            var targetPage = currentPage

            if isTwoUp {
                // 見開きモード：2ページ分の幅を考慮
                let twoPageWidth = scaledPageWidth * 2
                let baseOffsetX = (viewSize.width - twoPageWidth) / 2
                offsetY = (viewSize.height - scaledPageHeight) / 2

                // 見開きモードでは、ストロークの位置から実際に描画したページを判定する
                let strokeX = strokePoints.first?.x ?? 0
                let centerX = viewSize.width / 2

                // ストロークが画面の左半分か右半分かを判定
                // ストローク座標系では: strokeX < centerX が左半分
                // RTLモードでもPKCanvasViewの座標系は反転しない（PDFViewのみ反転）
                let isStrokeOnLeftSide = strokeX < centerX

                // オフセットを設定（RTLモードでもストローク座標は反転しているので、そのまま使用）
                if strokeX < centerX {
                    offsetX = baseOffsetX  // ストローク座標での左側
                } else {
                    offsetX = baseOffsetX + scaledPageWidth  // ストローク座標での右側
                }

                // 見開きで表示されているページペアを特定
                // visiblePagesを使って実際に表示されているページを取得
                let visiblePages = pdfView.visiblePages
                let visibleIndices = visiblePages.compactMap { document.index(for: $0) }.sorted()

                print("visiblePages indices: \(visibleIndices)")

                // 実際に表示されている2ページから選択
                let actualTargetPageIndex: Int
                if visibleIndices.count >= 2 {
                    // 2ページ表示されている場合
                    let smallerIdx = visibleIndices[0]
                    let largerIdx = visibleIndices[1]

                    // PDFKitの論理配置: 左=smallerIdx、右=largerIdx
                    // RTLモードでは画面が scaleX: -1 で反転されているため、
                    // ユーザーの見た目: 左=largerIdx、右=smallerIdx
                    //
                    // isStrokeOnLeftSide は「ユーザーが画面のどちら側に描いたか」を示す
                    // RTL: 画面左側に描いた → largerIdxに追加
                    // RTL: 画面右側に描いた → smallerIdxに追加
                    if isRTL {
                        if isStrokeOnLeftSide {
                            actualTargetPageIndex = largerIdx   // 画面左側 = 大きい番号
                        } else {
                            actualTargetPageIndex = smallerIdx  // 画面右側 = 小さい番号
                        }
                    } else {
                        // LTR: 画面左側 = 小さい番号、画面右側 = 大きい番号
                        if isStrokeOnLeftSide {
                            actualTargetPageIndex = smallerIdx
                        } else {
                            actualTargetPageIndex = largerIdx
                        }
                    }
                } else if visibleIndices.count == 1 {
                    // 1ページのみ表示（最初や最後のページ）
                    actualTargetPageIndex = visibleIndices[0]
                } else {
                    // フォールバック
                    actualTargetPageIndex = document.index(for: currentPage)
                }

                // ページが有効範囲内かチェック
                if actualTargetPageIndex >= 0 && actualTargetPageIndex < document.pageCount {
                    pageIndex = actualTargetPageIndex
                    if let page = document.page(at: actualTargetPageIndex) {
                        targetPage = page
                    }
                }

                print("strokeX: \(strokeX), centerX: \(centerX), isStrokeOnLeftSide (screen): \(isStrokeOnLeftSide)")
                print("pdfView.currentPage index: \(document.index(for: currentPage)), visiblePages: \(visibleIndices)")
                print("Actual target pageIndex: \(pageIndex)")
            } else {
                // 単ページモード：中央配置
                offsetX = (viewSize.width - scaledPageWidth) / 2
                offsetY = (viewSize.height - scaledPageHeight) / 2
            }

            // デバッグ情報
            print("=== Marker Debug ===")
            print("Canvas size: \(viewSize)")
            print("PDF page size: \(pageRect.size)")
            print("Scale factor: \(scaleFactor)")
            print("Scaled page size: (\(scaledPageWidth), \(scaledPageHeight))")
            print("isTwoUp: \(isTwoUp)")
            print("Offset: (\(offsetX), \(offsetY))")
            print("isRTL: \(isRTL)")
            print("pageIndex: \(pageIndex)")
            if let firstPoint = strokePoints.first {
                print("Stroke first point (screen): \(firstPoint)")
            }

            // ストロークの点をPDF座標に変換
            let normalizedPoints = strokePoints.map { point -> CGPoint in
                // 画面座標からPDF表示領域内の相対座標に変換
                let relativeX = (point.x - offsetX) / scaledPageWidth
                let relativeY = (point.y - offsetY) / scaledPageHeight

                // Y座標を反転（画面座標は上が0、PDF座標は下が0）
                let normalizedY = 1.0 - relativeY

                return CGPoint(x: relativeX, y: normalizedY)
            }

            if let firstNorm = normalizedPoints.first {
                print("Normalized first point: \(firstNorm)")
            }
            print("===================")

            // フリーハンドモードでマーカー処理
            processFreeformStroke(normalizedPoints, book: book, pageIndex: pageIndex, targetPage: targetPage, pageRect: pageRect, isRTL: isRTL)
        }

        // MARK: - Freeform Mode (図形認識：描いた線を直線化)

        private func processFreeformStroke(
            _ normalizedPoints: [CGPoint],
            book: Book,
            pageIndex: Int,
            targetPage: PDFPage,
            pageRect: CGRect,
            isRTL: Bool
        ) {
            // マーカーの太さを正規化座標で計算
            let thickness: CGFloat = CGFloat(parent.selectedThickness.height) / pageRect.height * 1.5

            // ストロークを直線化
            guard let straightened = textLineDetector.straightenStroke(normalizedPoints, thickness: thickness) else {
                return
            }

            // PDF座標に変換（RTL変換はnormalizedPointsで済んでいるのでここでは行わない）
            let pdfBounds = textLineDetector.convertStraightenedStrokeToPDF(
                straightened,
                pageSize: pageRect.size,
                isRightToLeft: false  // RTL変換は既に適用済み
            )

            // メインスレッドでマーカーを追加
            DispatchQueue.main.async {
                // マーカーを追加（テキストは空文字列）
                let marker = SmartMarkerManager.shared.addMarker(
                    bookId: book.id,
                    pdfFileName: book.fileName,
                    pageIndex: pageIndex,
                    bounds: pdfBounds,
                    text: ""  // フリーハンドモードではテキストなし
                )

                // PDFにアノテーションを追加
                let annotation = SmartMarkerManager.shared.createAnnotation(for: marker)
                targetPage.addAnnotation(annotation)

                // PDFViewを更新
                self.parent.pdfView.setNeedsDisplay()
            }
        }

    }
}

// MARK: - Marker Toolbar View (Popover用コンパクト版)

struct MarkerToolbarView: View {
    @ObservedObject var markerManager = SmartMarkerManager.shared
    @Binding var isPresented: Bool

    // マーカー削除用（オプショナル）
    var pdfFileName: String?
    var pageIndex: Int?
    var pdfView: PDFView?

    /// 表示されているページのインデックス一覧（見開き時は2ページ）
    var visiblePageIndices: [Int] {
        guard let pdfView = pdfView,
              let document = pdfView.document else {
            if let pageIndex = pageIndex {
                return [pageIndex]
            }
            return []
        }

        let visiblePages = pdfView.visiblePages
        return visiblePages.compactMap { document.index(for: $0) }.sorted()
    }

    var body: some View {
        VStack(spacing: 12) {
            // ヘッダー（タイトルのみ、トグルは上部メニューのタップで行う）
            HStack {
                Image(systemName: "pencil.tip.crop.circle.fill")
                    .foregroundColor(markerManager.selectedColor.swiftUIColor)
                Text("マーカー設定")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // 色選択（横並び）
            VStack(alignment: .leading, spacing: 6) {
                Text("色")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(MarkerColor.allCases, id: \.self) { color in
                        Button(action: {
                            markerManager.selectedColor = color
                        }) {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            markerManager.selectedColor == color ? Color.primary : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: markerManager.selectedColor == color ? color.swiftUIColor.opacity(0.5) : .clear, radius: 3)
                        }
                    }
                }
            }

            // 太さ選択（横並び）
            VStack(alignment: .leading, spacing: 6) {
                Text("太さ")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(MarkerThickness.allCases, id: \.self) { thickness in
                        Button(action: {
                            markerManager.selectedThickness = thickness
                        }) {
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(markerManager.selectedColor.swiftUIColor)
                                    .frame(width: 50, height: max(4, thickness.height * 0.8))

                                Text(thickness.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(markerManager.selectedThickness == thickness
                                          ? Color.gray.opacity(0.2)
                                          : Color.clear)
                            )
                        }
                    }
                }
            }

            Text("Apple Pencilで線を引くとハイライト\n指でスワイプするとページ送り")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // このページのマーカー一覧（個別削除用）- 見開き時は両ページ分表示
            if let pdfFileName = pdfFileName {
                let pageIndices = visiblePageIndices
                let allMarkers = pageIndices.flatMap { idx in
                    markerManager.getMarkers(for: pdfFileName, pageIndex: idx)
                }

                if !allMarkers.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        let pageLabel = pageIndices.count > 1
                            ? "表示中のページ（p.\(pageIndices.map { String($0 + 1) }.joined(separator: ", "))）"
                            : "このページ"
                        Text("\(pageLabel)のマーカー（\(allMarkers.count)件）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // マーカー一覧をスクロール可能なリストで表示
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(allMarkers) { marker in
                                    MarkerDeleteRowView(
                                        marker: marker,
                                        pdfView: pdfView,
                                        pageLabel: pageIndices.count > 1 ? "p.\(marker.pageIndex + 1)" : nil,
                                        onDelete: {
                                            deleteMarker(marker)
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func deleteMarker(_ marker: Marker) {
        // マーカーを削除
        markerManager.removeMarker(marker)

        // PDFからアノテーションも削除
        if let pdfView = pdfView,
           let page = pdfView.document?.page(at: marker.pageIndex) {
            // 該当するアノテーションを削除
            for annotation in page.annotations {
                if annotation.bounds == marker.cgRectBounds {
                    page.removeAnnotation(annotation)
                    break
                }
            }
            pdfView.setNeedsDisplay()
        }

        // このページにマーカーがなくなったらしおりも削除
        guard let pdfFileName = pdfFileName else { return }
        if !markerManager.hasMarkers(for: pdfFileName, pageIndex: marker.pageIndex) {
            BookmarkManager.shared.removeBookmark(pdfFileName: pdfFileName, pageIndex: marker.pageIndex)
        }
    }
}

// MARK: - Marker Delete Row View (ポップオーバー内の個別削除用)

struct MarkerDeleteRowView: View {
    let marker: Marker
    var pdfView: PDFView?
    var pageLabel: String?  // 見開き時にページ番号を表示
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            // 色インジケーター
            Circle()
                .fill(marker.color.swiftUIColor)
                .frame(width: 16, height: 16)

            // テキストまたは位置情報
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let pageLabel = pageLabel {
                        Text(pageLabel)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(4)
                    }

                    if marker.text.isEmpty {
                        Text("フリーハンドマーカー")
                            .font(.caption)
                            .foregroundColor(.primary)
                    } else {
                        Text(marker.text)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }

                Text(marker.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 削除ボタン
            Button(action: {
                showDeleteConfirm = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(marker.color.swiftUIColor.opacity(0.15))
        )
        .alert("マーカーを削除", isPresented: $showDeleteConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("このマーカーを削除しますか？")
        }
    }
}

// MARK: - Marker List View (for viewing all markers on a page)

struct MarkerListView: View {
    let pdfFileName: String
    let pageIndex: Int

    @ObservedObject var markerManager = SmartMarkerManager.shared
    @Environment(\.dismiss) private var dismiss

    var markers: [Marker] {
        markerManager.getMarkers(for: pdfFileName, pageIndex: pageIndex)
    }

    var body: some View {
        NavigationView {
            List {
                if markers.isEmpty {
                    Text("このページにはマーカーがありません")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(markers) { marker in
                        MarkerRowView(marker: marker)
                    }
                    .onDelete(perform: deleteMarkers)
                }
            }
            .navigationTitle("マーカー一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func deleteMarkers(at offsets: IndexSet) {
        for index in offsets {
            let marker = markers[index]
            markerManager.removeMarker(marker)
        }
    }
}

struct MarkerRowView: View {
    let marker: Marker
    @ObservedObject var markerManager = SmartMarkerManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // 色インジケーター
            Circle()
                .fill(marker.color.swiftUIColor)
                .frame(width: 12, height: 12)

            // テキスト
            VStack(alignment: .leading, spacing: 4) {
                Text(marker.text)
                    .font(.body)
                    .lineLimit(2)

                Text(marker.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 色変更メニュー
            Menu {
                ForEach(MarkerColor.allCases, id: \.self) { color in
                    Button(action: {
                        markerManager.updateMarkerColor(marker, newColor: color)
                    }) {
                        Label(color.displayName, systemImage: "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MarkerToolbarView(isPresented: .constant(true))
}

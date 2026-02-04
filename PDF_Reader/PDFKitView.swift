import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let url: URL
    let isRightToLeft: Bool // true: 右開き（縦書き）
    let isTwoUp: Bool       // true: 見開き
    @Binding var currentPageIndex: Int
    // ページめくりアニメーション用
    @Binding var isPageTurnAnimating: Bool
    @Binding var pageTurnDirection: PageTurnDirection
    @Binding var currentPageImage: UIImage?
    @Binding var nextPageImage: UIImage?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFWrapperView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .systemGray6
        pdfView.autoScales = false  // 手動でスケール制御
        pdfView.displayDirection = .horizontal
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 4.0
        pdfView.isUserInteractionEnabled = true

        // ページ内スクロールを無効化（ページ固定）
        pdfView.pageShadowsEnabled = false

        PDFManager.shared.currentPDFView = pdfView

        // ラッパー作成
        let wrapper = PDFWrapperView(pdfView: pdfView)

        // ジェスチャー設定
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeLeft.direction = .left
        wrapper.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeRight.direction = .right
        wrapper.addGestureRecognizer(swipeRight)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return wrapper
    }
    
    func updateUIView(_ wrapper: PDFWrapperView, context: Context) {
        let pdfView = wrapper.pdfView
        PDFManager.shared.currentPDFView = pdfView
        context.coordinator.parent = self
        context.coordinator.wrapper = wrapper  // Coordinatorにwrapperを保持

        // 設定適用
        wrapper.isRightToLeft = isRightToLeft
        wrapper.isTwoUp = isTwoUp

        // ドキュメントまたは表示モードが変わったかチェック
        let documentChanged = wrapper.currentDocumentURL != url
        let targetMode: PDFDisplayMode = isTwoUp ? .twoUp : .singlePage
        let modeChanged = wrapper.currentDisplayMode != targetMode

        // 1. ドキュメント読み込み
        if documentChanged {
            if let document = PDFDocument(url: url) {
                pdfView.document = document
                wrapper.currentDocumentURL = url
                wrapper.hasInitializedScale = false  // 新しいドキュメントなのでスケール再計算
                wrapper.optimalScale = 0  // スケールリセット

                // 保存されたマーカーを復元
                restoreMarkers(to: document, pdfFileName: url.lastPathComponent)
            }
        }

        // 2. 表示モード
        if modeChanged {
            if isTwoUp {
                pdfView.displayMode = .twoUp
                pdfView.displaysAsBook = true
            } else {
                pdfView.displayMode = .singlePage
            }
            wrapper.currentDisplayMode = targetMode
            wrapper.hasInitializedScale = false  // モード変更時もスケール再計算
            wrapper.optimalScale = 0  // スケールリセット
        }

        // 3. スケール調整（初回またはドキュメント/モード変更時のみ）
        if !wrapper.hasInitializedScale {
            // layoutSubviewsが呼ばれた後にスケールを計算
            DispatchQueue.main.async {
                wrapper.calculateAndApplyOptimalScale()
            }
        }

        // 4. ページ位置復元
        if let doc = pdfView.document,
           let page = doc.page(at: currentPageIndex) {
            if pdfView.currentPage != page {
                DispatchQueue.main.async {
                    pdfView.go(to: page)
                    // ページ移動後にスケールを再適用
                    if wrapper.optimalScale > 0 {
                        pdfView.scaleFactor = wrapper.optimalScale
                    }
                }
            }
        }

        wrapper.setNeedsLayout()
    }
    
    // ドキュメント全体の最大ページサイズを取得
    private func getMaxPageSize(document: PDFDocument) -> CGSize {
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                let bounds = page.bounds(for: .mediaBox)
                maxWidth = max(maxWidth, bounds.width)
                maxHeight = max(maxHeight, bounds.height)
            }
        }

        return CGSize(width: maxWidth, height: maxHeight)
    }

    // 画面にフィットするようにスケール調整（はみ出さないように表示）
    private func adjustScaleToFitHeight(pdfView: PDFView, wrapper: PDFWrapperView) {
        guard let document = pdfView.document else { return }

        // ドキュメント全体の最大ページサイズを基準にする
        let maxPageSize = getMaxPageSize(document: document)
        let viewHeight = wrapper.bounds.height
        let viewWidth = wrapper.bounds.width

        guard viewHeight > 0 && viewWidth > 0 && maxPageSize.height > 0 && maxPageSize.width > 0 else { return }

        // 高さと幅の両方を考慮
        let heightScale = viewHeight / maxPageSize.height

        if isTwoUp {
            // 見開き表示
            let twoPageWidth = maxPageSize.width * 2
            let widthScale = viewWidth / twoPageWidth
            // 高さと幅の小さい方に合わせる（はみ出し防止）
            let scale = min(heightScale, widthScale)
            pdfView.scaleFactor = scale
            wrapper.optimalScale = scale
        } else {
            // 単ページ：幅いっぱいに表示
            let widthScale = viewWidth / maxPageSize.width
            pdfView.scaleFactor = widthScale
            wrapper.optimalScale = widthScale
        }

        // スクロール位置をセンタリング
        centerPage(pdfView: pdfView)
    }

    // ページをビューの中央に配置
    private func centerPage(pdfView: PDFView) {
        guard let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView else { return }

        // スクロールを無効化してページを固定
        scrollView.isScrollEnabled = false

        // コンテンツをセンタリング
        let contentSize = scrollView.contentSize
        let boundsSize = scrollView.bounds.size

        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0

        if contentSize.width > boundsSize.width {
            offsetX = (contentSize.width - boundsSize.width) / 2
        }
        if contentSize.height > boundsSize.height {
            offsetY = (contentSize.height - boundsSize.height) / 2
        }

        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    // 保存されたマーカーをPDFドキュメントに復元
    private func restoreMarkers(to document: PDFDocument, pdfFileName: String) {
        let markerManager = SmartMarkerManager.shared
        let markers = markerManager.getMarkers(for: pdfFileName)

        for marker in markers {
            guard let page = document.page(at: marker.pageIndex) else { continue }

            // 既存のアノテーションと重複しないかチェック
            let existingAnnotations = page.annotations
            let alreadyExists = existingAnnotations.contains { annotation in
                annotation.bounds == marker.cgRectBounds && annotation.type == "Highlight"
            }

            if !alreadyExists {
                let annotation = markerManager.createAnnotation(for: marker)
                page.addAnnotation(annotation)
            }
        }
    }

    // --- 座標反転ラッパー ---
    class PDFWrapperView: UIView {
        let pdfView: PDFView
        var isRightToLeft: Bool = false {
            didSet { setNeedsLayout() }
        }
        var isTwoUp: Bool = false

        // スケール管理用
        var hasInitializedScale: Bool = false
        var currentDocumentURL: URL?
        var currentDisplayMode: PDFDisplayMode?
        var optimalScale: CGFloat = 1.0
        private var lastBoundsSize: CGSize = .zero

        init(pdfView: PDFView) {
            self.pdfView = pdfView
            super.init(frame: .zero)
            addSubview(pdfView)
            pdfView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pdfView.topAnchor.constraint(equalTo: topAnchor),
                pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
                pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
                pdfView.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()

            // boundsが変わった場合、またはスケールが初期化されていない場合にスケールを適用
            let boundsChanged = lastBoundsSize != bounds.size
            if boundsChanged {
                lastBoundsSize = bounds.size
                // boundsが変わったらスケールを再計算
                if bounds.height > 0 && bounds.width > 0 {
                    calculateAndApplyOptimalScale()
                }
            }

            // スケールが計算済みで、boundsが有効な場合は適用
            if optimalScale > 0 && bounds.height > 0 {
                if pdfView.scaleFactor != optimalScale {
                    pdfView.scaleFactor = optimalScale
                }
            } else if !hasInitializedScale && bounds.height > 0 && bounds.width > 0 {
                // 初回スケール計算がまだの場合はここで計算
                calculateAndApplyOptimalScale()
            }

            // まず全てリセット
            pdfView.transform = .identity
            resetSubviewsTransforms(in: pdfView)

            if isRightToLeft {
                // 1. PDFView全体を左右反転（鏡像）
                // これで [29][30] が [30(鏡)][29(鏡)] という配置に入れ替わります
                pdfView.transform = CGAffineTransform(scaleX: -1, y: 1)

                // 2. ページの中身だけを反転し返す
                // DocumentView自体は反転させず（位置キープ）、その子供である「PageView」だけを反転させます
                flipPagesOnly(in: pdfView)
            }

            // スクロールを無効化
            disableScrolling()
        }

        func disableScrolling() {
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.isScrollEnabled = false
            }
        }

        func calculateAndApplyOptimalScale() {
            guard let document = pdfView.document else { return }
            guard bounds.height > 0 && bounds.width > 0 else { return }

            // ドキュメント全体の最大ページサイズを基準にする
            var maxWidth: CGFloat = 0
            var maxHeight: CGFloat = 0
            for i in 0..<document.pageCount {
                if let page = document.page(at: i) {
                    let pageBounds = page.bounds(for: .mediaBox)
                    maxWidth = max(maxWidth, pageBounds.width)
                    maxHeight = max(maxHeight, pageBounds.height)
                }
            }

            guard maxHeight > 0 && maxWidth > 0 else { return }

            // 高さと幅の両方を考慮して、はみ出さないスケールを計算
            let heightScale = bounds.height / maxHeight

            if isTwoUp {
                let twoPageWidth = maxWidth * 2
                let widthScale = bounds.width / twoPageWidth
                // 見開き：高さと幅の小さい方に合わせる（はみ出し防止）
                optimalScale = min(heightScale, widthScale)
            } else {
                // 単ページ：高さと幅の小さい方に合わせる（横向きでもはみ出し防止）
                let widthScale = bounds.width / maxWidth
                optimalScale = min(heightScale, widthScale)
            }

            pdfView.scaleFactor = optimalScale
            hasInitializedScale = true
        }
        
        private func flipPagesOnly(in view: UIView) {
            // ScrollViewを探す
            if let scrollView = view.subviews.first(where: { $0 is UIScrollView }) {
                // ScrollViewの中には DocumentView (コンテンツ全体) がある
                for documentView in scrollView.subviews {
                    // DocumentViewの中には各ページのビューがある
                    for pageView in documentView.subviews {
                        // 個々のページだけを反転させて、文字を読めるようにする
                        pageView.transform = CGAffineTransform(scaleX: -1, y: 1)
                    }
                }
            }
        }
        
        private func resetSubviewsTransforms(in view: UIView) {
            for subview in view.subviews {
                subview.transform = .identity
                resetSubviewsTransforms(in: subview)
            }
        }
    }
    
    class Coordinator: NSObject {
        var parent: PDFKitView
        weak var wrapper: PDFWrapperView?

        init(parent: PDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let index = document.index(for: currentPage)
            if parent.currentPageIndex != index {
                DispatchQueue.main.async {
                    self.parent.currentPageIndex = index
                }
            }

            // ページ変更後にスケールを再適用（PDFViewがリセットする場合があるため）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self,
                      let wrapper = self.wrapper,
                      wrapper.optimalScale > 0 else { return }
                if pdfView.scaleFactor != wrapper.optimalScale {
                    pdfView.scaleFactor = wrapper.optimalScale
                    wrapper.disableScrolling()
                }
            }
        }
        
        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let wrapper = gesture.view as? PDFWrapperView else { return }
            let pdfView = wrapper.pdfView

            let isRTL = parent.isRightToLeft
            let isNext: Bool

            if isRTL {
                // 右開き（縦書き）：右へスワイプ（→）で次へ（ページをめくる）
                if gesture.direction == .right { isNext = true } else { isNext = false }
            } else {
                // 左開き（横書き）：左へスワイプ（←）で次へ
                isNext = (gesture.direction == .left)
            }

            // アニメーションが有効な場合
            if PageTurnSettings.shared.isPageTurnAnimationEnabled {
                let canNavigate = isNext ? pdfView.canGoToNextPage : pdfView.canGoToPreviousPage

                if canNavigate {
                    // 現在のページをキャプチャ
                    let currentImage = capturePageImage(pdfView: pdfView)

                    // 次/前のページに移動
                    if isNext {
                        pdfView.goToNextPage(nil)
                    } else {
                        pdfView.goToPreviousPage(nil)
                    }

                    // スケールを再適用
                    reapplyScale(pdfView: pdfView, wrapper: wrapper)

                    // 移動後のページをキャプチャ
                    let nextImage = capturePageImage(pdfView: pdfView)

                    // アニメーション開始
                    DispatchQueue.main.async {
                        self.parent.currentPageImage = currentImage
                        self.parent.nextPageImage = nextImage
                        self.parent.pageTurnDirection = isNext ? .left : .right
                        self.parent.isPageTurnAnimating = true
                    }
                }
            } else {
                // アニメーションなしで通常のページ移動
                if isNext {
                    if pdfView.canGoToNextPage {
                        pdfView.goToNextPage(nil)
                        reapplyScale(pdfView: pdfView, wrapper: wrapper)
                    }
                } else {
                    if pdfView.canGoToPreviousPage {
                        pdfView.goToPreviousPage(nil)
                        reapplyScale(pdfView: pdfView, wrapper: wrapper)
                    }
                }
            }
        }

        private func reapplyScale(pdfView: PDFView, wrapper: PDFWrapperView) {
            // ページ移動直後にスケールを再適用
            if wrapper.optimalScale > 0 {
                pdfView.scaleFactor = wrapper.optimalScale
                wrapper.disableScrolling()
            }
        }

        private func capturePageImage(pdfView: PDFView) -> UIImage? {
            guard let currentPage = pdfView.currentPage else { return nil }

            let pageRect = currentPage.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0  // Retina用

            let renderer = UIGraphicsImageRenderer(size: CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            ))

            let isRTL = parent.isRightToLeft

            return renderer.image { ctx in
                ctx.cgContext.scaleBy(x: scale, y: scale)
                ctx.cgContext.translateBy(x: 0, y: pageRect.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)

                // 右開きモードの場合、ページを水平反転してキャプチャ
                // （表示と同じ向きにするため）
                if isRTL {
                    ctx.cgContext.translateBy(x: pageRect.width, y: 0)
                    ctx.cgContext.scaleBy(x: -1, y: 1)
                }

                currentPage.draw(with: .mediaBox, to: ctx.cgContext)
            }
        }
    }
    
    static func addHighlightToSelection() {
        guard let pdfView = PDFManager.shared.currentPDFView,
              let selection = pdfView.currentSelection else { return }
        selection.pages.forEach { page in
            let highlight = PDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
            highlight.color = .yellow
            highlight.endLineStyle = .square
            page.addAnnotation(highlight)
        }
        pdfView.clearSelection()
    }
}

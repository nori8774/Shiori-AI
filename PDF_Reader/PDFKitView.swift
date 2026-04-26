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
        wrapper.coordinator = context.coordinator

        // ジェスチャー設定
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeLeft.direction = .left
        wrapper.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeRight.direction = .right
        wrapper.addGestureRecognizer(swipeRight)

        // ピンチジェスチャー（ズーム）
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        wrapper.addGestureRecognizer(pinch)

        // ダブルタップでズームリセット
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        wrapper.addGestureRecognizer(doubleTap)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // スケール変更通知でズーム状態を検出
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )

        return wrapper
    }

    func updateUIView(_ wrapper: PDFWrapperView, context: Context) {
        let pdfView = wrapper.pdfView
        PDFManager.shared.currentPDFView = pdfView
        context.coordinator.parent = self
        context.coordinator.wrapper = wrapper

        // ドキュメントまたは表示モードが変わったかチェック
        let documentChanged = wrapper.currentDocumentURL != url
        let targetMode: PDFDisplayMode = isTwoUp ? .twoUp : .singlePage
        let modeChanged = wrapper.currentDisplayMode != targetMode

        // 設定適用
        wrapper.isRightToLeft = isRightToLeft
        wrapper.isTwoUp = isTwoUp

        // 1. ドキュメント読み込み
        if documentChanged {
            if let document = PDFDocument(url: url) {
                pdfView.document = document
                wrapper.currentDocumentURL = url
                wrapper.hasInitializedScale = false
                wrapper.optimalScale = 0

                // 保存されたマーカーを復元
                restoreMarkers(to: document, pdfFileName: url.lastPathComponent)
            }
        }

        // 2. 表示モード変更
        if modeChanged {
            // モード変更中はレイアウトループを防止
            wrapper.isSwitchingMode = true

            if isTwoUp {
                pdfView.displayMode = .twoUp
                pdfView.displaysAsBook = true
            } else {
                pdfView.displayMode = .singlePage
            }
            wrapper.currentDisplayMode = targetMode
            wrapper.hasInitializedScale = false
            wrapper.optimalScale = 0
        }

        // 3. スケール調整（モード変更時は少し遅延させてPDFViewの内部レイアウト完了を待つ）
        if !wrapper.hasInitializedScale {
            let delay: TimeInterval = modeChanged ? 0.1 : 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                wrapper.calculateAndApplyOptimalScale()
                wrapper.isSwitchingMode = false
            }
        }

        // 4. ページ位置復元（ユーザーズーム中はスキップ）
        if !wrapper.isUserZooming {
            if let doc = pdfView.document,
               let page = doc.page(at: currentPageIndex) {
                if pdfView.currentPage != page {
                    let delay: TimeInterval = modeChanged ? 0.15 : 0.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        pdfView.go(to: page)
                        if wrapper.optimalScale > 0 {
                            pdfView.scaleFactor = wrapper.optimalScale
                        }
                    }
                }
            }
        }

        // モード変更時はsetNeedsLayoutしない（遅延計算に任せる）
        if !modeChanged && !wrapper.isUserZooming {
            wrapper.setNeedsLayout()
        }
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
        var isRightToLeft: Bool = false
        var isTwoUp: Bool = false
        weak var coordinator: Coordinator?

        // スケール管理用
        var hasInitializedScale: Bool = false
        var currentDocumentURL: URL?
        var currentDisplayMode: PDFDisplayMode?
        var optimalScale: CGFloat = 1.0
        private var lastBoundsSize: CGSize = .zero
        private var isRecalculatingScale: Bool = false
        // モード切替中フラグ（layoutSubviewsのループ防止）
        var isSwitchingMode: Bool = false

        // ユーザーズーム状態管理
        var isUserZooming: Bool = false  // PDFViewがズームされているか
        var userScale: CGFloat = 0       // 現在のズーム倍率

        // ユーザーズーム中にページが変わった場合の保留ページインデックス
        var pendingPageIndex: Int?

        // ズーム時のパンジェスチャー（ラッパーに追加）
        var zoomPanGesture: UIPanGestureRecognizer?

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

        // hitTestオーバーライド: ズーム中は全タッチをラッパー自身で受け取る
        // （PDFView内部のジェスチャーにタッチが届かないようにする）
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if isUserZooming {
                return self.point(inside: point, with: event) ? self : nil
            }
            return super.hitTest(point, with: event)
        }

        /// ズーム時: ラッパーにパンジェスチャーを追加
        func activateZoomPan() {
            guard zoomPanGesture == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleZoomPan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            addGestureRecognizer(pan)
            zoomPanGesture = pan
            print("PDFWrapperView: activateZoomPan - added pan gesture to wrapper")
        }

        /// ズーム解除時: パンジェスチャーを削除
        func deactivateZoomPan() {
            if let pan = zoomPanGesture {
                removeGestureRecognizer(pan)
                zoomPanGesture = nil
            }
        }

        private func findInternalScrollView() -> UIScrollView? {
            func search(in view: UIView) -> UIScrollView? {
                for subview in view.subviews {
                    if let sv = subview as? UIScrollView { return sv }
                    if let sv = search(in: subview) { return sv }
                }
                return nil
            }
            return search(in: pdfView)
        }

        @objc private func handleZoomPan(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = findInternalScrollView() else { return }

            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)

            var newOffset = scrollView.contentOffset
            newOffset.x += translation.x
            newOffset.y -= translation.y

            // contentOffsetをコンテンツ範囲内にクランプ
            let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            newOffset.x = min(max(0, newOffset.x), maxX)
            newOffset.y = min(max(0, newOffset.y), maxY)

            scrollView.contentOffset = newOffset
        }

        func goToNextPage() {
            if pdfView.canGoToNextPage {
                resetUserZoom()
                pdfView.goToNextPage(nil)
                reapplyScale()
            }
        }

        func goToPreviousPage() {
            if pdfView.canGoToPreviousPage {
                resetUserZoom()
                pdfView.goToPreviousPage(nil)
                reapplyScale()
            }
        }

        /// ユーザーズームをリセットしてデフォルト倍率に戻す
        func resetUserZoom() {
            isUserZooming = false
            userScale = 0
            deactivateZoomPan()
            // 保留中のページインデックスをCoordinatorに通知
            if let pending = pendingPageIndex {
                pendingPageIndex = nil
                coordinator?.syncPageIndex(pending)
            }
        }

        private func reapplyScale() {
            if optimalScale > 0 {
                pdfView.scaleFactor = optimalScale
                disableScrolling()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // モード切替中はレイアウト処理をスキップ（updateUIViewの遅延処理に任せる）
            guard !isSwitchingMode else { return }
            // スケール再計算中のレイアウトループを防止
            guard !isRecalculatingScale else { return }

            // ユーザーがズーム中の場合はレイアウト処理を完全スキップ
            // （applyRTLTransformのresetSubviewsTransformsがPDFView内部状態を破壊するため）
            if isUserZooming {
                return
            }

            // boundsが変わった場合にスケールを再計算
            let boundsChanged = lastBoundsSize != bounds.size
            if boundsChanged && bounds.height > 0 && bounds.width > 0 {
                lastBoundsSize = bounds.size
                calculateAndApplyOptimalScale()
            }

            // スケールが計算済みで、boundsが有効な場合は適用
            if optimalScale > 0 && bounds.height > 0 {
                if abs(pdfView.scaleFactor - optimalScale) > 0.001 {
                    isRecalculatingScale = true
                    pdfView.scaleFactor = optimalScale
                    isRecalculatingScale = false
                }
            } else if !hasInitializedScale && bounds.height > 0 && bounds.width > 0 {
                calculateAndApplyOptimalScale()
            }

            // RTL対応
            applyRTLTransform()

            // スクロールを無効化（デフォルト表示時のみ）
            disableScrolling()
        }

        /// RTL対応のトランスフォームを適用
        private func applyRTLTransform() {
            pdfView.transform = .identity
            resetSubviewsTransforms(in: pdfView)

            if isRightToLeft {
                // 1. PDFView全体を左右反転（鏡像）
                pdfView.transform = CGAffineTransform(scaleX: -1, y: 1)

                // 2. ページの中身だけを反転し返す
                flipPagesOnly(in: pdfView)
            }
        }

        func disableScrolling() {
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                scrollView.isScrollEnabled = false
                scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
            }
        }

        /// ズーム中はスクロール（パン）を有効化（scaleChangedから呼ばれる）
        func enableScrolling() {
            // activateZoomPanはscaleChangedから直接呼ぶので、ここでは不要
        }

        func calculateAndApplyOptimalScale() {
            guard !isRecalculatingScale else { return }
            guard let document = pdfView.document else { return }
            guard bounds.height > 0 && bounds.width > 0 else { return }

            isRecalculatingScale = true
            defer { isRecalculatingScale = false }

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

            if let wrapper = self.wrapper, wrapper.isUserZooming {
                // ユーザーズーム中: ページインデックスを保留するのみ
                wrapper.pendingPageIndex = index
            } else {
                // 通常時: ページインデックスを更新
                if parent.currentPageIndex != index {
                    DispatchQueue.main.async {
                        self.parent.currentPageIndex = index
                    }
                }

                // デフォルトスケールに戻す
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self, let wrapper = self.wrapper else { return }
                    if wrapper.optimalScale > 0 {
                        if abs(pdfView.scaleFactor - wrapper.optimalScale) > 0.001 {
                            pdfView.scaleFactor = wrapper.optimalScale
                            wrapper.disableScrolling()
                        }
                    }
                }
            }
        }

        /// 保留中のページインデックスをSwiftUIバインディングに反映
        func syncPageIndex(_ index: Int) {
            if parent.currentPageIndex != index {
                parent.currentPageIndex = index
            }
        }

        /// PDFViewのスケール変更を検出（PDFView内蔵のピンチズームを検知）
        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let wrapper = self.wrapper else { return }

            let currentScale = pdfView.scaleFactor
            let optimalScale = wrapper.optimalScale

            guard optimalScale > 0 else { return }

            let isZoomed = abs(currentScale - optimalScale) / optimalScale > 0.05

            if isZoomed && !wrapper.isUserZooming {
                // ズームイン検出: パンモード有効化
                print("ZOOM DETECTED: scale=\(currentScale), optimal=\(optimalScale)")
                wrapper.isUserZooming = true
                wrapper.userScale = currentScale
                wrapper.activateZoomPan()
            } else if isZoomed && wrapper.isUserZooming {
                // ズーム中のスケール変更: userScaleを追従
                wrapper.userScale = currentScale
            } else if !isZoomed && wrapper.isUserZooming {
                // ズーム解除検出
                print("ZOOM RESET: scale=\(currentScale)")
                wrapper.resetUserZoom()
                wrapper.disableScrolling()
                wrapper.setNeedsLayout()
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            // PDFViewの内蔵ピンチに任せる（scaleChangedで検出）
            // このハンドラはフォールバック用
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let wrapper = gesture.view as? PDFWrapperView else { return }
            let pdfView = wrapper.pdfView

            if wrapper.isUserZooming {
                // ズーム中: デフォルト倍率に戻す
                wrapper.resetUserZoom()
                if wrapper.optimalScale > 0 {
                    pdfView.scaleFactor = wrapper.optimalScale
                }
                wrapper.disableScrolling()
                wrapper.setNeedsLayout()
            } else {
                // デフォルト表示中: 2倍に拡大
                let zoomScale = wrapper.optimalScale * 2.0
                let clampedScale = min(zoomScale, pdfView.maxScaleFactor)
                pdfView.scaleFactor = clampedScale
            }
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let wrapper = gesture.view as? PDFWrapperView else { return }
            let pdfView = wrapper.pdfView

            // ズーム中のスワイプ: まずズームを解除
            if wrapper.isUserZooming {
                wrapper.resetUserZoom()
                if wrapper.optimalScale > 0 {
                    pdfView.scaleFactor = wrapper.optimalScale
                }
                wrapper.disableScrolling()
                wrapper.setNeedsLayout()
            }

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
            wrapper.resetUserZoom()
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

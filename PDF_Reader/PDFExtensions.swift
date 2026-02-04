import PDFKit
import UIKit

extension PDFView {
    // 既存のメソッド
    func takeSnapshot() -> UIImage? {
        guard let page = self.currentPage else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image
    }
    
    // 【追加】現在のページ番号を取得するメソッド
    func getCurrentPageIndex() -> Int {
        guard let page = self.currentPage, let doc = self.document else { return 0 }
        return doc.index(for: page)
    }

    // 見開き表示時に両ページをキャプチャ（右開きモードにも対応）
    // 戻り値: (image, leftPageIndex, rightPageIndex)
    func takeSpreadSnapshot(isRightToLeft: Bool) -> UIImage? {
        let (image, _, _) = takeSpreadSnapshotWithIndices(isRightToLeft: isRightToLeft)
        return image
    }

    // 見開きスナップショットとページインデックスを取得
    func takeSpreadSnapshotWithIndices(isRightToLeft: Bool) -> (UIImage?, Int, Int) {
        guard let document = self.document,
              let currentPage = self.currentPage else { return (nil, -1, -1) }

        let currentIndex = document.index(for: currentPage)
        let pageCount = document.pageCount

        // 見開きのペアを決定
        // PDFViewの見開き表示(twoUpContiguous)では、currentPageは見開きの左側のページを返す
        let leftIndex: Int
        let rightIndex: Int

        if isRightToLeft {
            // 右開き（縦書き）：右から左に読む
            // 見開きでは大きい番号が左、小さい番号が右に表示される
            // 表示P20-21の場合（印刷番号）= インデックス19-20
            // currentIndex=19の場合: leftIndex=20(印刷21), rightIndex=19(印刷20)
            leftIndex = currentIndex + 1
            rightIndex = currentIndex
        } else {
            // 左開き（横書き）：左から右に読む
            // 見開きでは小さい番号が左、大きい番号が右に表示される
            leftIndex = currentIndex
            rightIndex = currentIndex + 1
        }

        print("takeSpreadSnapshot: currentIndex=\(currentIndex), leftIndex=\(leftIndex), rightIndex=\(rightIndex), isRightToLeft=\(isRightToLeft)")

        // 有効なページを取得
        let leftPage = (leftIndex >= 0 && leftIndex < pageCount) ? document.page(at: leftIndex) : nil
        let rightPage = (rightIndex >= 0 && rightIndex < pageCount) ? document.page(at: rightIndex) : nil

        // 両方ない場合は単一ページのスナップショットを返す
        guard leftPage != nil || rightPage != nil else {
            return (takeSnapshot(), currentIndex, currentIndex)
        }

        // 実際に取得できたページのインデックス
        let actualLeftIndex = leftPage != nil ? leftIndex : -1
        let actualRightIndex = rightPage != nil ? rightIndex : -1

        // ページサイズを取得（どちらかのページを基準に）
        let samplePage = leftPage ?? rightPage!
        let pageRect = samplePage.bounds(for: .mediaBox)

        // 見開きサイズを計算
        let spreadWidth = pageRect.width * 2
        let spreadHeight = pageRect.height
        let spreadSize = CGSize(width: spreadWidth, height: spreadHeight)

        let renderer = UIGraphicsImageRenderer(size: spreadSize)

        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: spreadSize))

            // 左ページを描画
            if let left = leftPage {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: spreadHeight)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                left.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }

            // 右ページを描画
            if let right = rightPage {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: pageRect.width, y: spreadHeight)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                right.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        }

        return (image, actualLeftIndex, actualRightIndex)
    }
}

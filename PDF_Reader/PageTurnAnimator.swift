import SwiftUI
import UIKit
import Combine

// MARK: - Page Turn Settings

class PageTurnSettings: ObservableObject {
    static let shared = PageTurnSettings()

    @Published var isPageTurnAnimationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPageTurnAnimationEnabled, forKey: "pageTurnAnimationEnabled")
        }
    }

    @Published var animationSpeed: Double {
        didSet {
            UserDefaults.standard.set(animationSpeed, forKey: "pageTurnAnimationSpeed")
        }
    }

    private init() {
        self.isPageTurnAnimationEnabled = UserDefaults.standard.bool(forKey: "pageTurnAnimationEnabled")
        self.animationSpeed = UserDefaults.standard.double(forKey: "pageTurnAnimationSpeed")
        if animationSpeed == 0 {
            animationSpeed = 0.5  // デフォルト値
        }
    }
}

// MARK: - Page Turn Animation View

struct PageTurnAnimationView: View {
    let currentImage: UIImage?
    let nextImage: UIImage?
    let direction: PageTurnDirection
    @Binding var isAnimating: Bool
    var onAnimationComplete: (() -> Void)?

    @State private var animationProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 次のページ（背景）
                if let nextImage = nextImage {
                    Image(uiImage: nextImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }

                // 現在のページ（めくられる）
                if let currentImage = currentImage {
                    PageTurnLayer(
                        image: currentImage,
                        progress: animationProgress,
                        direction: direction,
                        size: geometry.size
                    )
                }
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                startAnimation()
            }
        }
    }

    private func startAnimation() {
        let duration = PageTurnSettings.shared.animationSpeed

        withAnimation(.easeInOut(duration: duration)) {
            animationProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isAnimating = false
            animationProgress = 0
            onAnimationComplete?()
        }
    }
}

// MARK: - Page Turn Direction

enum PageTurnDirection {
    case left   // 左へめくる（次のページへ）
    case right  // 右へめくる（前のページへ）
}

// MARK: - Page Turn Layer (UIKit)

struct PageTurnLayer: UIViewRepresentable {
    let image: UIImage
    let progress: CGFloat
    let direction: PageTurnDirection
    let size: CGSize

    func makeUIView(context: Context) -> PageTurnView {
        let view = PageTurnView()
        view.image = image
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PageTurnView, context: Context) {
        uiView.image = image
        uiView.progress = progress
        uiView.direction = direction
        uiView.setNeedsDisplay()
    }
}

class PageTurnView: UIView {
    var image: UIImage?
    var progress: CGFloat = 0
    var direction: PageTurnDirection = .left

    override func draw(_ rect: CGRect) {
        guard let image = image, let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()

        // ページめくりの3D効果を計算
        let angle = progress * .pi / 2  // 0 to 90 degrees
        let perspective: CGFloat = -1.0 / 500.0

        var transform = CATransform3DIdentity
        transform.m34 = perspective

        switch direction {
        case .left:
            // 左へめくる（右端を軸に回転）
            transform = CATransform3DRotate(transform, -angle, 0, 1, 0)
            context.translateBy(x: rect.width, y: 0)
            context.scaleBy(x: -1, y: 1)

        case .right:
            // 右へめくる（左端を軸に回転）
            transform = CATransform3DRotate(transform, angle, 0, 1, 0)
        }

        // 影の効果
        let shadowAlpha = progress * 0.5
        context.setShadow(offset: CGSize(width: direction == .left ? -10 : 10, height: 0),
                          blur: 20,
                          color: UIColor.black.withAlphaComponent(shadowAlpha).cgColor)

        // 画像を描画（変換適用）
        let visibleWidth = rect.width * (1 - progress * 0.5)
        let drawRect = CGRect(x: 0, y: 0, width: visibleWidth, height: rect.height)

        // クリッピング
        context.clip(to: drawRect)

        // 画像を描画
        image.draw(in: rect)

        context.restoreGState()

        // ページの端のカール効果
        drawCurlEffect(in: rect, context: context)
    }

    private func drawCurlEffect(in rect: CGRect, context: CGContext) {
        guard progress > 0.1 else { return }

        let curlWidth: CGFloat = 30 * progress
        let curlX: CGFloat

        switch direction {
        case .left:
            curlX = rect.width * (1 - progress)
        case .right:
            curlX = rect.width * progress - curlWidth
        }

        // グラデーションでカール効果を表現
        let colors = [
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor
        ]
        let locations: [CGFloat] = [0, 1]

        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: locations) else { return }

        let startPoint = CGPoint(x: curlX, y: 0)
        let endPoint = CGPoint(x: curlX + curlWidth, y: 0)

        context.saveGState()
        context.clip(to: CGRect(x: curlX, y: 0, width: curlWidth, height: rect.height))
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        context.restoreGState()
    }
}

// MARK: - Page Turn Modifier

struct PageTurnModifier: ViewModifier {
    @ObservedObject var settings = PageTurnSettings.shared
    @Binding var isAnimating: Bool
    let currentImage: UIImage?
    let nextImage: UIImage?
    let direction: PageTurnDirection
    var onComplete: (() -> Void)?

    func body(content: Content) -> some View {
        ZStack {
            content

            if settings.isPageTurnAnimationEnabled && isAnimating {
                PageTurnAnimationView(
                    currentImage: currentImage,
                    nextImage: nextImage,
                    direction: direction,
                    isAnimating: $isAnimating,
                    onAnimationComplete: onComplete
                )
                .allowsHitTesting(false)  // アニメーション中もタッチを透過
            }
        }
    }
}

extension View {
    func pageTurnAnimation(
        isAnimating: Binding<Bool>,
        currentImage: UIImage?,
        nextImage: UIImage?,
        direction: PageTurnDirection,
        onComplete: (() -> Void)? = nil
    ) -> some View {
        modifier(PageTurnModifier(
            isAnimating: isAnimating,
            currentImage: currentImage,
            nextImage: nextImage,
            direction: direction,
            onComplete: onComplete
        ))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("Page Turn Animation Test")

        Button("Test Animation") {
            // Test animation
        }
    }
}

import SwiftUI
import Combine

/// マーカー入力方法の設定を管理するシングルトン
class InputMethodSettings: ObservableObject {
    static let shared = InputMethodSettings()

    /// 入力方法の種類
    enum InputMethod: String, CaseIterable {
        case finger = "finger"
        case pencil = "pencil"

        var displayName: String {
            switch self {
            case .finger:
                return DeviceHelper.isMac ? "マウス / トラックパッド" : "指"
            case .pencil:
                return "Apple Pencil"
            }
        }

        var description: String {
            switch self {
            case .finger:
                return DeviceHelper.isMac
                    ? "マウスやトラックパッドでドラッグしてマーカーを引けます"
                    : "画面を指でなぞってマーカーを引けます"
            case .pencil:
                return "Apple Pencilでのみマーカーを引けます"
            }
        }

        /// Macで利用可能な入力方法のみ返す
        static var availableCases: [InputMethod] {
            if DeviceHelper.isMac {
                return [.finger]  // Macでは指（マウス）モードのみ
            }
            return allCases
        }
    }

    @Published var inputMethod: InputMethod {
        didSet {
            UserDefaults.standard.set(inputMethod.rawValue, forKey: "markerInputMethod")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "markerInputMethod") ?? "finger"
        let method = InputMethod(rawValue: saved) ?? .finger
        // Macではpencilモードが使えないのでfingerにフォールバック
        if DeviceHelper.isMac && method == .pencil {
            self.inputMethod = .finger
        } else {
            self.inputMethod = method
        }
    }
}

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
                return "指"
            case .pencil:
                return "Apple Pencil"
            }
        }

        var description: String {
            switch self {
            case .finger:
                return "画面を指でなぞってマーカーを引けます"
            case .pencil:
                return "Apple Pencilでのみマーカーを引けます"
            }
        }
    }

    @Published var inputMethod: InputMethod {
        didSet {
            UserDefaults.standard.set(inputMethod.rawValue, forKey: "markerInputMethod")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "markerInputMethod") ?? "finger"
        self.inputMethod = InputMethod(rawValue: saved) ?? .finger
    }
}

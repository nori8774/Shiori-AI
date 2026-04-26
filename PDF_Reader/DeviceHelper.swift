import UIKit

/// デバイス判定ユーティリティ
struct DeviceHelper {
    /// iPhone かどうか
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// iPad かどうか
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

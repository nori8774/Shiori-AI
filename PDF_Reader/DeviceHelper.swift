import UIKit

/// デバイス判定ユーティリティ
struct DeviceHelper {
    /// Mac Catalyst で動作しているかどうか
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// iPhone かどうか
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// iPad かどうか（Mac Catalystは含まない）
    static var isPad: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    /// iPad または Mac かどうか（大画面デバイス判定用）
    static var isPadOrMac: Bool {
        isPad || isMac
    }
}

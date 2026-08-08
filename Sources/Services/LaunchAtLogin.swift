import Foundation
#if os(macOS)
import ServiceManagement
#endif

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            #if os(macOS)
            return SMAppService.mainApp.status == .enabled
            #else
            return false
            #endif
        }
        set {
            #if os(macOS)
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignore — user can toggle again
            }
            #endif
        }
    }
}

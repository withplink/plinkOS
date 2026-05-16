import UIKit

enum HapticStyle {
    case soft     // light impact, single
    case warning  // medium impact, single
    case error    // notification error (feels like 3-pulse)
}

func haptic(_ style: HapticStyle) {
    switch style {
    case .soft:
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    case .warning:
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .error:
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

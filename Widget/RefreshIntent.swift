// The ⟳ button in the limits widget. The widget can't fetch (it's sandboxed and has no tokens),
// so it asks the menu bar app to refresh via a Darwin notification, waits for a newer snapshot,
// and returns. WidgetKit always reloads the widget after an intent runs, so the new numbers show up
// right away, regardless of the background reload budget.
import AppIntents
import Foundation

let refreshNotification = "com.pavelershov.agentmonitor.refresh"

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Agent Limits"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let before = SharedStore.load()?.updated ?? .distantPast
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(refreshNotification as CFString), nil, nil, true)
        for _ in 0..<20 {   // up to ~5 s
            try? await Task.sleep(nanoseconds: 250_000_000)
            if (SharedStore.load()?.updated ?? .distantPast) > before { break }
        }
        return .result()
    }
}

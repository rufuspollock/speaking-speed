// Posts "How did that feel?" after each conversation, with Calm / OK / Rushed
// buttons. Needs the app bundle (scripts/install.sh); from `swift run` it no-ops
// and the rating is only available in the menu.
import Foundation
import SpeakingSpeedCore
import UserNotifications

@MainActor
final class ConversationNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "conversation"
    private let onRating: @MainActor (UUID, Rating) -> Void
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(onRating: @escaping @MainActor (UUID, Rating) -> Void) {
        self.onRating = onRating
        super.init()
        guard let center else { return }
        center.delegate = self
        let actions = Rating.allCases.map {
            UNNotificationAction(identifier: $0.rawValue, title: $0.rawValue.capitalized, options: [])
        }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ s: ConversationSummary, text: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "How did that feel?"
        content.body = text
        content.categoryIdentifier = Self.category
        content.userInfo = ["id": s.id.uuidString]
        center.add(UNNotificationRequest(identifier: s.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let rating = Rating(rawValue: response.actionIdentifier),
              let idString = response.notification.request.content.userInfo["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run { onRating(id, rating) }
    }
}

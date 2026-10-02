import Foundation
import QueepCore
import UserNotifications

/// Local reminder that a social feed is more useful when the interesting bits are saved in Queep.
/// The real 10-minute social-app threshold needs Family Controls later. This DEBUG path only
/// schedules a short delay so the banner can be tested without that entitlement.
@MainActor
enum FeedNotice {
    static let identifier = "library.testFeedNotice"
    static let title = "Rolar o feed só é produtivo usando o Queep."
    static let body = "Salve as coisas interessantes que acabou de ver"

    private static var scheduledThisLaunch = false

    static func eligible(isLocal: Bool, access: SubscriptionAccess?) -> Bool {
        if let access, !access.isDevelopment, access.plan != .free { return false }
        if isLocal || access?.isDevelopment == true { return true }
        return access?.plan == .free
    }

    /// Once per launch, about 12 seconds after the library appears.
    static func scheduleAfterLibraryAppears(isLocal: Bool, access: SubscriptionAccess?) {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        guard !scheduledThisLaunch else { return }
        guard eligible(isLocal: isLocal, access: access) else { return }
        scheduledThisLaunch = true
        Task { await deliver(after: 12) }
        #endif
    }

    /// Settings row. Requests permission when needed and shows the same notice in a few seconds.
    static func scheduleFromSettings(isLocal: Bool, access: SubscriptionAccess?) {
        #if DEBUG
        guard eligible(isLocal: isLocal, access: access) else { return }
        Task { await deliver(after: 4) }
        #endif
    }

    private static func deliver(after seconds: TimeInterval) async {
        let center = UNUserNotificationCenter.current()
        center.delegate = FeedNoticePresenter.shared
        let settings = await center.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            allowed = true
        case .notDetermined:
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            allowed = false
        @unknown default:
            allowed = false
        }
        guard allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(request)
    }
}

final class FeedNoticePresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = FeedNoticePresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Notification Service Extension — lets iOS attach rich-media images to a push
/// while the app is backgrounded or killed. Firebase's helper does the download
/// and content mutation.
final class NotificationService: UNNotificationServiceExtension {
    private var delivery: ((UNNotificationContent) -> Void)?
    private var mutableContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        delivery = contentHandler
        mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let mutableContent else {
            contentHandler(request.content)
            return
        }

        #if canImport(FirebaseMessaging)
        Messaging.serviceExtension().populateNotificationContent(
            mutableContent,
            withContentHandler: contentHandler
        )
        #else
        contentHandler(mutableContent)
        #endif
    }

    override func serviceExtensionTimeWillExpire() {
        guard let delivery, let mutableContent else { return }
        delivery(mutableContent)
    }
}

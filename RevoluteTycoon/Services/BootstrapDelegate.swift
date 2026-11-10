import UIKit

/// Minimal UIKit delegate bridged into the SwiftUI app. Two jobs: wire the
/// launch runtime up before the first frame, and gate orientation globally so
/// the native game stays portrait while the gray-flow screens (loading,
/// no-wifi, push promo, web lane) are free to rotate with the device.
final class BootstrapDelegate: NSObject, UIApplicationDelegate {

    /// Updated by `LaunchModel` on every phase change — UIKit reads it back
    /// via `application(_:supportedInterfaceOrientationsFor:)`. Written and
    /// read exclusively on the main thread, so no concurrency isolation is
    /// needed (and no `nonisolated(unsafe)` noise either).
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Wire everything up before the first scene connects so the notification
        // delegate is already in place for a cold-start push tap.
        LaunchModel.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            LaunchModel.shared.captureColdPush(remote)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        LaunchModel.shared.setApnsToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        debugTrace("apns register failed \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    /// Publishes a new orientation lock and asks UIKit to re-query it right
    /// now — the native game lock must engage the instant we transition out of
    /// the gray flow, not on the next spontaneous rotation.
    @MainActor
    static func applyOrientation(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        if #available(iOS 16, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
        scene.windows
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

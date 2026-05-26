import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    enum PermissionState {
        case notDetermined
        case allowed
        case denied

        var label: String {
            switch self {
            case .notDetermined: return "아직 허용하지 않음"
            case .allowed: return "Mac 알림 허용됨"
            case .denied: return "시스템 설정에서 차단됨"
            }
        }
    }

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func permissionState() async -> PermissionState {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestPermission() async throws -> PermissionState {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await permissionState()
    }

    func sendCompletionNotification(for result: AnalysisResult) async {
        guard await permissionState() == .allowed else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        if result.reports.isEmpty {
            content.title = "CRT 0.2 분석 완료"
            content.body = "\(result.date) 기준에 맞는 급변 후보가 발견되지 않았습니다."
        } else {
            let symbols = result.reports.prefix(3).map(\.symbol).joined(separator: ", ")
            content.title = "CRT 0.2 급변 후보 \(result.reports.count)건"
            content.body = "\(result.date) 분석: \(symbols) 후보를 확인하세요."
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - NotificationService.swift
// CViewApp - 로컬 알림 서비스 (스트리머 온라인 알림)

import Foundation
import UserNotifications
import AppKit
import CViewCore

/// 로컬 알림 관리 서비스
@MainActor
final class NotificationService: NSObject {

    static let shared = NotificationService()

    private var isAuthorized = false
    private let logger = AppLogger.app
    
    /// 알림 클릭 시 채널ID 전달 콜백
    var onWatchChannel: ((String) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// 알림 권한 요청
    func requestAuthorization() async {
        // LaunchServices 재등록 — 알림 아이콘 캐시 강제 갱신
        refreshLaunchServicesRegistration()

        do {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            logger.info("Notification authorization: \(granted)")
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    /// LaunchServices에 앱 번들을 강제 재등록하여 알림 아이콘 캐시 갱신
    private func refreshLaunchServicesRegistration() {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard FileManager.default.fileExists(atPath: lsregister) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsregister)
        process.arguments = ["-f", Bundle.main.bundlePath]
        try? process.run()
        process.waitUntilExit()
    }

    /// 현재 알림 권한 상태 확인
    func checkAuthorizationStatus() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        return isAuthorized
    }

    // MARK: - Notifications

    /// 스트리머 온라인 알림 발송
    func notifyStreamerOnline(_ channels: [OnlineChannel]) {
        guard isAuthorized else { return }

        let iconAttachment = makeIconAttachment()

        for channel in channels {
            let content = UNMutableNotificationContent()
            content.title = "\(channel.channelName) 방송 시작!"
            content.body = channel.liveTitle.isEmpty
                ? "\(channel.channelName)님이 방송을 시작했습니다."
                : channel.liveTitle
            content.sound = .default
            content.categoryIdentifier = "STREAMER_ONLINE"
            content.userInfo = [
                "channelId": channel.channelId,
                "channelName": channel.channelName
            ]
            if let iconAttachment {
                content.attachments = [iconAttachment]
            }

            let request = UNNotificationRequest(
                identifier: "online-\(channel.channelId)-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    AppLogger.app.error("Failed to send notification: \(error.localizedDescription)")
                }
            }
        }

        logger.info("Sent \(channels.count) online notifications")
    }

    /// 앱 아이콘을 임시 파일로 저장해 UNNotificationAttachment 생성
    private func makeIconAttachment() -> UNNotificationAttachment? {
        guard let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: icnsURL) else { return nil }

        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cview_notif_icon_\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1").png")

        if !FileManager.default.fileExists(atPath: tmpURL.path) {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
            try? png.write(to: tmpURL)
        }

        return try? UNNotificationAttachment(
            identifier: "app-icon",
            url: tmpURL,
            options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
        )
    }

    /// 모든 예약된 알림 취소
    func cancelAllPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// 알림 카테고리 등록 (액션 버튼)
    func registerCategories() {
        let watchAction = UNNotificationAction(
            identifier: "WATCH_ACTION",
            title: "시청하기",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "닫기",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "STREAMER_ONLINE",
            actions: [watchAction, dismissAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        
        guard action == "WATCH_ACTION" || action == UNNotificationDefaultActionIdentifier,
              let channelId = userInfo["channelId"] as? String else { return }
        
        await MainActor.run {
            onWatchChannel?(channelId)
        }
    }
}

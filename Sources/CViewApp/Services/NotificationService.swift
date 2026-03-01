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
    
    /// 앱 아이콘 PNG 데이터 캐시 (매번 이미지 변환 방지)
    private var cachedIconPNG: Data?
    
    /// 알림 클릭 시 채널ID 전달 콜백
    var onWatchChannel: ((String) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Safe UNUserNotificationCenter Access

    /// 앱 번들이 올바르게 설정된 경우에만 UNUserNotificationCenter를 반환.
    /// `swift build` 바이너리처럼 .app 번들이 아닌 환경에서는 nil을 반환하여 크래시 방지.
    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    // MARK: - Authorization

    /// 알림 권한 요청
    func requestAuthorization() async {
        guard let center = notificationCenter else {
            logger.warning("Notifications unavailable — no app bundle (swift build binary?)")
            return
        }

        // LaunchServices 재등록 — 알림 아이콘 캐시 강제 갱신
        refreshLaunchServicesRegistration()

        do {
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
        let bundlePath = Bundle.main.bundlePath
        // @MainActor 블로킹 방지: 비동기로 프로세스 실행
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsregister)
            process.arguments = ["-f", bundlePath]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// 현재 알림 권한 상태 확인
    func checkAuthorizationStatus() async -> Bool {
        guard let center = notificationCenter else { return false }
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        return isAuthorized
    }

    // MARK: - Notifications

    /// 스트리머 온라인 알림 발송
    func notifyStreamerOnline(_ channels: [OnlineChannel]) {
        guard isAuthorized else { return }

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
            if let attachment = makeIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: "online-\(channel.channelId)-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            notificationCenter?.add(request) { error in
                if let error {
                    AppLogger.app.error("Failed to send notification: \(error.localizedDescription)")
                }
            }
        }

        logger.info("Sent \(channels.count) online notifications")
    }

    /// 카테고리 변경 알림 발송
    func notifyCategoryChange(_ changes: [ChannelChangeInfo]) {
        guard isAuthorized else { return }

        for change in changes {
            let content = UNMutableNotificationContent()
            content.title = "\(change.channelName) 카테고리 변경"
            content.body = "\(change.oldValue) → \(change.newValue)"
            content.sound = .default
            content.categoryIdentifier = "STREAMER_ONLINE"
            content.userInfo = [
                "channelId": change.channelId,
                "channelName": change.channelName
            ]
            if let attachment = makeIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: "category-\(change.channelId)-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            notificationCenter?.add(request) { error in
                if let error {
                    AppLogger.app.error("Failed to send category notification: \(error.localizedDescription)")
                }
            }
        }

        logger.info("Sent \(changes.count) category change notifications")
    }

    /// 제목 변경 알림 발송
    func notifyTitleChange(_ changes: [ChannelChangeInfo]) {
        guard isAuthorized else { return }

        for change in changes {
            let content = UNMutableNotificationContent()
            content.title = "\(change.channelName) 방송 제목 변경"
            content.body = change.newValue
            content.sound = .default
            content.categoryIdentifier = "STREAMER_ONLINE"
            content.userInfo = [
                "channelId": change.channelId,
                "channelName": change.channelName
            ]
            if let attachment = makeIconAttachment() {
                content.attachments = [attachment]
            }

            let request = UNNotificationRequest(
                identifier: "title-\(change.channelId)-\(Date.now.timeIntervalSince1970)",
                content: content,
                trigger: nil
            )

            notificationCenter?.add(request) { error in
                if let error {
                    AppLogger.app.error("Failed to send title notification: \(error.localizedDescription)")
                }
            }
        }

        logger.info("Sent \(changes.count) title change notifications")
    }

    /// 앱 아이콘을 임시 파일로 저장해 UNNotificationAttachment 생성
    /// - Note: UNNotificationAttachment는 파일을 data store로 **이동**시키므로,
    ///   매 호출마다 고유한 임시 파일을 생성해야 합니다.
    private func makeIconAttachment() -> UNNotificationAttachment? {
        // 1) PNG 데이터 캐시 (이미지 변환은 한 번만)
        if cachedIconPNG == nil {
            guard let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: icnsURL),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
            cachedIconPNG = png
        }

        guard let png = cachedIconPNG else { return nil }

        // 2) 매 Attachment마다 고유 파일 생성 (시스템이 파일을 이동시키기 때문)
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cview_notif_icon_\(UUID().uuidString).png")

        do {
            try png.write(to: tmpURL)
        } catch {
            logger.error("Failed to write notification icon: \(error.localizedDescription)")
            return nil
        }

        return try? UNNotificationAttachment(
            identifier: "app-icon",
            url: tmpURL,
            options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
        )
    }

    /// 모든 예약된 알림 취소
    func cancelAllPending() {
        notificationCenter?.removeAllPendingNotificationRequests()
    }

    /// 알림 카테고리 등록 (액션 버튼)
    func registerCategories() {
        guard let center = notificationCenter else { return }

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

        center.setNotificationCategories([category])
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

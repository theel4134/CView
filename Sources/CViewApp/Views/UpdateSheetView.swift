// MARK: - UpdateSheetView.swift
// CViewApp - 자동 업데이트 다이얼로그

import SwiftUI
import CViewCore
import CViewUI

struct UpdateSheetView: View {
    @Bindable var service: UpdateService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header

            Divider()

            content

            Spacer(minLength: 0)

            footer
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 48, height: 48)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 18, weight: .semibold))
                Text("현재 버전 \(service.currentVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var iconName: String {
        switch service.status {
        case .idle, .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.seal.fill"
        case .updateAvailable: return "arrow.down.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .readyToInstall, .installing: return "gearshape.2.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch service.status {
        case .upToDate: return .green
        case .updateAvailable, .downloading, .readyToInstall, .installing: return .accentColor
        case .error: return .orange
        default: return .secondary
        }
    }

    private var titleText: String {
        switch service.status {
        case .idle: return "CView 업데이트"
        case .checking: return "업데이트 확인 중…"
        case .upToDate: return "최신 버전을 사용 중입니다"
        case .updateAvailable(let r): return "새 버전 \(r.versionString) 사용 가능"
        case .downloading: return "다운로드 중…"
        case .readyToInstall, .installing: return "설치 중…"
        case .error: return "업데이트 오류"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch service.status {
        case .idle:
            Text("업데이트 확인 버튼을 눌러 새 버전을 조회하세요.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

        case .checking:
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("GitHub 릴리스 확인 중…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            VStack(alignment: .leading, spacing: 8) {
                Text("설치된 버전이 GitHub 최신 릴리스와 동일합니다.")
                    .font(.system(size: 13))
                if let checked = service.lastCheckedAt {
                    Text("마지막 확인: \(checked.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

        case .updateAvailable(let release):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                if let asset = release.preferredAsset {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.zipper")
                            .foregroundStyle(.secondary)
                        Text(asset.name)
                            .font(.system(size: 12).monospaced())
                        Text("(\(formatBytes(asset.size)))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if let body = release.body, !body.isEmpty {
                    Text("릴리스 노트")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(body)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(DesignTokens.Spacing.sm)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress) {
                    Text("다운로드 \(Int(progress * 100))%")
                        .font(.system(size: 12))
                }
                Text("네트워크 속도에 따라 1~3분 소요될 수 있습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall, .installing:
            HStack(spacing: DesignTokens.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("앱을 교체하고 재실행하는 중입니다. 자동으로 새 버전이 실행됩니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

        case .error(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if case .updateAvailable(let r) = service.status, let url = r.htmlURL {
                Link("릴리스 페이지", destination: url)
                    .font(.system(size: 12))
            }

            Spacer()

            switch service.status {
            case .idle:
                Button("닫기") { dismiss() }
                Button("업데이트 확인") {
                    Task { await service.checkForUpdates() }
                }
                .keyboardShortcut(.defaultAction)

            case .checking, .downloading, .installing, .readyToInstall:
                Button("닫기") { dismiss() }
                    .disabled(true)

            case .upToDate:
                Button("확인 반복") {
                    Task { await service.checkForUpdates() }
                }
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.defaultAction)

            case .updateAvailable:
                Button("나중에") { dismiss() }
                Button("지금 업데이트") {
                    Task { await service.downloadAndInstall() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

            case .error:
                Button("닫기") {
                    service.dismissError()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func formatBytes(_ size: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(size))
    }
}

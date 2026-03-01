// MARK: - MultiLiveView.swift
// CViewApp — 멀티라이브 메인 뷰
// AVPlayer 기반 최대 4채널 동시 시청

import SwiftUI
import CViewCore
import CViewPlayer

struct MultiLiveView: View {

    @Environment(AppState.self) private var appState

    private var manager: MultiLiveManager {
        appState.multiLiveManager
    }

    var body: some View {
        ZStack {
            if manager.sessions.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    // 메인 플레이어 영역
                    if manager.isGridLayout {
                        gridLayout
                    } else {
                        tabLayout
                    }

                    // 하단 탭바
                    MultiLiveTabBar(manager: manager)
                }
            }
        }
        .background(DesignTokens.Colors.background)
        .sheet(isPresented: Binding(
            get: { manager.showAddSheet },
            set: { manager.showAddSheet = $0 }
        )) {
            MultiLiveAddSheet(manager: manager)
        }
        .toolbar {
            toolbarContent
        }
        .onDisappear {
            // 멀티라이브 뷰를 떠날 때 세션은 유지 (백그라운드 재생)
        }
    }

    // MARK: - 탭 레이아웃 (선택 세션 전체 화면)

    @ViewBuilder
    private var tabLayout: some View {
        if let selected = manager.selectedSession {
            MultiLivePlayerPane(session: selected, isSelected: true, isCompact: false)
                .id(selected.id)
        }
    }

    // MARK: - 그리드 레이아웃 (2x2)

    private var gridLayout: some View {
        GeometryReader { geo in
            let cols = manager.sessions.count <= 2 ? manager.sessions.count : 2
            let rows = manager.sessions.count <= 2 ? 1 : 2
            let cellWidth = geo.size.width / CGFloat(cols)
            let cellHeight = geo.size.height / CGFloat(rows)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: cols),
                spacing: 2
            ) {
                ForEach(manager.sessions) { session in
                    MultiLivePlayerPane(
                        session: session,
                        isSelected: session.id == manager.selectedSessionId,
                        isCompact: true
                    )
                    .frame(height: cellHeight - 1)
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.normal) {
                            manager.selectSession(id: session.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 빈 상태

    private var emptyStateView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DesignTokens.Colors.textTertiary)

            Text("멀티라이브")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Text("최대 4개 채널을 동시에 시청할 수 있습니다")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Button {
                manager.showAddSheet = true
            } label: {
                Label("채널 추가", systemImage: "plus.circle.fill")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.chzzkGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if !manager.sessions.isEmpty {
                Button {
                    withAnimation(DesignTokens.Animation.normal) {
                        manager.isGridLayout.toggle()
                    }
                } label: {
                    Image(systemName: manager.isGridLayout ? "rectangle.split.1x2" : "rectangle.split.2x2")
                }
                .help(manager.isGridLayout ? "탭 모드" : "그리드 모드")
            }

            Button {
                manager.showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("채널 추가")
            .disabled(!manager.canAddSession)
        }
    }
}

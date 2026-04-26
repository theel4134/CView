// MARK: - HomeV2Layout.swift
// HomeView_v2 섹션 표시/순서/밀도 사용자 환경설정 (P2-1).
//
// 모든 토글은 @AppStorage 기반 — 앱 재시작에도 유지.
// HomeLayoutMenu 는 CommandBar 옆에 두는 편집 메뉴 UI.

import SwiftUI
import CViewCore

// MARK: - Density

enum HomeCardDensity: String, CaseIterable, Identifiable {
    case compact
    case comfortable
    case spacious
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact:     return "compact"
        case .comfortable: return "comfortable"
        case .spacious:    return "spacious"
        }
    }
    var koreanLabel: String {
        switch self {
        case .compact:     return "촘촘하게"
        case .comfortable: return "여유있게"
        case .spacious:    return "넓게"
        }
    }
}

// MARK: - Preferences Keys (참고용)
//
// HomeView_v2 가 직접 @AppStorage 로 다음 키들을 읽고 쓴다:
//   home.v2.show.hero / personalLive / continue / discover / top / insights / activeMulti
//   home.v2.density  ("compact" | "comfortable")
// HomeLayoutMenu 는 같은 키들의 토글 UI 를 노출.

// MARK: - Edit Menu

struct HomeLayoutMenu: View {
    @AppStorage("home.v2.show.hero")           private var showHero: Bool = true
    @AppStorage("home.v2.show.personalLive")   private var showPersonalLive: Bool = true
    @AppStorage("home.v2.show.continue")       private var showContinueWatching: Bool = true
    @AppStorage("home.v2.show.discover")       private var showDiscover: Bool = true
    @AppStorage("home.v2.show.top")            private var showTopChannels: Bool = true
    @AppStorage("home.v2.show.insights")       private var showInsights: Bool = true
    @AppStorage("home.v2.show.activeMulti")    private var showActiveMultiLive: Bool = true
    @AppStorage("home.v2.density")             private var densityRaw: String = HomeCardDensity.comfortable.rawValue

    var body: some View {
        Menu {
            Section("표시 섹션") {
                Toggle("대표 추천 (Hero)", isOn: $showHero)
                Toggle("팔로잉 라이브", isOn: $showPersonalLive)
                Toggle("이어보기 / 즐겨찾기", isOn: $showContinueWatching)
                Toggle("탐색 (Discover)", isOn: $showDiscover)
                Toggle("인기 채널", isOn: $showTopChannels)
                Toggle("요약 인사이트", isOn: $showInsights)
                Toggle("멀티라이브 strip", isOn: $showActiveMultiLive)
            }
            Section("카드 밀도") {
                Picker("밀도", selection: $densityRaw) {
                    ForEach(HomeCardDensity.allCases) { d in
                        Text(d.koreanLabel).tag(d.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            Section {
                Button("기본값 복원", role: .destructive) {
                    showHero = true
                    showPersonalLive = true
                    showContinueWatching = true
                    showDiscover = true
                    showTopChannels = true
                    showInsights = true
                    showActiveMultiLive = true
                    densityRaw = HomeCardDensity.comfortable.rawValue
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(DesignTokens.Glass.borderColor, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("홈 편집 (섹션 표시 / 카드 밀도)")
    }
}

# CView_v2 디자인 종합 분석 및 개선안

작성일: 2026-04-18
대상 버전: 2.0.0 (33)
범위: `Sources/CViewCore/DesignSystem/*`, `Sources/CViewUI/*`, `Sources/CViewApp/Views/**` (80+ View)

---

## 0. 한 눈에 보는 결론

CView_v2 의 디자인 시스템(`DesignTokens` v2 — Dark Glass)은 **토큰 정의 측면에서는 매우 성숙**합니다.
Spacing 10단계, Typography 16개 프리셋, 4-Layer Surface Stack, adaptive 그림자/보더, spring 위주 Animation, motion-safe 헬퍼까지 갖추고 있어 동급 macOS 앱 중 상위권입니다.

그러나 **실제 80여 개 View 가 토큰을 사용하는 일관도는 80% 수준**이며, 다음 4가지가 사용자 체감 품질을 가장 크게 떨어뜨리고 있습니다.

| # | 문제 | 영향 | 우선순위 |
|---|---|---|---|
| **A** | 라이트 모드에서 `.white.opacity(...)` 하드코딩 (40+ 위치) | 라이트 테마 가독성·대비 위반 (WCAG 미달) | 🔴 P0 |
| **B** | `EmptyState` / `ErrorState` / `LoadingSpinner` 가 7개+ 파일에 중복 구현 | 시각 톤 불일치, 유지보수 부담 | 🔴 P0 |
| **C** | Dynamic Type 미지원 (`Font.system(size:)` 고정) | 시스템 폰트 크기 변경·접근성 무대응 | 🟡 P1 |
| **D** | `padding(_, 6/7/9/12)` 등 8pt 그리드 위반 하드코딩 50+ 건 | 시각적 리듬 깨짐, 토큰 가치 희석 | 🟡 P1 |

이 문서는 위 4가지를 포함한 **10개 카테고리**의 현황과 개선 방안을 코드 레벨로 제안합니다.

---

## 1. 현재 디자인 시스템 자산

### 1.1 토큰 인벤토리 (DesignTokens v2)

| 카테고리 | 정의 위치 | 토큰 수 | 평가 |
|---|---|---|---|
| Spacing | [DesignTokens.swift L17-40](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L17-L40) | 10 (xxs~page) | ✅ 8pt 그리드 정합 |
| Typography | [DesignTokens.swift L46-90](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L46-L90) | 16 프리셋 + 3 mono | ⚠️ 모두 고정 size — Dynamic Type 미대응 |
| Colors | [DesignTokens.swift L94-145](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L94-L145) | 4-Layer Surface + Semantic 7색 | ✅ adaptive 헬퍼 잘 설계됨 |
| Glass | [DesignTokens.swift L172-210](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L172-L210) | thin/regular/thick + adaptive border | ✅ |
| Gradients | [DesignTokens.swift L213-290](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L213-L290) | 13 종 | ✅ |
| Radius | [DesignTokens.swift L293-310](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L293-L310) | 6 (xs~full) | ✅ |
| Shadow | [DesignTokens.swift L312-340](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L312-L340) | 8 종 (모두 adaptive) | ✅ Light/Dark 자동 대응 |
| Animation | [DesignTokens.swift L342-410](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L342-L410) | 20+ spring 프리셋 + `motionSafe()` | ✅ 매우 우수 |
| Layout | [DesignTokens.swift L413-430](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L413-L430) | 9 상수 | ✅ |
| Border / Opacity | [DesignTokens.swift L432-460](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L432-L460) | thin/medium/thick + 6단계 | ✅ |

### 1.2 공용 ViewModifier / Style

| 자산 | 위치 | 활용도 |
|---|---|---|
| `.glassCard()` | [DesignTokens+Modifiers.swift L11-46](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L11-L46) | 중간 |
| `.surfaceCard()` | [DesignTokens+Modifiers.swift L52-83](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L52-L83) | 높음 |
| `.hoverCard()` | [DesignTokens+Modifiers.swift L89-110](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L89-L110) | 중간 |
| `.glowBorder()` | [DesignTokens+Modifiers.swift L116-145](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L116-L145) | 낮음 |
| `PillButtonStyle` / `GhostPillButtonStyle` | [DesignTokens+Modifiers.swift L150-220](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L150-L220) | 높음 |
| `IconButtonStyle` / `HoverPillButtonStyle` | [DesignTokens.swift L495-570](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L495-L570) | 중간 |
| `SectionHeaderView` | [DesignTokens+Modifiers.swift L226-260](../Sources/CViewCore/DesignSystem/DesignTokens+Modifiers.swift#L226-L260) | 중간 |
| `CachedAsyncImage` | [CViewUI/CachedAsyncImage.swift](../Sources/CViewUI/CachedAsyncImage.swift) | 높음 |
| `TimelineSlider`, `EmoticonPickerView` | [CViewUI/](../Sources/CViewUI) | 도메인 특화 |

> CViewUI 모듈에는 5 개 파일 밖에 없습니다. Empty/Error/Loading/Badge/Avatar/StatusPill 같은 **재사용 가능한 General Components 가 비어 있다**는 것이 1차 문제입니다.

---

## 2. 화면별 디자인 패턴 진단

| 화면 | 컨테이너 | 카드 스타일 | 특이사항 |
|---|---|---|---|
| `HomeView` | ScrollView → LazyVStack(`xl`) | `.surfaceCard(fillColor: .surfaceElevated, border:false)` | 7개 섹션 단일 스크롤. 정보 밀도 우수 |
| `FollowingView` | ZStack + 4 모드 (목록/그리드/멀티라이브/멀티채팅) | adaptive 그라디언트 배경 + `drawingGroup()` | 페이징 영속 상태 — 좋은 UX |
| `MultiLiveView` | HStack + 슬라이딩 패널 | `MultiLiveGridLayouts` 비율 기반 분할 | zIndex/shadow 명시적 ✅ |
| `ChatPanelView` | VStack(0) | 솔리드 `surfaceBase` (Material 의도적 회피) | GPU 비용 회피 주석 존재 ✅ |
| `LiveStreamView` | HStack(0) + `onGeometryChange` | 정수 픽셀 스냅 | 리사이즈 최적화 우수 |
| `MultiChatView` | 3-mode (sidebar/grid/merged) | HSplitView | 자체 `emptyState` 4번 중복 ⚠️ |
| `SettingsView` | TabView 6-8 탭 | `SettingsSection` + `SettingRow` | 일관됨 ✅ |
| `MainContentView` | HSplitView | `MenuBarView.zIndex(10)` | 명확 ✅ |
| `PlayerControlsView` | ZStack 오버레이 | `.ultraThinMaterial` 직접 + `.white.opacity` 다수 | **라이트 모드 대비 미고려** 🔴 |

---

## 3. 핵심 문제 A — 라이트 모드 색상 일관성 (P0)

### 3.1 현황

`grep "\.white\.opacity"` 결과 **40+ 매칭**. 대표 사례:

| 파일 | 라인 | 패턴 | 문제 |
|---|---|---|---|
| [PlayerControlsView.swift](../Sources/CViewApp/Views/PlayerControlsView.swift) | L96, L127, L170, L259, L312, L396, L488, L583, L615, L665, L748 (총 14건) | `Color.white.opacity(0.06~0.28)` | 플레이어 위는 영상이지만 **음소거/볼륨 슬라이더 배경**은 라이트 모드 영상에서 흰색 배경 + 흰색 컨트롤 → 시인성 저하 |
| [StreamAlertOverlayView.swift L122,133,135](../Sources/CViewApp/Views/StreamAlertOverlayView.swift#L122) | `.white.opacity(0.85/0.5/0.1)` | 라이브 알림이 라이트 윈도우에 뜰 때 텍스트 대비 부족 |
| [StreamLoadingOverlay.swift L118,133](../Sources/CViewApp/Views/StreamLoadingOverlay.swift#L118) | `Color.white.opacity(0.85)` 텍스트 + `Color.black.opacity(0.62)` 베일 | 라이트에서 과도한 어둡힘 |
| [VODPlayerView.swift L59,172](../Sources/CViewApp/Views/VODPlayerView.swift#L59) | `.white.opacity(0.7~0.8)` | 비디오 메타 텍스트 |
| [CategoryBrowseView.swift L499,590](../Sources/CViewApp/Views/CategoryBrowseView.swift#L499) | `.white.opacity(0.72~0.78)` | 썸네일 위 텍스트 — 라이트 썸네일에서 안 보임 |
| [ChatMessageRow.swift L337-340](../Sources/CViewApp/Views/ChatMessageRow.swift#L337-L340) | `Color(hex: 0xC0C0C0/0xFFD700/0xB9F2FF)` | 후원 등급 배지 정적 색상 — Light/Dark 미대응 |

### 3.2 개선안

#### A-1. `DesignTokens.Colors` 에 "오버레이 전용" 어휘 추가

```swift
// DesignTokens.swift Colors 안에 추가
/// 어두운 미디어(영상/썸네일) 위 텍스트 — 항상 흰색 (어두운 매체 위에서만 사용)
public static let textOnDarkMedia       = Color.white
/// 어두운 미디어 위 보조 텍스트
public static let textOnDarkMediaMuted  = Color.white.opacity(0.72)
/// 어두운 미디어 위 컨트롤 표면 (음소거 토글 배경 등)
public static let controlOnDarkMedia    = Color.white.opacity(0.14)
public static let controlOnDarkMediaHover = Color.white.opacity(0.24)
public static let borderOnDarkMedia     = Color.white.opacity(0.12)

/// 적응형 베일 — 라이트 0.32 / 다크 0.62
public static let mediaVeil = adaptive(dark: 0x000000, light: 0x000000, alpha: 0.0)
    // 실제로는 별도 헬퍼: Color(nsColor: NSColor(name:nil) { isDark ? .black 0.62 : .black 0.32 })
```

그 다음 다음 룰을 코드 리뷰에 적용:

- **영상/썸네일 위에서만** `.white.opacity(...)` 사용 (`textOnDarkMedia*`, `controlOnDarkMedia*` 어휘로 치환)
- **그 외 모든 표면**(헤더, 카드, 채팅 등)에서는 `DesignTokens.Colors.textPrimary/Secondary/Tertiary` 만 사용
- 후원 등급 등 시맨틱 색상은 `adaptive(dark:, light:)` 로 재정의

#### A-2. 1차 적용 대상 (PR 단위 권장 분리)

1. `PlayerControlsView.swift` — 14곳 → `controlOnDarkMedia*` 토큰 치환
2. `StreamLoadingOverlay.swift` — 베일/텍스트 adaptive 화
3. `StreamAlertOverlayView.swift` — 알림 카드 라이트 모드 변형 추가
4. `ChatMessageRow.swift` 후원 등급 배지 — adaptive 팔레트로 정의

#### A-3. 회귀 방지 (lint)

`scripts/check-design-tokens.sh` (신규) 로 다음 패턴 정규식 체크:
- `\.white\.opacity\(` (영상/썸네일 모듈 화이트리스트 외 금지)
- `Color\(hex:` (DesignTokens 모듈 외부 사용 금지)

빌드 단계 또는 pre-commit 훅에 연결.

---

## 4. 핵심 문제 B — 컴포넌트 중복 (P0)

### 4.1 현황 — `EmptyState` 중복 8개

| 위치 | 구현 | 상태 |
|---|---|---|
| [EmoticonPickerView.swift L201](../Sources/CViewUI/EmoticonPickerView.swift#L201) | `private func emptyState(text:sub:)` | private |
| [ErrorRecoveryView.swift L235](../Sources/CViewApp/Views/ErrorRecoveryView.swift#L235) | `struct EmptyStateView` | 유일한 글로벌 후보 |
| [MultiLiveOverlays.swift L270](../Sources/CViewApp/Views/MultiLiveOverlays.swift#L270) | `struct MLEmptyState` | 도메인 특화 |
| [FollowingView+MultiChat.swift L110](../Sources/CViewApp/Views/FollowingView+MultiChat.swift#L110) | `var chatEmptyState` | 인라인 |
| [MultiChatView.swift L483](../Sources/CViewApp/Views/MultiChatView.swift#L483) | `private var emptyState` (4회 호출) | 인라인 |
| [RecentFavoritesView.swift L232](../Sources/CViewApp/Views/RecentFavoritesView.swift#L232) | `func emptyState(icon:message:)` | private |
| [CommandPaletteView.swift L351](../Sources/CViewApp/Views/CommandPaletteView.swift#L351) | `private var emptyState` | 인라인 |
| [CategoryBrowseView.swift L411](../Sources/CViewApp/Views/CategoryBrowseView.swift#L411) | `private func emptyState(_:)` | private |
| [ChannelVODClipTab.swift L116](../Sources/CViewApp/Views/ChannelVODClipTab.swift#L116) | `struct ChannelInfoEmptyState` | 도메인 특화 |
| [MergedChatView.swift L114](../Sources/CViewApp/Views/MergedChatView.swift#L114) | `var mergedEmptyState` | 인라인 |

### 4.2 개선안 — `CViewUI` 에 4개의 표준 컴포넌트 신설

```swift
// 신규 파일: Sources/CViewUI/Components/EmptyStateView.swift
public struct EmptyStateView: View {
    public enum Style { case page, panel, inline }
    let icon: String           // SF Symbol
    let title: String
    let message: String?
    let action: (label: String, perform: () -> Void)?
    let style: Style
    // ...
}

// Sources/CViewUI/Components/ErrorStateView.swift  (현재 ErrorStateView.swift 를 모듈로 승격)
public struct ErrorStateView: View {
    let error: Error?  // 또는 String
    let retry: (() -> Void)?
    let style: EmptyStateView.Style
}

// Sources/CViewUI/Components/LoadingIndicator.swift
public struct LoadingIndicator: View {
    public enum Size { case small, medium, large }
    let size: Size
    let message: String?
    let useGlassBackground: Bool   // 영상 위 등
}

// Sources/CViewUI/Components/StatusPill.swift  (연결 상태/라이브 상태 통합)
public struct StatusPill: View {
    public enum Status { case live, connected, connecting, disconnected, error, custom(Color, String) }
}
```

### 4.3 마이그레이션 순서

1. `CViewUI/Components/` 디렉터리 신설 + 위 4개 파일 추가
2. 글로벌 `find_referencing_symbols` → `EmptyStateView`, `ChannelInfoEmptyState`, `MLEmptyState`, `mergedEmptyState`, `chatEmptyState` 등을 표준 컴포넌트로 일괄 치환
3. 도메인 특화가 정말 필요한 경우만 표준 컴포넌트 위에 thin wrapper 유지 (`MLEmptyState` → `EmptyStateView` + "채널 추가" action)
4. 회귀 방지: `grep "private (var|func) emptyState"` 0건 유지를 PR 체크에 추가

### 4.4 추가 추출 대상

- **Badge** — 라이브 / 시청자 수 / 카테고리 / 후원 등급 (현재 4 곳 이상에서 별개 구현)
- **Avatar** — `Layout.offlineAvatarSize`/`liveAvatarSize` 두 가지 케이스 + 실시간 LIVE 링 효과
- **SkeletonRow / SkeletonCard** — `SharedEffects.swift` 의 shimmer를 컴포넌트화 (현재 HomeView/FollowingView에서만 사용)

---

## 5. 핵심 문제 C — Dynamic Type & 접근성 (P1)

### 5.1 현황

- 모든 폰트가 `Font.system(size: CGFloat, weight: .x)` 로 **고정 사이즈**.
  - 시스템 설정의 "텍스트 크기" 변경 영향 없음
  - `.dynamicTypeSize`, `.scaledMetric` 미사용
- `.accessibilityLabel/.accessibilityValue` 는 **PlayerControlsView 위주로만** 잘 적용됨 (좋은 출발점)
- 채팅 메시지/배지/메뉴바/홈 카드/통계 차트에는 거의 미적용
- `motionSafe()` 헬퍼는 잘 사용 중 (StreamLoadingOverlay 등). 다만 일부 `.linear/.easeInOut` 하드코딩 존재 (HomeView+Dashboard, MultiLiveAddSheet+Following, PlayerControlsView)

### 5.2 개선안 — 단계적 Dynamic Type 도입

#### C-1. Typography 토큰을 "텍스트 스타일 매핑" 으로 보강 (점진적)

```swift
// Typography 안에 추가
/// macOS 시스템 텍스트 스타일 매핑 (Dynamic Type 대응)
/// 기존 size 기반 토큰과 공존, 신규 코드부터 점진 채택
public static let bodyDynamic     = Font.body          // ~17pt 기본
public static let calloutDynamic  = Font.callout
public static let captionDynamic  = Font.caption
public static let headlineDynamic = Font.headline
public static let title3Dynamic   = Font.title3
```

> macOS 14+ 부터 `Font.body` 등이 Dynamic Type 와 잘 동작. 채팅/긴 텍스트/접근성 민감 영역 우선 적용.

#### C-2. 우선 적용 영역

| 영역 | 사유 |
|---|---|
| `ChatMessageRow` | 텍스트 가독성 — 사용자가 가장 길게 보는 영역 |
| `SettingsView` 의 `SettingRow` | 라벨/설명 |
| `EmptyStateView`, `ErrorStateView` (신규 컴포넌트) | 메시지 본문 |
| 채널 카드 제목 | 한국어 채널명 길이 다양 |

플레이어 컨트롤/통계 숫자/배지 등은 **고정 사이즈 유지**가 합리적.

#### C-3. accessibility 보강 룰

신규/수정 PR 체크리스트에 다음 추가:
- 인터랙티브 요소 (Button, 토글, 슬라이더): `.accessibilityLabel` 필수
- 상태 표시 (라이브/연결/시청자수): `.accessibilityValue` 필수
- 장식적 아이콘: `.accessibilityHidden(true)`
- 채팅 메시지: `.accessibilityElement(children: .combine)` + 발신자/시간/내용 결합

---

## 6. 핵심 문제 D — 8pt 그리드 위반 (P1)

### 6.1 현황

`grep "\.padding\((\.h|\.v|\.top|\.bottom|\.leading|\.trailing)?,?\s*\d+"` → 50+ 매칭. 대표:

| 위치 | 값 | 토큰 매핑 |
|---|---|---|
| FollowingView.swift L429-430 | h:12, v:6 | `md`, → `xs(4)` 또는 `sm(8)` 통일 |
| FollowingView+List.swift L64,101,143-144,585,689 | v:7, v:9, h:9, v:4, v:9, v:3 | 9/7/3 모두 그리드 위반 → `sm(8)`, `xs(4)`, `xxs(2)` |
| MultiLiveAddSheet+Search.swift L45-46,196 | h:5, v:2, v:8 | h:5 → `xs(4)` |
| KeyboardShortcutsHelpView.swift L100-101 | h:8, v:3 | `sm`, → `xxs(2)` |
| ChatMessageRow.swift L100,108 | t:6, t:3 | → `xs(4)`, `xxs(2)` |
| CategoryBrowseView.swift L422 | h:40 | 의도적 (Empty illustration) — 토큰 추가 또는 주석으로 의도 명시 |

### 6.2 개선안

- 자동 fix-up 스크립트 작성:
  - `padding(.x, 4) → padding(.x, DesignTokens.Spacing.xs)`
  - `padding(.x, 8) → .sm` / `12 → .md` / `16 → .lg` / `24 → .xl`
  - 6/7/9 등 그리드 외 값은 사람이 결정 (`xs` 또는 `sm` 으로 의도 명확화)
- 시각 회귀 방지: PR 적용 후 주요 화면(Home/Following/Multi/Chat/Player) 스크린샷 diff
- lint 룰: 토큰 외부에서 `padding(.x, [숫자])` 사용 시 경고 (예외: `Spacing.*` 통한 호출은 통과)

---

## 7. Material/Glass 사용 정책 (P2)

### 7.1 현황

`.ultraThinMaterial` / `.regularMaterial` 직접 호출 약 12곳:

| 위치 | 용도 |
|---|---|
| PlayerControlsView L256, L445, L701 | 컨트롤 막대 배경 |
| StreamLoadingOverlay L116 | 스피너 카드 |
| SettingsSharedComponents L62 | 헤더 |

ChatPanelView 등 일부는 **의도적으로 솔리드 색상**을 채택 (Material blur 재계산 비용 회피, 코드 주석 명시 ✅).

### 7.2 개선안 — "언제 Glass 를 쓸지" 가이드라인 문서화

`DesignTokens.Glass` 상단 주석에 다음 정책 추가 + 모든 `.ultraThinMaterial` 직접 호출을 `DesignTokens.Glass.thin/regular/thick` 또는 `.glassCard()` 로 치환.

```
사용 정책
─────────
✅ 사용 권장:
  - 영상/썸네일 위 일시적 오버레이 (PlayerControls, StreamAlert)
  - 모달/팝오버/커맨드 팔레트 (커맨드 팔레트 등)
  - 아이콘/픽커 (이모티콘 픽커)

❌ 사용 지양 (솔리드 surface 권장):
  - 상시 표시되는 패널 (ChatPanel, Sidebar, Settings) → 60fps 부담
  - LazyVStack/LazyVGrid 안의 셀 → 매 프레임 blur 재계산
  - 1080p+ 영상 위 풀스크린 (CPU/GPU 비용 큼)
```

### 7.3 성능 사이드 효과

- `PlayerControlsView`의 `.ultraThinMaterial` 3곳을 솔리드 `.controlOnDarkMedia` 로 치환 시 **1080p60 에서 GPU ms 약 0.6~1.0ms 절감** 예상 (동급 SwiftUI 앱 사례 기반)
- 라이브 채널 16개 멀티뷰의 컨트롤 가시 시 큰 차이를 만듦

---

## 8. 애니메이션 일관성 (P2)

### 8.1 현황

DesignTokens.Animation 의 20개 프리셋 사용도는 80%+. 하지만 다음 7곳에서 하드코딩:

| 파일 | 패턴 | 권장 토큰 |
|---|---|---|
| HomeView+Dashboard.swift L97 | `.linear(duration: 0.6)` | `.normal` |
| MultiLiveAddSheet+Following.swift L156 | `.easeInOut(duration: 2.2)` | 신규 `breath: .easeInOut(2.2).repeatForever` 토큰 |
| PlayerControlsView (다수) | `.easeInOut` | `.fast` |
| FollowingView 일부 | `.default` | `.snappy` |

### 8.2 개선안

- 위 하드코딩 7곳을 토큰으로 치환
- `motionSafe()` 미적용 위치 점검: pulse/loop 류는 SharedEffects 처럼 `accessibilityDisplayShouldReduceMotion` 가드를 표준 헬퍼로 만들어 일관 적용
- 신규 토큰 후보:
  - `.breath` — 2~3초 호흡 애니메이션 (라이브 표시 등)
  - `.tabSwitch` — 0.18s 탭 전환 표준

---

## 9. 반응형/레이아웃 (P2)

### 9.1 현황

- `MultiLiveGridLayouts` 가 컨테이너 비율 기반 자동 분할 ([L35-50](../Sources/CViewApp/Views/MultiLiveGridLayouts.swift#L35-L50)) — **모범적**
- `LiveStreamView` 의 `onGeometryChange + 정수 픽셀 스냅` ([L88-110](../Sources/CViewApp/Views/LiveStreamView.swift#L88)) — **모범적**
- 그러나 일부 고정 폭 사용:
  - `BlockedUsersView` `frame(width: 380)`
  - 기타 시트/팝오버에서 magic number
- `ViewThatFits`, `horizontalSizeClass` 미사용 — macOS 단일 플랫폼이므로 큰 문제 아님

### 9.2 개선안

- 시트/팝오버의 폭/최소 높이를 `Layout.sheetIdealWidth/Height` 토큰으로 중앙화 (신규)
- 메인 화면 최소 폭 1000pt 정책 유지 ([Layout.minWindowWidth](../Sources/CViewCore/DesignSystem/DesignTokens.swift#L416)) — 그 이하에서 `MultiChatView` 의 sidebar 모드는 자동 grid 모드로 fallback (이미 존재) ✅

---

## 10. 상태 표현 (Loading/Error/Empty/Skeleton)

### 10.1 현황

| 상태 | 일관성 | 비고 |
|---|---|---|
| Loading (영상) | ✅ 통일 (StreamLoadingOverlay) | adaptive 베일만 보강 필요 |
| Loading (페이지) | ⚠️ 일부 ProgressView 직접 사용 | LoadingIndicator 추출 (§4.2) |
| Skeleton | ⚠️ HomeView/FollowingView 만 | SkeletonCard/Row 추출 |
| Empty | ❌ 8개 중복 (§4.1) | EmptyStateView 통합 (§4.2) |
| Error | ⚠️ ErrorStateView + ErrorRecoveryView 두 갈래 | 단일 ErrorStateView + retry/recover 옵션 |

### 10.2 개선안

위 §4.2 의 4개 컴포넌트 + Skeleton 컴포넌트 도입 시 자연스럽게 해결.
추가로 **ViewState enum**을 도입해 ViewModel 레벨 표현을 통일:

```swift
// CViewCore/Models/ViewState.swift (신규)
public enum ViewState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failure(Error)
}

// 사용 예
extension View {
    @ViewBuilder
    func stateView<V>(_ state: ViewState<V>, @ViewBuilder content: (V) -> some View) -> some View {
        switch state {
        case .idle, .loading: LoadingIndicator(size: .medium, message: nil, useGlassBackground: false)
        case .loaded(let v):  content(v)
        case .empty:          EmptyStateView(icon: "tray", title: "비어 있음", message: nil, action: nil, style: .panel)
        case .failure(let e): ErrorStateView(error: e, retry: nil, style: .panel)
        }
    }
}
```

---

## 11. 채팅/플레이어/오버레이 시각 위계 (P2)

### 11.1 현재 z-stack

```
[Player Video]
    └─ [PlayerOverlayBottom 그라디언트]
    └─ [PlayerControlsView (ultraThinMaterial + .white.opacity(0.06~0.28))]
    └─ [ChatOverlayView (ultraThinMaterial + .white.opacity(0.5))]   ← 라이트 모드 가독성 ❌
    └─ [StreamAlertOverlayView]
[ChatPanelView (solid surfaceBase) — 사이드]
```

### 11.2 개선안

1. **ChatOverlayView**: Material → 솔리드 `Color.black.opacity(adaptive 0.45/0.32)` + `textOnDarkMedia` 어휘 사용
2. **PlayerControlsView**: §3 의 `controlOnDarkMedia*` 토큰 일괄 적용
3. **StreamAlertOverlayView**: 카드 자체에 라이트/다크 두 변형 (어두운 영상 위가 아닐 수도 있음 — Picture-in-Picture 등)
4. **오버레이 페이드 정책 통일**:
   - 컨트롤: 3초 미상호작용 시 fade-out (`.fast` spring)
   - 알림: 6초 후 자동 dismiss + 호버 시 멈춤
   - 현재 일부 `.opacity` 토글이 즉발 — `.smooth` spring 통일

---

## 12. 컬러 팔레트·시맨틱 정리 (P3)

| 항목 | 현황 | 권장 |
|---|---|---|
| 후원 색상 (`Colors.donation/donationEnd`) | 정적 골드 | adaptive 추가 — 라이트에서 채도 낮춤 |
| 라이브 색상 (`Colors.live = 0xFF3B30`) | 양 모드 동일 | macOS 시스템 red 와 통일성 OK ✅ |
| `accentBlue/Purple/Pink/Orange/Cyan` | 5색 adaptive | ✅ 매우 좋음 — 차트/카테고리 카드에 더 적극 활용 권장 (현재 통계 차트만 사용) |
| ChatMessageRow 후원 등급 색상 | hex 직접 | adaptive 팔레트로 |

---

## 13. 추천 실행 로드맵

> 모든 Phase 는 **빌드 가능한 단위**로 끊어 PR 1개당 30분 내 머지 가능하게 설계.

### Phase 1 — 기초 컴포넌트 신설 (P0, 1~2일)

1. `Sources/CViewUI/Components/` 디렉터리 + 4개 컴포넌트 (`EmptyStateView`, `ErrorStateView`, `LoadingIndicator`, `StatusPill`)
2. `Sources/CViewUI/Components/Badge.swift`, `Avatar.swift`, `SkeletonCard.swift`
3. 기존 인라인 `emptyState` 1차 5건 치환 (MultiChatView, FollowingView+MultiChat, RecentFavoritesView, CategoryBrowseView, CommandPaletteView)

**검증**: 빌드 + 각 화면 스크린샷 비교

### Phase 2 — 라이트 모드 색상 정합 (P0, 1~2일)

1. `DesignTokens.Colors` 에 `textOnDarkMedia*`, `controlOnDarkMedia*`, `borderOnDarkMedia`, `mediaVeil` 추가
2. `PlayerControlsView` 14곳, `StreamLoadingOverlay`, `StreamAlertOverlayView`, `ChatOverlayView` 치환
3. ChatMessageRow 후원 등급 hex → adaptive 팔레트
4. `scripts/check-design-tokens.sh` 추가

**검증**: macOS Light/Dark 모드 양쪽 + Increase Contrast 토글 확인

### Phase 3 — 8pt 그리드 정리 + Animation 토큰화 (P1, 0.5일)

1. 50+ 곳 padding 자동 치환 + 6/7/9 위반 사례 사람 판단으로 픽스
2. 7곳 하드코딩 애니메이션 토큰 치환

### Phase 4 — Dynamic Type & 접근성 (P1, 1~2일)

1. `Typography.bodyDynamic` 등 신규 토큰
2. `ChatMessageRow`, `SettingsView`, `EmptyStateView`/`ErrorStateView` 적용
3. 라이브/시청자/연결 상태 `.accessibilityValue` 보강
4. 장식 아이콘 `.accessibilityHidden(true)` 일괄

### Phase 5 — Material 정책 정착 (P2, 0.5일)

1. `.ultraThinMaterial` 직접 호출 → 토큰/모디파이어 치환
2. `DesignTokens.Glass` 사용 정책 docstring + `docs/design-system.md` 신규
3. PlayerControls Material → 솔리드 치환으로 GPU 비용 절감 측정

### Phase 6 — ViewState 도입 (P3, 0.5일)

1. `ViewState<T>` enum + `.stateView` 헬퍼
2. 신규 화면부터 채택, 기존은 점진 마이그레이션

---

## 14. 측정 지표 (개선 효과 검증)

| 지표 | 현재 (추정) | 목표 |
|---|---|---|
| `.white\.opacity` 직접 호출 (오버레이 모듈 외) | 30+ | **0** |
| `private (var\|func) emptyState` | 7 | **0** |
| `Color\(hex:` 사용 (DesignTokens 외) | 10+ | **0** |
| `.padding(_, [숫자])` 토큰 외 호출 | 50+ | **<5** (의도적 magic 만, 주석 필수) |
| `.ultraThinMaterial` 직접 사용 | 12 | **0** (모두 모디파이어/토큰 경유) |
| Dynamic Type 대응 화면 | 0 | 채팅/설정/Empty/Error |
| `.accessibilityLabel` 커버리지 | ~30% | **80%+** |
| 라이트 모드 WCAG AA (4.5:1) 준수 | 부분 위반 | **전 영역 통과** |
| PlayerControls 1080p60 GPU ms | (미측정) | -0.5ms 이상 |

---

## 15. 부록 — 신규/수정 파일 요약

### 추가 (Add)
```
Sources/CViewUI/Components/EmptyStateView.swift
Sources/CViewUI/Components/ErrorStateView.swift     # ErrorStateView.swift 모듈로 이동·승격
Sources/CViewUI/Components/LoadingIndicator.swift
Sources/CViewUI/Components/StatusPill.swift
Sources/CViewUI/Components/Badge.swift
Sources/CViewUI/Components/Avatar.swift
Sources/CViewUI/Components/SkeletonCard.swift
Sources/CViewCore/Models/ViewState.swift
docs/design-system.md                                # Glass/색상 정책 가이드
scripts/check-design-tokens.sh                       # CI/pre-commit 룰
```

### 수정 (Modify)
```
Sources/CViewCore/DesignSystem/DesignTokens.swift
  + Colors: textOnDarkMedia*, controlOnDarkMedia*, borderOnDarkMedia, mediaVeil
  + Typography: bodyDynamic, calloutDynamic, captionDynamic, headlineDynamic, title3Dynamic
  + Animation: breath, tabSwitch
  + Layout: sheetIdealWidth/Height

Sources/CViewApp/Views/PlayerControlsView.swift                 # .white.opacity 14곳 치환
Sources/CViewApp/Views/StreamLoadingOverlay.swift               # 베일/텍스트 adaptive
Sources/CViewApp/Views/StreamAlertOverlayView.swift             # adaptive 변형
Sources/CViewApp/Views/ChatOverlayView.swift                    # 솔리드 + 토큰
Sources/CViewApp/Views/ChatMessageRow.swift                     # 후원 등급 adaptive
Sources/CViewApp/Views/MultiChatView.swift                      # emptyState → EmptyStateView
Sources/CViewApp/Views/FollowingView+MultiChat.swift            # 동상
Sources/CViewApp/Views/RecentFavoritesView.swift                # 동상
Sources/CViewApp/Views/CategoryBrowseView.swift                 # 동상
Sources/CViewApp/Views/CommandPaletteView.swift                 # 동상
Sources/CViewApp/Views/MergedChatView.swift                     # 동상
Sources/CViewApp/Views/MultiLiveOverlays.swift                  # MLEmptyState → EmptyStateView wrapper
Sources/CViewApp/Views/ChannelVODClipTab.swift                  # ChannelInfoEmptyState → EmptyStateView wrapper
Sources/CViewApp/Views/ErrorRecoveryView.swift                  # EmptyStateView 분리
Sources/CViewApp/Views/HomeView+Dashboard.swift                 # animation 토큰화
Sources/CViewApp/Views/MultiLiveAddSheet+Following.swift        # animation 토큰화
Sources/CViewApp/Views/FollowingView*.swift, MultiLiveAddSheet+Search.swift, KeyboardShortcutsHelpView.swift
                                                                # padding 그리드 정합
```

---

## 16. 결론

CView_v2 의 디자인 시스템은 **토큰 정의는 90점, 실사용 일관성은 75점** 수준입니다.
이 문서의 Phase 1~3 만 완료해도 **사용자 체감 라이트 모드 품질, 화면 간 톤 통일성, 코드 유지보수성**이 한 단계 도약합니다.
Phase 4~6 까지 완성하면 macOS 26 시대 접근성/Dynamic Type/모션 정책에 대응하는 일급 macOS 앱 디자인 시스템이 됩니다.

**즉시 시작 권장**: Phase 1 (`CViewUI/Components/` 신설) — 다른 모든 작업의 토대가 되며 시각 회귀 위험이 가장 낮습니다.

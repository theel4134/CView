# CView v2 — 모던 UI/UX 리디자인 종합 계획서

---

## 1. 디자인 트렌드 리서치 요약

### 1.1 2025-2026 주요 트렌드

| 트렌드 | 설명 | 참고 앱 |
|--------|------|---------|
| **Dark Glassmorphism** | 반투명 frosted-glass 패널 + 배경 블러 + 미묘한 그림자/테두리 + 선명한 액센트. macOS Big Sur에서 시작, 2025-2026에 Dark Mode와 결합하여 전성기 | Apple Music, macOS System Settings |
| **Raycast-style Surface Hierarchy** | 순수 검정(#000) 대신 deep charcoal(#1C1C1E) 기반, 6-8pt 명도 단계로 표면 계층 생성 | Raycast, Linear, Arc Browser |
| **Pill-shaped Controls** | 버튼/탭/배지를 pill(캡슐) 형태로 그룹화, 클린한 레이아웃 | YouTube 2025 Redesign, Twitch |
| **Content-First Immersion** | 콘트롤을 최소화하여 콘텐츠(영상/채팅)에 집중, 필요시에만 노출 | YouTube Player 2025, Netflix |
| **Micro-interactions** | hover, press, transition에 spring 기반 애니메이션으로 촉각적 피드백 | Linear, Raycast, Figma |
| **Generous Spacing** | 크고 일관된 여백으로 "숨 쉬는" 레이아웃, 8pt 그리드 엄격 준수 | Apple HIG 2025, Linear |
| **Translucent Sidebar** | 사이드바에 vibrancy/blur 효과로 깊이감 부여 | macOS Finder, Xcode, Arc |
| **Semantic Color System** | 고정색 최소화, 시맨틱 토큰(primary, surface, on-surface)으로 자동 적응 | Material You, Raycast DS |

### 1.2 벤치마크 앱 분석

#### Raycast (macOS 데스크톱 앱 — Gold Standard)
- Surface Stack: `#1C1C1E` → `#242424` → `#2C2C2E` → `#3A3A3C` (6-8pt 명도 스텝)
- Translucent 변형: `rgba(36,36,36,0.85)`, `rgba(44,44,46,0.75)`
- 타이포그래피: SF Pro, 제한된 사이즈 세트(13/14/16/20/28), weight로 계층 구분
- 액센트: 단일 브랜드 컬러 + 시맨틱 컬러만 사용
- 키보드 우선 조작, ⌘K 팔레트 핵심
- 호버 피드백: subtle background tint (1-2% opacity 변화)

#### YouTube 2025 Player Redesign
- "Cleaner and more immersive" — 컨트롤 최소화
- 모든 버튼을 pill 컨테이너로 그룹화
- 프로그레스 바 아래에 모든 컨트롤 배치
- 커스텀 동적 아이콘 (좋아요 누를 때 컨텐츠별 애니메이션)

#### Arc Browser (macOS)
- 사이드바에 vibrancy + blur 적용
- 탭을 "Spaces"로 그룹화 (색상별 구분)
- 커맨드 바 중심 네비게이션
- 분할 뷰 & PiP 네이티브 지원

#### Twitch Redesign Principles
- 스트림 타이틀/정보가 요소에 묻히지 않도록 정리
- 아이콘 일관성 개선
- 카테고리/태그 pill 디자인
- 채팅 영역 시각적 분리 강화

---

## 2. 현재 CView v2 문제점 분석

### 2.1 DesignTokens.swift 문제점

| # | 문제 | 현재 상태 | 개선 방향 |
|---|------|----------|----------|
| 1 | **Spacing 과밀** | 19개 토큰 (hair~xxxl), 1~10 사이 1px 단위 차이 | 8pt 그리드 기반 10개로 정리 |
| 2 | **Radius 과밀** | 15개 토큰 (hair~full), 1px 단위 차이 | 6개로 정리 (xs/sm/md/lg/xl/full) |
| 3 | **Typography inline custom 남용** | `Typography.custom(size:weight:)` 뷰 곳곳에서 임의 사용 | 프리셋만 사용하도록 정리, custom() deprecated |
| 4 | **배경색 너무 어두움** | `backgroundDark: 0x0A0A0A` (거의 순수 검정) | Raycast 스타일 `0x141416` 또는 `0x1C1C1E` |
| 5 | **표면 계층 부족** | surface 2단계 (0x161616, 0x1E1E1E) | 4단계로 확장 (base/elevated/overlay/popover) |
| 6 | **Glassmorphism 미실현** | `GlassCardModifier`가 단색 fill, blur 없음 | 진짜 glass 효과 (`.ultraThinMaterial` + 블러) |
| 7 | **Gradient 단색 fill** | `primary`, `live` 등 단색 LinearGradient | 실제 그라데이션으로 개선 |
| 8 | **미사용 토큰** | `primaryDark`, `primaryLight` 선언만 존재 | 제거 또는 활용 |

### 2.2 View 레벨 문제점

| # | 화면 | 문제 |
|---|------|------|
| 1 | **HomeView (775L)** | 파일 과대, 인라인 스타일 多, 통계 카드/차트/그리드가 한 파일 |
| 2 | **FollowingView (845L)** | 필터/정렬/카드 모두 한 파일, 카드 디자인 밋밋 |
| 3 | **MultiLiveAddSheet (891L)** | 검색+결과+카테고리 한 파일, 최대 파일 |
| 4 | **LiveStreamView (660L)** | HSplitView 직접 구성, 컨트롤/채팅 분리 부족 |
| 5 | **PlayerControlsView (659L)** | Apple TV+ 스타일이지만 정리 필요 |
| 6 | **CategoryBrowseView (647L)** | 카테고리 그리드→드릴다운 한 파일 |
| 7 | **CommandPaletteView (516L)** | Raycast 스타일이지만 디자인 정제 필요 |
| 8 | **SearchViews (497L)** | Spotlight 스타일, 결과 카드 개선 필요 |
| 9 | **ChatMessageRow (462L)** | 메시지 렌더링 복잡, 디자인 개선 여지 |

### 2.3 CViewUI 컴포넌트 문제점

| 컴포넌트 | 문제 |
|----------|------|
| `LiveBadge` | 기본적, 펄스 효과만 있음 |
| `ViewerCountBadge` | 스타일 단순 |
| `CViewLoadingIndicator` | 기본 ProgressView wrapper |
| `CachedAsyncImage` | 기능적으로는 좋으나 placeholder/error 상태 디자인 |
| `EmoticonPickerView` | 고정 크기(380×340), 모던한 느낌 부족 |

---

## 3. 리디자인 전략

### 3.1 디자인 철학 전환

```
현재: "Minimal Monochrome" (흑/백/회 + 단일 액센트)
  ↓
목표: "Dark Glass" (딥 차콜 기반 + 글래스모피즘 + 치지직 그린 액센트)
```

**핵심 원칙:**
1. **깊이(Depth)** — 4단계 표면 계층 + 진짜 glass blur로 공간감
2. **호흡(Breathing)** — 8pt 그리드 엄격 준수, 넉넉한 패딩
3. **일관성(Consistency)** — 모든 카드/버튼/배지가 동일한 glass 시스템
4. **몰입(Immersion)** — 영상 재생 시 UI 최소화
5. **반응성(Responsiveness)** — 모든 인터랙션에 spring 애니메이션

### 3.2 컬러 시스템 재설계

```swift
// AS-IS
backgroundDark = 0x0A0A0A  // 거의 검정 → 눈 피로
surface       = 0x161616
surfaceLight  = 0x1E1E1E

// TO-BE (Raycast-inspired 4-layer stack)
background     = 0x141416  // Deep charcoal (Raycast ~#1C1C1E보다 약간 어둡게)
surfaceBase    = 0x1C1C1E  // 카드, 패널 기본면
surfaceElevated = 0x242426 // 호버, 활성 패널
surfaceOverlay  = 0x2C2C2E // 드롭다운, 툴팁, 모달
surfacePopover  = 0x3A3A3C // 커맨드 팔레트, 팝오버

// Translucent 변형 (Glass용)
glassThin     = rgba(28,28,30, 0.70)  // 얇은 유리
glassMedium   = rgba(36,36,38, 0.80)  // 중간 유리
glassThick    = rgba(44,44,46, 0.88)  // 두꺼운 유리
```

### 3.3 타이포그래피 정리

```swift
// AS-IS: 18개 사이즈 토큰, 38+ 프리셋
// TO-BE: 8개 사이즈, 16개 프리셋 (size × weight 조합만)

사이즈 세트:
  display:   32pt  (대시보드 헤더)
  title:     24pt  (섹션 타이틀)
  headline:  20pt  (카드 타이틀)
  subhead:   16pt  (서브헤더, 버튼)
  body:      14pt  (본문, 채팅)
  caption:   12pt  (보조 텍스트)
  footnote:  11pt  (타임스탬프, 배지)
  micro:      9pt  (뷰어 수 등 극소)

Weight 조합:
  각 사이즈 × { regular, medium, semibold, bold } 중 필요한 것만
  → 총 ~16개 프리셋
```

### 3.4 Spacing 정리

```swift
// AS-IS: 19개 (hair, xxxs, nano, xxs, mini, xss, xsm, xs, smXs, compact, sm, cozy, md, mdl, lg, xl, xxl, xxxl)
// TO-BE: 10개 (8pt 그리드 + 보조)

xxs:  2pt   (테두리 간격)
xs:   4pt   (아이콘-텍스트 간격)
sm:   8pt   (요소 내부 패딩)
md:  12pt   (카드 내부 패딩)
lg:  16pt   (섹션 간격)
xl:  24pt   (섹션 구분)
xxl: 32pt   (대 섹션 간격)
xxxl: 48pt  (페이지 마진)
section: 64pt (섹션 구분선)
page: 80pt   (페이지 레벨 마진)
```

### 3.5 Radius 정리

```swift
// AS-IS: 15개 (hair~full)
// TO-BE: 6개

xs:   4pt   (배지, 태그)
sm:   8pt   (버튼, 입력 필드)
md:  12pt   (카드)
lg:  16pt   (패널, 모달)
xl:  24pt   (대형 카드, 이미지)
full: 999pt (pill, 원형)
```

---

## 4. 구현 범위 & 단계별 진행

### Phase 1: 디자인 토큰 시스템 재구축 (기반)

**변경 파일:**
- `Sources/CViewCore/DesignSystem/DesignTokens.swift` — 전면 재작성

**세부 작업:**
1. Spacing 19개 → 10개 정리 + deprecated alias 유지 (점진 마이그레이션)
2. Radius 15개 → 6개 정리 + deprecated alias
3. Typography 38+ → 16개 프리셋 정리
4. Colors: 4계층 표면 스택 + Glass 변형 추가
5. Gradients: 단색 fill → 실제 그라데이션 (미묘한 2-tone)
6. Shadow: glass 친화적 그림자 (블러 반경 확대, 투명도 조정)
7. 새로운 `GlassModifier`: `.ultraThinMaterial` + 블러 + 미세 테두리
8. 새로운 `SurfaceModifier`: 표면 레벨별 스타일 자동 적용
9. ViewModifier Extension 정리

### Phase 2: 공통 컴포넌트 리디자인 (CViewUI)

**변경 파일:**
- `Sources/CViewUI/CViewUI.swift`
- `Sources/CViewUI/CachedAsyncImage.swift`
- `Sources/CViewUI/TimelineSlider.swift`
- `Sources/CViewUI/EmoticonPickerView.swift`
- `Sources/CViewUI/EmoticonViews.swift`

**세부 작업:**
1. `LiveBadge` → glass pill + 그린/레드 그라데이션 글로우 + breath 애니메이션
2. `ViewerCountBadge` → glass pill, SF Symbol 아이콘 개선
3. `CViewLoadingIndicator` → 커스텀 로딩 (원형 그라데이션 스피너 또는 shimmer)
4. `CachedAsyncImage` → placeholder shimmer, error state 개선, 부드러운 fade-in
5. `TimelineSlider` → glass 트랙, 선명한 핸들, 호버 시 확장 효과
6. `EmoticonPickerView` → 리사이즈 가능, glass 배경, 검색 바 개선
7. 새로운 공통 컴포넌트:
   - `GlassCard` (범용 glass 카드 컨테이너)
   - `PillButton` (캡슐 버튼)
   - `PillTag` (카테고리/태그 pill)
   - `SectionHeader` (통일된 섹션 헤더)
   - `AvatarView` (프로필 이미지 + 온라인 상태)
   - `StreamThumbnail` (썸네일 + 오버레이 정보)

### Phase 3: 사이드바 & 네비게이션 (Skeleton)

**변경 파일:**
- `Sources/CViewApp/Navigation/AppRouter.swift`
- `Sources/CViewApp/Views/MainContentView.swift`

**세부 작업:**
1. 사이드바 → translucent/vibrancy 배경 (`.ultraThinMaterial`)
2. 사이드바 아이템: glass hover 효과, 선택 시 accent tint
3. 사이드바 폭 조절 핸들 개선
4. NavigationSplitView 전환 애니메이션 spring 적용
5. Window toolbar 스타일 개선 (title bar 통합)

### Phase 4: Home & Dashboard 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/HomeView.swift`
- `Sources/CViewApp/Views/Dashboard/DashboardStatCard.swift`
- `Sources/CViewApp/Views/Dashboard/DashboardCharts.swift`

**세부 작업:**
1. HomeView 분리: 통계 섹션, 인기 섹션, 추천 섹션 별도 SubView
2. StatCard → glass card + 숫자 카운트업 애니메이션
3. Charts → 차트 색상 accent 표준화, glass 컨테이너
4. 인기 채널 그리드 → 큰 썸네일, glass 오버레이 정보, 호버 효과
5. 섹션 간 넉넉한 spacing (xl 이상)
6. 스크롤 시 헤더 sticky/blur 효과

### Phase 5: Following (팔로잉) 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/FollowingView.swift`
- `Sources/CViewApp/Views/FollowingCardViews.swift`

**세부 작업:**
1. 필터/정렬 → pill 버튼 바 (수평 스크롤)
2. 카테고리 칩 → glass pill 태그
3. Live 카드 → 큰 썸네일 + glass 정보 오버레이
4. Offline 카드 → subtle dimmed 스타일
5. 카드 호버 → scale + shadow spring 애니메이션
6. 라이브 카드에 viewer count pill 오버레이

### Phase 6: 라이브 스트림 플레이어 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/LiveStreamView.swift`
- `Sources/CViewApp/Views/PlayerControlsView.swift`
- `Sources/CViewApp/Views/StreamLoadingOverlay.swift`

**세부 작업:**
1. 플레이어 컨트롤 → YouTube 2025 스타일 pill 그룹화
2. 프로그레스 바 → glass 트랙, hover 시 확대
3. 볼륨/화질 팝오버 → glass 패널
4. 스트림 로딩 → 커스텀 spinner + glass 오버레이 + 단계별 상태 텍스트
5. HSplitView 분리선 → 미세한 glass 디바이더
6. 풀스크린 전환 → smooth spring 애니메이션
7. 키보드 단축키 힌트 → 호버 시 glass tooltip

### Phase 7: 채팅 패널 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/ChatPanelView.swift`
- `Sources/CViewApp/Views/ChatMessageRow.swift`
- `Sources/CViewApp/Views/ChatInputView.swift`
- `Sources/CViewApp/Views/ChatAutocompleteView.swift`

**세부 작업:**
1. 채팅 배경 → surfaceBase, 플레이어와 시각적 분리
2. 메시지 행 → 호버 시 subtle 배경 tint
3. 도네이션 메시지 → glass card + donation gradient 테두리
4. 채팅 입력 → glass 입력 필드, 전송 버튼 pill
5. Autocomplete → glass 드롭다운
6. 채팅 설정 → glass 패널
7. 이모티콘 피커 → glass 배경 + 탭 pill

### Phase 8: 검색 & 커맨드 팔레트 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/SearchViews.swift`
- `Sources/CViewApp/Views/SearchResultRows.swift`
- `Sources/CViewApp/Views/CommandPaletteView.swift`

**세부 작업:**
1. 검색 바 → glass 입력 필드 + 확대 포커스 애니메이션
2. 검색 결과 → glass 카드, 카테고리별 섹션
3. 키워드 추천 → pill 태그
4. CommandPalette → Raycast 스타일 정밀 재현
   - glass 배경 + 강한 blur
   - 결과 행 hover 효과
   - 키보드 네비게이션 인디케이터
   - 섹션 구분선 미세화

### Phase 9: Multi-Live 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/MultiLiveView.swift`
- `Sources/CViewApp/Views/MultiLiveTabBar.swift`
- `Sources/CViewApp/Views/MultiLiveAddSheet.swift`
- `Sources/CViewApp/Views/MultiLivePlayerPane.swift`
- `Sources/CViewApp/Views/MultiLiveGridLayouts.swift`
- `Sources/CViewApp/Views/MultiLiveControlViews.swift`
- `Sources/CViewApp/Views/MultiLiveOverlays.swift`
- `Sources/CViewApp/Views/MultiLiveStateViews.swift`

**세부 작업:**
1. 탭 바 → glass pill 탭 + 선택 인디케이터 애니메이션
2. 플레이어 그리드 → 균등 분할 + glass 테두리
3. 추가 시트 → glass 모달, 검색/결과 개선
4. StatusOverlay → glass + 상태 아이콘
5. 오디오 전환 → pill 버튼

### Phase 10: 설정 & 기타 화면 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/SettingsView.swift`
- `Sources/CViewApp/Views/GeneralSettingsTab.swift`
- `Sources/CViewApp/Views/PlayerSettingsTab.swift`
- `Sources/CViewApp/Views/ChatSettingsTab.swift`
- `Sources/CViewApp/Views/ChatSettingsQualityView.swift`
- `Sources/CViewApp/Views/NetworkSettingsTab.swift`
- `Sources/CViewApp/Views/PerformanceSettingsTab.swift`
- `Sources/CViewApp/Views/MetricsSettingsTab.swift`
- `Sources/CViewApp/Views/SettingsSharedComponents.swift`
- `Sources/CViewApp/Views/LoginView.swift`
- `Sources/CViewApp/Views/MenuBarView.swift`
- `Sources/CViewApp/Views/SplashView.swift`

**세부 작업:**
1. 설정 → macOS System Settings 스타일 유지하되 glass 적용
2. 설정 섹션 → glass card 그룹화
3. Toggle/Picker/Slider → accent 컬러 통일
4. 로그인 → glass 모달, OAuth 버튼 pill
5. 메뉴바 팝업 → glass 배경 + blur
6. 스플래시 → 그라데이션 로고 애니메이션

### Phase 11: 카테고리 & 클립 리디자인

**변경 파일:**
- `Sources/CViewApp/Views/CategoryBrowseView.swift`
- `Sources/CViewApp/Views/PopularClipsView.swift`
- `Sources/CViewApp/Views/PopularClipCards.swift`
- `Sources/CViewApp/Views/ClipPlayerView.swift`
- `Sources/CViewApp/Views/VODPlayerView.swift`

**세부 작업:**
1. 카테고리 그리드 → glass card + 대표 이미지
2. 드릴다운 → 채널 리스트 glass 카드
3. 클립 카드 → 큰 썸네일 + glass 정보 오버레이
4. 클립 플레이어 → 라이브 플레이어와 통일된 컨트롤

### Phase 12: 채널 정보 & 프로필

**변경 파일:**
- `Sources/CViewApp/Views/ChannelInfoView.swift`
- `Sources/CViewApp/Views/ChannelInfoHeaderView.swift`
- `Sources/CViewApp/Views/ChannelInfoTabContent.swift`
- `Sources/CViewApp/Views/ChannelMediaCards.swift`
- `Sources/CViewApp/Views/ChannelVODClipTab.swift`
- `Sources/CViewApp/Views/ChannelMemoSheet.swift`
- `Sources/CViewApp/Views/ChatUserProfileSheet.swift`
- `Sources/CViewApp/Views/BlockedUsersView.swift`

**세부 작업:**
1. 채널 헤더 → 배너 이미지 + glass 프로필 오버레이
2. 탭 → pill 탭 바
3. VOD/클립 그리드 → glass 카드
4. 유저 프로필 시트 → glass 모달
5. 메모 시트 → glass 입력 필드

### Phase 13: Effects & Shared

**변경 파일:**
- `Sources/CViewApp/Views/SharedEffects.swift`
- `Sources/CViewApp/Views/Components/LiveThumbnailView.swift`
- `Sources/CViewApp/Views/Components/AppIconView.swift`
- `Sources/CViewApp/Views/ErrorStateView.swift`
- `Sources/CViewApp/Views/ErrorRecoveryView.swift`

**세부 작업:**
1. ShimmerModifier → 그라데이션 방향/속도 개선
2. LiveThumbnailView → glass 오버레이 + 라이브 배지
3. Error 뷰 → glass card + 재시도 pill 버튼

### Phase 14: 성능 & 통계 뷰

**변경 파일:**
- `Sources/CViewApp/Views/PerformanceOverlayView.swift`
- `Sources/CViewApp/Views/StatisticsView.swift`
- `Sources/CViewApp/Views/StatisticsDetailViews.swift`
- `Sources/CViewApp/Views/RecentFavoritesView.swift`

**세부 작업:**
1. 성능 오버레이 → glass HUD, 미니멀 모노 폰트
2. 통계 → glass card + 차트 accent 통일

---

## 5. 새로운 디자인 토큰 미리보기

```swift
// ── Phase 1 에서 구현할 새 DesignTokens 구조 ──

public enum DesignTokens {

    // MARK: - Spacing (8pt Grid — 10 tokens)
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
        public static let section: CGFloat = 64
        public static let page: CGFloat = 80
    }

    // MARK: - Radius (6 tokens)
    public enum Radius {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let full: CGFloat = 999
    }

    // MARK: - Typography (8 sizes × limited weights)
    public enum Typography {
        public static let display = Font.system(size: 32, weight: .bold)
        public static let title = Font.system(size: 24, weight: .bold)
        public static let headline = Font.system(size: 20, weight: .semibold)
        public static let subhead = Font.system(size: 16, weight: .medium)
        public static let body = Font.system(size: 14, weight: .regular)
        public static let bodyMedium = Font.system(size: 14, weight: .medium)
        public static let bodySemibold = Font.system(size: 14, weight: .semibold)
        public static let caption = Font.system(size: 12, weight: .regular)
        public static let captionMedium = Font.system(size: 12, weight: .medium)
        public static let footnote = Font.system(size: 11, weight: .regular)
        public static let footnoteMedium = Font.system(size: 11, weight: .medium)
        public static let micro = Font.system(size: 9, weight: .medium)
        public static let headlineBold = Font.system(size: 20, weight: .bold)
        public static let subheadSemibold = Font.system(size: 16, weight: .semibold)
        public static let titleSemibold = Font.system(size: 24, weight: .semibold)
        public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    }

    // MARK: - Colors (4-Layer Surface Stack + Glass)
    public enum Colors {
        // accent
        public static let primary = Color(hex: 0x00FFA3)
        public static let chzzkGreen = primary

        // surface stack (6-8pt luminance steps)
        public static let background = adaptive(dark: 0x141416, light: 0xF5F5F7)
        public static let surfaceBase = adaptive(dark: 0x1C1C1E, light: 0xFFFFFF)
        public static let surfaceElevated = adaptive(dark: 0x242426, light: 0xF0F0F5)
        public static let surfaceOverlay = adaptive(dark: 0x2C2C2E, light: 0xEAEAF0)
        public static let surfacePopover = adaptive(dark: 0x3A3A3C, light: 0xE0E0E8)

        // text
        public static let textPrimary = adaptive(dark: 0xF5F5F7, light: 0x1D1D1F)
        public static let textSecondary = adaptive(dark: 0x8E8E93, light: 0x48484A)
        public static let textTertiary = adaptive(dark: 0x636366, light: 0x8E8E93)

        // border
        public static let border = adaptive(dark: 0x38383A, light: 0xD1D1D6)
        public static let borderSubtle = adaptive(dark: 0x2C2C2E, light: 0xE5E5EA)

        // semantic
        public static let live = Color(hex: 0xFF3B30)
        public static let liveGlow = Color(hex: 0xFF3B30).opacity(0.3)
        public static let donation = Color(hex: 0xFFD700)
        public static let error = Color(hex: 0xFF453A)
        public static let success = Color(hex: 0x00FFA3)
        public static let warning = Color(hex: 0xFFAA00)

        // accent palette
        public static let accentBlue = Color(hex: 0x5BA3FF)
        public static let accentPurple = Color(hex: 0xBF5FFF)
        public static let accentPink = Color(hex: 0xFF5FA0)
        public static let accentOrange = Color(hex: 0xFF9F0A)

        // on-surface
        public static let onPrimary = Color(hex: 0x0A0A0A)
        public static let textOnOverlay = Color.white
    }

    // MARK: - Glass (새로운 토큰)
    public enum Glass {
        /// 얇은 유리 — 사이드바, 오버레이
        public static let thin = Material.ultraThinMaterial
        /// 보통 유리 — 카드, 패널
        public static let regular = Material.thinMaterial
        /// 두꺼운 유리 — 모달, 팝오버
        public static let thick = Material.regularMaterial
        /// 배경 블러 강도
        public static let blurRadius: CGFloat = 20
    }
}

// MARK: - Glass Card Modifier (진짜 Glass)
public struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let borderOpacity: Double

    public init(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        material: Material = .thinMaterial,
        borderOpacity: Double = 0.15
    ) { ... }

    public func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(borderOpacity), lineWidth: 0.5)
            }
    }
}
```

---

## 6. 마이그레이션 전략

### 6.1 Deprecated Alias (호환성)
Phase 1에서 기존 토큰명을 `@available(*, deprecated)` alias로 유지하여 빌드를 깨지 않고 점진적 마이그레이션:

```swift
// 기존 코드 호환 alias
extension DesignTokens.Spacing {
    @available(*, deprecated, renamed: "sm")
    public static let xs: CGFloat = 8  // 기존 xs → 신규 sm
    // ...
}
```

### 6.2 점진적 뷰 마이그레이션
- 각 Phase에서 해당하는 뷰만 새 토큰으로 전환
- 전환 완료 후 deprecated alias 제거 (최종 Phase)

### 6.3 빌드 검증
- 각 Phase 완료 후 빌드 테스트
- UI 스크린샷 비교 (가능하다면)

---

## 7. 우선순위 & 예상 작업량

| Phase | 이름 | 우선순위 | 예상 변경 파일 수 | 복잡도 |
|-------|------|---------|-----------------|--------|
| 1 | 디자인 토큰 재구축 | 🔴 필수 | 1 | ★★★★ |
| 2 | 공통 컴포넌트 | 🔴 필수 | 5 + 신규 | ★★★ |
| 3 | 사이드바 & 네비게이션 | 🔴 필수 | 2 | ★★★ |
| 4 | Home & Dashboard | 🟡 높음 | 3 | ★★★ |
| 5 | Following | 🟡 높음 | 2 | ★★★ |
| 6 | 라이브 플레이어 | 🟡 높음 | 3 | ★★★★ |
| 7 | 채팅 패널 | 🟡 높음 | 4 | ★★★ |
| 8 | 검색 & 커맨드 | 🟢 중간 | 3 | ★★★ |
| 9 | Multi-Live | 🟢 중간 | 8 | ★★★★ |
| 10 | 설정 & 기타 | 🟢 중간 | 12 | ★★★ |
| 11 | 카테고리 & 클립 | 🟢 중간 | 5 | ★★ |
| 12 | 채널 정보 | 🟢 중간 | 8 | ★★ |
| 13 | Effects & Shared | 🔵 낮음 | 5 | ★★ |
| 14 | 성능 & 통계 | 🔵 낮음 | 4 | ★★ |

**총 변경 대상: ~65개 파일 + 신규 컴포넌트 ~6개**

---

## 8. 핵심 시각 변화 요약

```
┌─────────────────────────────────────────────────────────┐
│  현재 (Minimal Monochrome)     →    목표 (Dark Glass)    │
├─────────────────────────────────────────────────────────┤
│  #0A0A0A 배경 (거의 검정)      →    #141416 (Deep Charcoal) │
│  단색 표면 fill                →    Material blur + 반투명  │
│  0.5px 테두리                  →    0.5px 화이트 글로우 테두리│
│  기본 ProgressView             →    커스텀 Glass 스피너     │
│  사각형 버튼                   →    Pill 캡슐 버튼         │
│  flat 카드                    →    Glass 카드 + hover 효과 │
│  19 spacing 토큰              →    10 spacing 토큰        │
│  15 radius 토큰               →    6 radius 토큰          │
│  38+ font 프리셋              →    16 font 프리셋          │
│  인라인 custom() 남용          →    프리셋만 사용           │
│  easeInOut 애니메이션          →    spring 중심             │
│  2단계 표면 계층               →    4단계 표면 계층         │
└─────────────────────────────────────────────────────────┘
```

---

## 9. 진행 방식

이 계획 승인 후, Phase 1부터 순차적으로 구현합니다.
각 Phase 완료 시:
1. 빌드 확인
2. 변경 사항 요약 보고
3. 다음 Phase 진행 여부 확인

**시작할 Phase나 수정할 부분이 있으면 말씀해주세요.**

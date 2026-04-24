# CView_v2 메인 홈 화면 전면 개편 분석 및 UI 제안

작성일: 2026-04-24  
범위: `Sources/CViewApp/Views/HomeView*.swift`, `MainContentView.swift`, `SearchViews.swift`, `FollowingView*.swift`, `RecentFavoritesView.swift`, `HomeViewModel.swift`, `DesignTokens.swift`  
목적: 현재 홈 화면의 정보 구조와 기능 분산 상태를 분석하고, 전면 개편 시 넣어야 할 필수 기능과 현대적인 UI 방향을 제안한다.

---

## 0. 한 눈에 보는 결론

현재 CView_v2 홈은 "사용자가 바로 볼 방송을 고르는 시작점"이라기보다 "치지직 전체 통계를 보여주는 대시보드"에 가깝다. `HomeView`는 헤더, 통계 카드, 차트, 스트리밍 분석, 메트릭 서버, 내 라이브, 인기 채널을 한 스크롤에 배치한다. 구조 자체는 안정적이지만, 홈 첫 화면에서 가장 중요한 작업인 **바로 시청, 팔로잉 확인, 검색, 최근 시청 복귀, 멀티라이브 시작**이 뒤쪽 섹션 또는 다른 사이드바 화면에 흩어져 있다.

권장 방향은 홈을 "라이브 커맨드 센터"로 재정의하는 것이다. 첫 화면 상단에는 검색과 핵심 액션을 고정하고, 중단에는 개인화된 라이브/최근 시청/즐겨찾기/추천을 카드 또는 레일 형태로 배치하며, 통계와 메트릭은 접을 수 있는 보조 영역으로 내려야 한다.

우선순위는 다음과 같다.

| 우선순위 | 제안 | 이유 |
|---|---|---|
| P0 | 홈 상단을 "검색 + 지금 볼 만한 라이브 + 빠른 액션"으로 재구성 | 앱 실행 후 첫 행동을 줄임 |
| P0 | 팔로잉 라이브, 즐겨찾기 라이브, 최근 시청 복귀를 홈 1화면 안에 노출 | 현재 핵심 개인 기능이 분산됨 |
| P0 | 멀티라이브 시작 진입점을 홈에 추가 | CView의 차별 기능을 홈에서 바로 발견 가능하게 함 |
| P1 | 통계/메트릭은 접이식 또는 별도 대시보드 CTA로 축소 | 홈 정보 과밀 해소 |
| P1 | Raycast/Spotlight형 검색 경험을 홈 전역 검색으로 승격 | 이미 `SearchViews`에 좋은 구현 자산 존재 |
| P1 | 카드 비주얼을 썸네일 중심 미디어 레이아웃으로 강화 | 라이브 앱의 첫 인상 개선 |

---

## 1. 현재 홈 구조 분석

### 1.1 화면 구성

`HomeView`는 단일 `ScrollView`와 `LazyVStack`으로 7개 섹션을 순서대로 보여준다.

1. `dashboardHeader`
2. `statCardsGrid`
3. `chartsSection`
4. `analyticsSection`
5. `metricsServerSection`
6. `personalStatsSection`
7. `topChannelsSection`

근거:

- [HomeView.swift L38-L75](../Sources/CViewApp/Views/HomeView.swift#L38-L75): 홈의 전체 섹션 순서
- [HomeView+Dashboard.swift L12-L124](../Sources/CViewApp/Views/HomeView+Dashboard.swift#L12-L124): 헤더와 라이브 요약
- [HomeView+Dashboard.swift L219-L260](../Sources/CViewApp/Views/HomeView+Dashboard.swift#L219-L260): 통계 카드
- [HomeView+Sections.swift L77-L140](../Sources/CViewApp/Views/HomeView+Sections.swift#L77-L140): 내 라이브 섹션
- [HomeView+Sections.swift L176-L212](../Sources/CViewApp/Views/HomeView+Sections.swift#L176-L212): 인기 채널 섹션

이 구성은 데이터 관찰에는 좋지만 홈 화면으로서는 다음 문제가 있다.

- 첫 화면 상단이 통계 중심이라 "지금 볼 방송"이 바로 보이지 않는다.
- 검색창이 홈에 없다. 검색은 별도 사이드바 항목이다.
- 최근 시청/즐겨찾기는 `RecentFavoritesView`로 분리되어 홈의 개인화 흐름과 이어지지 않는다.
- 멀티라이브는 앱의 강점이지만 홈에서는 명확한 시작 액션이 없다.
- 메트릭 서버와 차트가 상단 흐름에 들어오면서 일반 사용자의 첫 사용 목적과 충돌한다.

### 1.2 데이터와 기능 자산

`HomeViewModel`은 홈 개편에 필요한 데이터 자산을 이미 상당히 갖고 있다.

| 데이터 | 현재 위치 | 홈 개편 활용 |
|---|---|---|
| `liveChannels` | [HomeViewModel.swift L19](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L19) | 인기/추천/검색 초기 결과 |
| `allStatChannels` | [HomeViewModel.swift L20](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L20) | 카테고리별 트렌드와 대시보드 |
| `recommendedChannels` | [HomeViewModel.swift L21](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L21) | 추천 레일의 명시적 모델 후보. 현재 UI 활용은 약함 |
| `followingChannels` | [HomeViewModel.swift L22](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L22) | 팔로잉 라이브, 오프라인 팔로잉, 추천 근거 |
| `recentLiveFollowing` | [HomeViewModel.swift L100-L102](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L100-L102) | 홈 상단 개인 라이브 레일 |
| `topChannels` | [HomeViewModel.swift L102](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L102) | 인기 채널 레일 |
| 캐시 복원 | [HomeViewModel.swift L340-L363](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L340-L363) | 앱 실행 직후 즉시 홈 표시 |
| 자동 갱신 | [HomeViewModel.swift L385-L426](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L385-L426) | 라이브 홈 최신성 유지 |

좋은 점은 캐시 복원과 자동 갱신이 이미 있어 홈을 개인화 피드로 바꿔도 초기 빈 화면 문제를 줄일 수 있다는 것이다.

### 1.3 내비게이션 분산

`MainContentView`는 홈, 팔로잉, 카테고리, 검색, 클립, 최근/즐겨찾기, 메트릭, 설정을 사이드바 detail로 분리한다.

근거:

- [MainContentView.swift L58-L77](../Sources/CViewApp/Views/MainContentView.swift#L58-L77): `NavigationSplitView`
- [MainContentView.swift L84-L126](../Sources/CViewApp/Views/MainContentView.swift#L84-L126): 사이드바 항목별 detail view

분리 자체는 맞지만, 홈에서는 다음 기능의 요약 진입점이 필요하다.

- 검색: [SearchViews.swift L159-L180](../Sources/CViewApp/Views/SearchViews.swift#L159-L180)에 이미 Spotlight/Raycast형 검색바 자산이 있다.
- 최근/즐겨찾기: [RecentFavoritesView.swift L16-L43](../Sources/CViewApp/Views/RecentFavoritesView.swift#L16-L43)에 탭과 상태 모델이 있다.
- 팔로잉: [FollowingView.swift L1-L5](../Sources/CViewApp/Views/FollowingView.swift#L1-L5) 기준으로 라이브 채널 목록과 멀티라이브/멀티채팅 경험이 강하다.

홈 개편은 이 화면들을 대체하는 것이 아니라, 각 기능의 "첫 행동"만 홈으로 당겨오는 식이 적절하다.

---

## 2. 홈 개편 목표

### 2.1 제품 관점 목표

홈의 역할을 다음으로 명확히 바꾼다.

> 앱을 열자마자 "내가 볼 방송"을 찾고, 바로 재생하거나 멀티라이브에 추가하는 화면.

이를 위해 홈 첫 화면에서 사용자가 3초 안에 할 수 있어야 하는 행동은 다음이다.

1. 검색어 입력
2. 팔로잉 라이브 1개 재생
3. 최근 보던 채널 재개
4. 즐겨찾기 채널 확인
5. 멀티라이브 슬롯에 채널 추가
6. 인기/카테고리 방송 탐색

### 2.2 UI 관점 목표

- 통계보다 콘텐츠를 먼저 보여준다.
- 카드보다 썸네일, 채널 아바타, LIVE 상태, 시청자 수를 강하게 보여준다.
- 액션은 텍스트 버튼보다 아이콘/툴바/컨텍스트 메뉴 중심으로 간결하게 둔다.
- macOS 앱답게 사이드바와 툴바 패턴을 존중하고, 과한 랜딩 페이지식 히어로는 피한다.
- 기존 `DesignTokens`의 4-layer surface, chzzk green accent, adaptive color를 유지한다.

---

## 3. 추천 정보 구조

### 3.1 권장 홈 레이아웃

```text
┌──────────────────────────────────────────────────────────────┐
│ Top Command Bar                                               │
│ [검색: 채널/라이브/클립]   [새로고침] [멀티라이브] [설정]      │
├──────────────────────────────────────────────────────────────┤
│ Now Live For You                                              │
│ 팔로잉 라이브 / 즐겨찾기 라이브 / 최근 보던 채널 복귀          │
├──────────────────────────────────────────────────────────────┤
│ Continue Watching + Favorites                                 │
│ 최근 시청 4개 + 즐겨찾기 4개                                  │
├──────────────────────────────────────────────────────────────┤
│ Discover Live                                                 │
│ 인기 라이브 / 카테고리 칩 / 추천 채널                         │
├──────────────────────────────────────────────────────────────┤
│ Compact Insights                                              │
│ 전체 라이브 수, 총 시청자, 상위 카테고리, 메트릭 상태           │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 화면별 역할 분리

| 영역 | 역할 | 현재 자산 | 개편 제안 |
|---|---|---|---|
| Top Command Bar | 검색, 새로고침, 멀티라이브 시작 | `SearchViews.searchBar`, `HomeView.refresh`, `MultiLiveManager` | 홈 상단 고정 또는 첫 섹션화 |
| Now Live For You | 개인화된 바로보기 | `recentLiveFollowing`, `followingLiveCount` | 팔로잉 라이브 6개를 첫 번째 레일로 노출 |
| Continue Watching | 최근 시청 복귀 | `DataStore.fetchRecentItems` | 최근 4개만 홈에 요약 |
| Favorites | 즐겨찾기 빠른 접근 | `DataStore.fetchFavoriteItems` | LIVE 중 즐겨찾기 우선 정렬 |
| Discover Live | 인기/추천/카테고리 | `topChannels`, `topCategories`, `categoryChannels` | 썸네일 카드 + 카테고리 필터 칩 |
| Compact Insights | 보조 지표 | 기존 통계 카드/차트/메트릭 | 접이식 또는 하단 요약 |

---

## 4. 필수 기능 제안

### P0-1. 홈 전역 검색

현재 검색 경험은 별도 화면에 있고, 검색바 스타일은 이미 잘 만들어져 있다. 홈 상단에 같은 패턴의 검색 진입점을 두되, 실제 결과는 다음 중 하나로 처리한다.

- 빠른 방식: 클릭/단축키 입력 시 `SearchView`로 이동
- 고급 방식: 홈 안에서 spotlight overlay를 열고 검색 결과를 즉시 표시

권장 구현:

- placeholder: `채널, 라이브, 클립 검색`
- 왼쪽 `magnifyingglass`, 오른쪽 `command` 단축키 힌트
- 최근 검색/팔로잉 자동완성은 `SearchViewModel.followingChannelNames` 자산 재사용
- 검색 결과 클릭 시 `LiveStreamView`, `ChannelInfoView`, `ClipLookupView`로 즉시 이동

이유:

- 홈에서 검색이 없으면 사용자는 사이드바를 다시 훑어야 한다.
- 라이브 앱에서 검색은 보조 기능이 아니라 시청 진입점이다.

### P0-2. "지금 라이브 중인 팔로잉" 최상단 레일

`personalStatsSection`은 현재 홈 뒤쪽에 있고 `recentLiveFollowing` 6개만 보여준다. 이 섹션을 상단으로 끌어올려야 한다.

필수 표시 정보:

- 채널 아바타
- 방송 썸네일
- 방송 제목
- 시청자 수
- 카테고리
- LIVE 지속 시간 또는 시작 시각
- 버튼: 재생, 멀티라이브 추가, 채널 상세

권장 UI:

- 넓은 창: 좌측 "대표 추천 라이브" 1개 대형 카드 + 우측 팔로잉 라이브 4개 compact 카드
- 좁은 창: 가로 스크롤 레일 또는 2열 adaptive grid

### P0-3. 최근 시청/즐겨찾기 홈 요약

`RecentFavoritesView`는 좋은 자산이지만 별도 메뉴에 있어 발견성이 낮다. 홈에는 전체 목록이 아니라 "복귀 가능한 항목"만 보여주면 된다.

필수 규칙:

- 최근 시청 4개, 즐겨찾기 4개 제한
- LIVE 중인 즐겨찾기를 우선 정렬
- 최근 시청 중 현재 LIVE인 채널에는 빨간 LIVE dot + 시청자 수 표시
- 오프라인 채널은 채널 상세로 이동, 라이브 채널은 바로 재생

### P0-4. 멀티라이브 빠른 시작

CView의 차별점은 단일 라이브보다 멀티라이브/멀티채팅이다. 홈에서 이 기능을 더 강하게 보여줘야 한다.

필수 액션:

- "멀티라이브 시작" primary button
- 각 라이브 카드의 hover 액션: `+ 멀티라이브`
- 이미 멀티라이브 세션이 있으면 홈 상단에 현재 세션 strip 표시
- 추천 조합: "팔로잉 라이브 상위 2~4개로 멀티라이브 구성"

권장 문구:

- `멀티라이브`
- `현재 3개 시청 중`
- `팔로잉 라이브로 시작`

### P0-5. 로그인/쿠키 상태를 홈에서 명확히 해결

현재 `cookieLoginBanner`는 내 라이브 섹션 안쪽에 있다. 팔로잉 라이브가 홈 핵심이 되면 인증 상태도 상단에서 해결해야 한다.

상태별 홈 처리:

| 상태 | 홈 UI |
|---|---|
| 미로그인 | 개인화 영역에 로그인 CTA, 인기 라이브는 계속 표시 |
| 쿠키 로그인 필요 | 네이버 로그인 CTA를 검색/팔로잉 영역 가까이에 표시 |
| 로그인 완료 + 팔로잉 없음 | 팔로잉 설정 안내보다 인기/카테고리 탐색을 먼저 제공 |
| 캐시만 있음 | stale badge와 함께 캐시 콘텐츠를 유지 |

---

## 5. 추천 기능 제안

### P1-1. 개인화 추천 레일

`recommendedChannels`가 모델에 있으나 홈 UI에서 강하게 쓰이지 않는다. 우선은 복잡한 ML 없이 rule-based 추천부터 시작한다.

추천 스코어 예시:

```text
score =
  followingLive * 100
+ favoriteLive * 80
+ recentlyWatchedLive * 60
+ sameCategoryAsRecent * 25
+ viewerRankNormalized * 15
- alreadyWatching * 100
```

표시 레일:

- `지금 볼 만한 방송`
- `최근 본 카테고리`
- `팔로잉이 많이 보는 카테고리`
- `방금 뜬 라이브`

### P1-2. 카테고리 칩과 빠른 필터

현재 카테고리 통계는 차트 중심이다. 홈에서는 차트보다 필터 칩이 더 유용하다.

권장 칩:

- 전체
- 게임
- 스포츠
- 토크
- 음악
- 상위 카테고리 5개

카테고리 칩 클릭 결과:

- 홈 내 Discover Live 카드만 필터링
- "전체보기" 클릭 시 `CategoryBrowseView`로 이동

### P1-3. 홈 카드 액션 메뉴

각 라이브 카드 hover 또는 context menu에 다음 액션을 통일한다.

- 재생
- 멀티라이브에 추가
- 채널 상세
- 즐겨찾기 토글
- 채팅만 열기

`FollowingLiveCard`와 `MiniChannelCard` 계열의 액션 패턴을 맞추는 것이 중요하다.

### P1-4. Compact Insights

기존 통계 화면은 버리지 말고 홈 하단 또는 접이식 영역으로 줄인다.

표시 추천:

- 라이브 채널 수
- 총 시청자
- 상위 카테고리 3개
- 메트릭 서버 상태
- 앱 레이턴시 평균은 서버가 온라인일 때만 표시

차트는 기본 접힘 상태가 낫다. 통계를 자세히 보려는 사용자는 `MetricsDashboardView` 또는 별도 "분석 보기"로 이동하면 된다.

### P2-1. "홈 편집" 또는 섹션 순서 개인화

Apple HIG의 사이드바 가이드도 사용자가 중요한 영역을 커스터마이즈할 수 있으면 좋다고 권장한다. 홈도 장기적으로 섹션 표시/순서 설정을 제공할 수 있다.

예:

- 팔로잉 먼저 보기
- 인기 먼저 보기
- 메트릭 숨기기
- 최근 시청 숨기기
- 카드 밀도: compact / comfortable

---

## 6. 현대적인 UI 디자인 레퍼런스와 CView 적용안

### 6.1 Raycast / Spotlight형 Command Home

적용 대상:

- 홈 상단 검색
- 빠른 이동
- 채널/라이브/클립 통합 검색

특징:

- 큰 검색 필드
- 키보드 중심
- 결과 리스트와 미리보기 패널
- 미세한 surface stack과 border

CView 적용:

- `SearchViews.swift`에 이미 "Spotlight/Raycast 스타일 검색" 주석과 구현이 있다.
- 홈은 검색 결과 전체를 품기보다 `CommandPaletteView` 또는 `SearchView` 진입점으로 쓰는 것이 유지보수에 좋다.

### 6.2 YouTube / Twitch형 Media Feed

적용 대상:

- 인기 라이브
- 추천 라이브
- 카테고리별 라이브 카드

특징:

- 16:9 썸네일 중심
- LIVE badge, viewer count, duration badge
- 채널 아바타와 제목 2줄
- hover 시 썸네일 확대와 액션 노출

CView 적용:

- `FollowingLiveCard`의 썸네일, LIVE badge, viewer count 자산을 홈 카드에도 통합한다.
- 현재 홈의 `MiniChannelCard`는 compact 용도로 남기고, 첫 화면 추천 카드에는 더 큰 media card가 필요하다.

### 6.3 Linear / Notion형 Dense Workspace

적용 대상:

- 홈 하단 통계
- 메트릭 서버
- 상태 요약

특징:

- 장식보다 정보 위계
- 작은 typography
- chip, status dot, compact table
- section header와 command button 중심

CView 적용:

- 통계 영역은 대형 차트보다 compact insight row와 접이식 detail이 어울린다.
- `DashboardStatCard`는 유지하되 첫 화면 우선순위를 낮춘다.

### 6.4 macOS Native Sidebar + Toolbar

적용 대상:

- 앱 전체 내비게이션
- 홈 상단 액션 배치

Apple HIG 참고:

- [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars): 사이드바는 앱 정보 구조와 주요 영역 접근에 적합하지만, 공간이 좁을 때는 더 compact한 컨트롤이 필요하다. macOS에서는 사이드바 자동 숨김/표시와 사용자 커스터마이즈를 고려하라고 설명한다.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): 툴바는 자주 쓰는 명령, 탐색, 검색을 제공하는 곳이며, 너무 많은 항목을 넣지 말고 기능과 빈도 기준으로 그룹화하라고 안내한다.

CView 적용:

- 현재 `NavigationSplitView` 기반 사이드바는 유지한다.
- 홈 안에는 중복 사이드바를 만들지 않는다.
- 상단 command bar는 검색, 새로고침, 멀티라이브, 보기 옵션 정도로 제한한다.
- 세부 기능은 사이드바/메뉴/command palette로 연결한다.

### 6.5 Apple TV / Music형 Editorial Hero는 제한적으로만 사용

대형 히어로는 예쁘지만 CView 홈에는 과하면 안 된다. 앱의 목적이 "반복적으로 라이브를 찾고 실행하는 도구"이기 때문이다.

적합한 방식:

- 대형 배경 이미지를 쓰는 마케팅형 hero는 피한다.
- 대신 "대표 추천 라이브 1개"를 media hero card로 둔다.
- 텍스트는 짧게, 액션은 명확하게 둔다.

---

## 7. 권장 홈 와이어프레임

### 7.1 Wide macOS Window

```text
┌────────────────────────────────────────────────────────────────────────────┐
│  CView Home                                      [검색________________] [↻] │
│                                                                            │
│  ┌──────────────────────────────┐  ┌────────────────────────────────────┐  │
│  │ 대표 추천 라이브              │  │ 지금 라이브 중인 팔로잉             │  │
│  │ 16:9 thumbnail                │  │ ○ channel  title  viewers   [▶][+] │  │
│  │ LIVE  12.4K  category         │  │ ○ channel  title  viewers   [▶][+] │  │
│  │ title                         │  │ ○ channel  title  viewers   [▶][+] │  │
│  │ [재생] [멀티라이브 추가]       │  │ [전체 팔로잉 보기]                 │  │
│  └──────────────────────────────┘  └────────────────────────────────────┘  │
│                                                                            │
│  최근 시청                         즐겨찾기                                │
│  [card][card][card][card]           [card][card][card][card]                │
│                                                                            │
│  탐색                                                                    │
│  [전체][게임][토크][스포츠][음악]                                          │
│  [live card] [live card] [live card] [live card]                            │
│                                                                            │
│  요약  라이브 1,234  총 시청자 12.3만  상위 카테고리 게임/토크/스포츠       │
└────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Compact Window

```text
┌──────────────────────────────┐
│ [검색____________________] [↻]│
│ 지금 볼 만한 방송             │
│ [대표 라이브 카드]             │
│ 팔로잉 라이브                 │
│ [horizontal cards...]         │
│ 최근 시청                     │
│ [list rows...]                │
│ 인기 라이브                   │
│ [2-column cards...]           │
└──────────────────────────────┘
```

---

## 8. 디자인 시스템 적용 가이드

### 8.1 유지할 것

- `DesignTokens.Colors.background/surfaceBase/surfaceElevated/surfaceOverlay`의 4-layer stack
- `DesignTokens.Colors.chzzkGreen` 단일 브랜드 accent
- `ViewThatFits`, adaptive grid, cache-first rendering
- `LiveThumbnailView` 기반 썸네일 갱신
- `motionSafe`와 spring 기반 animation

### 8.2 줄일 것

- 홈 상단에서 차트와 대시보드 카드 과다 노출
- `.fill.quaternary` 직접 배경 반복
- 텍스트 버튼 위주의 "전체보기"
- 작은 숫자 통계의 과도한 강조
- 첫 화면 안에서 비슷한 mini stat/card 반복

### 8.3 새로 만들 공용 컴포넌트 후보

| 컴포넌트 | 역할 |
|---|---|
| `HomeCommandBar` | 검색, 새로고침, 멀티라이브, 보기 옵션 |
| `HomeHeroLiveCard` | 대표 추천 라이브 대형 카드 |
| `LiveRailSection` | 팔로잉/추천/인기 레일 공통 |
| `CompactChannelStrip` | 최근/즐겨찾기 compact row |
| `HomeInsightStrip` | 통계 요약 row |
| `LiveCardActionMenu` | 재생/멀티라이브/상세/즐겨찾기 공통 액션 |

---

## 9. 구현 로드맵

### Phase 1. 홈 정보 구조 재배치

목표: 코드 변경 최소로 홈 첫 화면의 우선순위를 바꾼다.

작업:

1. `HomeView` 섹션 순서를 `CommandBar -> Personal Live -> Recent/Favorites -> Discover -> Compact Insights`로 변경
2. 기존 `statCardsGrid`, `chartsSection`, `analyticsSection`은 하단 `Insights`로 이동
3. `personalStatsSection`을 상단 카드/레일 형태로 리디자인
4. `topChannelsSection`을 media card 중심으로 확대

검증:

- 로그인/미로그인/쿠키 필요 상태
- 캐시 있음/없음
- 메트릭 서버 온라인/오프라인
- 좁은 창/넓은 창

### Phase 2. 홈 전용 카드와 액션 통합

목표: 홈에서 바로 재생/멀티라이브/상세 이동을 가능하게 한다.

작업:

1. `HomeHeroLiveCard` 추가
2. `LiveCardActionMenu` 추가
3. `RecentFavoritesView`의 데이터 로딩 일부를 홈에서 재사용 가능한 helper로 분리
4. 카드 hover 시 `triggerPrefetch(channelId:)` 유지

검증:

- hover prefetch가 과도하게 호출되지 않는지 확인
- 카드 클릭과 버튼 클릭 충돌 방지
- VoiceOver label과 help tooltip

### Phase 3. 추천 로직

목표: rule-based 개인화 추천을 제공한다.

작업:

1. `HomeViewModel`에 `homeRecommendations` 계산 프로퍼티 또는 별도 service 추가
2. 즐겨찾기/최근시청/팔로잉/카테고리 기반 score 적용
3. 이미 재생 중인 채널 제외
4. 추천 결과 fallback: `topChannels`

검증:

- 데이터가 적은 신규 사용자
- 로그아웃 사용자
- 팔로잉이 모두 오프라인인 사용자

### Phase 4. 홈 편집과 섹션 개인화

목표: 고급 사용자에게 홈 밀도와 섹션 순서를 제공한다.

작업:

1. `HomeLayoutSettings` 추가
2. 섹션 표시/숨김 저장
3. compact/comfortable 카드 밀도 설정
4. 메트릭/통계 섹션 기본 접힘 설정

---

## 10. 리스크와 주의점

| 리스크 | 설명 | 대응 |
|---|---|---|
| 홈이 다시 과밀해질 위험 | 기능을 많이 올리면 현재 대시보드 과밀 문제가 반복됨 | 첫 화면은 "행동", 하단은 "분석"으로 분리 |
| API 호출 증가 | 최근/즐겨찾기 live status, 추천 계산으로 호출이 늘 수 있음 | 기존 `liveChannels`와 캐시 우선 사용 |
| 카드 액션 충돌 | 카드 전체 클릭, hover 버튼, context menu가 겹칠 수 있음 | 클릭 영역과 버튼 영역 분리 |
| 멀티라이브 진입 과노출 | 초보 사용자에게 부담 가능 | primary CTA는 하나만, 카드별 `+`는 hover에서만 노출 |
| 디자인 시스템 파편화 | 홈 전용 컴포넌트가 중복될 수 있음 | `LiveRailSection`, `LiveCardActionMenu` 등 공용화 |

---

## 11. 최종 추천안

홈 개편의 핵심은 "예쁜 대시보드"가 아니라 "실제로 매일 쓰는 라이브 시작 화면"을 만드는 것이다.

최종 형태는 다음을 권장한다.

1. 상단: Raycast형 검색 + 새로고침 + 멀티라이브 시작
2. 첫 영역: 대표 추천 라이브 + 팔로잉 라이브 compact list
3. 두 번째 영역: 최근 시청 + 즐겨찾기
4. 세 번째 영역: 인기/카테고리/추천 라이브 media grid
5. 하단: 접이식 통계/메트릭 summary

이 방향이면 기존 `HomeViewModel`의 캐시/자동 갱신/통계 계산 자산을 유지하면서도, 사용자가 앱을 열었을 때 바로 "볼 것"과 "할 것"이 보이는 홈으로 전환할 수 있다.

# 라이브 메뉴 UI/UX 정밀 분석 및 개선안

> CView_v2 — 2026.03.31 기준 · 분석 대상: `FollowingView` 및 하위 컴포넌트 전체

---

## 1. 현재 구조 요약

### 뷰 계층

```
FollowingView (메인)
├── headerSection              — 타이틀 · 통계 배지 · 액션 버튼
├── searchFilterCard           — 검색바 · 전체/라이브 세그먼트
├── categoryFilterChips        — 카테고리 가로 스크롤 칩
├── livePagingView             — LazyVGrid (반응형 컬럼)
│   └── FollowingLiveCard      — 16:9 썸네일 + 정보 바
├── offlinePagingView          — LazyVStack 행 리스트
│   └── FollowingOfflineRow    — 프로필 + 이름 + 상태
├── multiLiveInlinePanel       — 멀티라이브 사이드 패널
└── multiChatInlinePanel       — 멀티채팅 사이드 패널
```

### 진입 경로

| 경로 | 동작 |
|------|------|
| 사이드바 "라이브" (♥ heart.fill) | `FollowingView` 표시 |
| 라이브 카드 클릭 | `LiveStreamView(channelId:)` 네비게이션 |
| 호버 → "멀티라이브" 버튼 | `MultiLiveManager.addSession` → 사이드 패널 |
| 오프라인 행 클릭 | `ChannelInfoView` 채널 상세 |

---

## 2. 강점 (현재 잘 되어 있는 점)

| # | 항목 | 상세 |
|---|------|------|
| ✅ 1 | **반응형 그리드** | `ResponsiveFollowingLayout` 4단계 SizeClass 기반 컬럼·간격·폰트 자동 조정 |
| ✅ 2 | **영속 상태** | `FollowingViewState` → 메뉴 전환 후 돌아와도 정렬·필터·페이지·패널 상태 유지 |
| ✅ 3 | **스켈레톤 로딩** | 첫 로드 시 shimmer 카드 8장 + stagger 애니메이션으로 체감 속도 향상 |
| ✅ 4 | **호버 프리페치** | 카드 hover 시 `hlsPrefetchService.prefetch` → 클릭 시 ~400ms 단축 |
| ✅ 5 | **마이크로 인터랙션** | cardHover spring, scale 1.02, border 발광, stagger 등장 — 일관된 모션 언어 |
| ✅ 6 | **멀티라이브/멀티채팅 통합** | 분리 창 없이 사이드 패널로 통합, 듀얼 분할 비율 드래그 조절 |
| ✅ 7 | **45초 썸네일 갱신** | `LiveThumbnailService` 백그라운드 정지/복귀 자동 관리 |
| ✅ 8 | **카테고리 칩 필터** | 라이브 카테고리별 카운트 표시 + 가로 스크롤 마스크 |
| ✅ 9 | **컨텍스트 메뉴 알림** | 채널별 알림 설정 (방송 시작·카테고리·제목 변경) |

---

## 3. 발견된 UX 이슈 (20건)

### 3.1 내비게이션 & 정보 구조

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| N-1 | 🔴 High | **카드 클릭 목적지 혼동** | 카드 클릭 → `LiveStreamView` (시청), 호버 힌트는 "클릭: 채널 보기" | 힌트 문구와 실제 동작 불일치 — 사용자가 채널 상세가 열릴 것으로 기대 |
| N-2 | 🟡 Med | **단일 클릭 경로만 존재** | 카드 탭 = 스트림 시청 고정 | 채널 상세 보기 경로 없음 (컨텍스트 메뉴에도 없음, 오프라인은 가능) |
| N-3 | 🟡 Med | **사이드바 아이콘 의미 불일치** | `heart.fill` (♥) = "라이브" 메뉴 | ♥는 "즐겨찾기/좋아요" 의미, 라이브 방송 목록에는 `antenna.radiowaves.left.and.right` 등이 적합 |
| N-4 | 🟢 Low | **페이지네이션 키보드 미지원** | 좌/우 화살표 버튼만 동작 | ← → 키보드, 스크롤 페이지 전환 불가 |

### 3.2 검색 & 필터링

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| F-1 | 🔴 High | **검색이 채널명만 매칭** | `localizedCaseInsensitiveContains(channelName)` | 방송 제목·카테고리로 검색 불가 — "배그" 검색해도 PUBG 방송 안 나옴 |
| F-2 | 🟡 Med | **카테고리 칩 다량 시 UX 열화** | 가로 스크롤 단일 행 | 10개+ 카테고리 시 끝까지 스크롤 필요, 현위치 파악 어려움 |
| F-3 | 🟡 Med | **정렬 옵션 접근성** | 툴바 메뉴 버튼 (앱 우상단) | 사용 빈도 대비 접근 동선 김 — 검색/필터 카드 권역에 통합하는 것이 자연스러움 |
| F-4 | 🟢 Low | **필터 상태 시각 피드백 부족** | "라이브" 필터 ON이면 오프라인 단순 숨김 | 필터 적용 중임을 상시 표시하는 배지/라벨 없음 |

### 3.3 라이브 카드 디자인

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| C-1 | 🟡 Med | **방송 제목 1줄 잘림** | `lineLimit(1)` — 긴 제목 말줄임 | 제목 전문 확인 불가, 툴팁 없음 |
| C-2 | 🟡 Med | **호버 오버레이가 정보 차단** | 호버 시 검정 40% + "멀티라이브" 버튼만 표시 | 썸네일 내 배지(시청자수·업타임·제목)가 완전히 가려져 호버 상태에서 정보 확인 불가 |
| C-3 | 🟢 Low | **업타임 배지 폰트 과소** | `clock.fill` 6pt + 텍스트 8pt | 사실상 읽기 어려움, 특히 작은 카드에서 |
| C-4 | 🟢 Low | **카드 등장 stagger 누적** | `delay(index * 0.04)` — 페이지 내 index 고정 | 12장 카드 시 마지막 카드 480ms 후 등장 — 첫 페이지 이후에도 매번 적용 |

### 3.4 오프라인 섹션

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| O-1 | 🟡 Med | **오프라인 행 고정 높이 44pt** | `offlinePageHeight` 계산에 `rowHeight: 44` 하드코딩 | `ResponsiveFollowingLayout.offlineRowHeight`와 정합 불일치 가능 (ultraCompact=34, compact=38) |
| O-2 | 🟢 Low | **오프라인 grayscale 과도** | `grayscale(0.5) + opacity(0.5)` | 시각 대비 부족으로 읽기 어려움, 접근성(WCAG) 기준 미달 가능 |

### 3.5 멀티라이브/멀티채팅 패널

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| M-1 | 🟡 Med | **패널 초기 상태 `hideFollowingList = true`** | 멀티라이브 열면 팔로잉 목록 기본 숨김 | 추가 채널을 선택하려면 목록 토글을 먼저 찾아야 함 — 발견성 낮음 |
| M-2 | 🟡 Med | **듀얼 패널 분할 핸들 작음** | `Capsule(3x28)` — 3pt 너비 | 마우스 정밀 조작 필요, 발견성 매우 낮음 |
| M-3 | 🟢 Low | **멀티라이브 세션 수 제한 표시 없음** | 최대 4개까지, 가득 차면 비활성 | 몇 개 남았는지 시각적 힌트 없음 |

### 3.6 성능 & 기술

| # | 심각도 | 이슈 | 현재 동작 | 영향 |
|---|--------|------|-----------|------|
| P-1 | 🟡 Med | **페이지 전환 시 전체 그리드 리드로** | `.id(livePageIndex)` → 전체 재생성 | transition + drawingGroup이 완화하지만, 카드 객체 매번 새로 생성 |
| P-2 | 🟢 Low | **recomputeFiltered 연쇄 호출** | `onChange(of: followingChannels)` + `onChange(of: sortOrder)` + … | 초기 로드 시 channels 변경 → sortOrder 감지 등으로 다중 호출 가능 |

---

## 4. 개선안 (우선순위별)

### 🔴 Priority 1 — 즉시 개선 (사용자 혼동·기능 결함)

#### [N-1] 카드 클릭 힌트 문구 수정 + 채널 상세 경로 추가

**현재:**
```swift
// FollowingCardViews.swift infoArea
if isHovered {
    Text("클릭: 채널 보기")
}
```
**개선안:**
- 힌트 문구를 **"클릭: 방송 보기"** 로 수정 (실제 동작과 일치)
- 프로필 아바타 영역에 별도 탭 제스처 추가 → 채널 상세 이동
- 또는 우클릭 컨텍스트 메뉴에 **"채널 정보 보기"** 항목 추가

```
카드 클릭     → LiveStreamView (시청)
프로필 클릭   → ChannelInfoView (채널 상세)  [신규]
우클릭       → 컨텍스트 메뉴 + "채널 정보" 항목  [신규]
```

#### [F-1] 검색 범위 확장 — 방송 제목·카테고리 포함

**현재:**
```swift
channels.filter { $0.channelName.localizedCaseInsensitiveContains(searchText) }
```
**개선안:**
```swift
channels.filter { ch in
    ch.channelName.localizedCaseInsensitiveContains(searchText)
    || ch.liveTitle.localizedCaseInsensitiveContains(searchText)
    || (ch.categoryName ?? "").localizedCaseInsensitiveContains(searchText)
}
```
- 검색바 placeholder를 **"채널, 방송 제목, 카테고리 검색..."** 으로 변경
- 매칭 필드 하이라이트 표시 (선택적)

---

### 🟡 Priority 2 — 단기 개선 (UX 품질)

#### [C-2] 호버 오버레이 정보 보존

**문제:** 호버 시 모든 배지가 검정 오버레이에 가려짐

**개선안 A — 오버레이 영역 축소:**
```
현재: 전체 썸네일 100% 블랙 40%
개선: 하단 40%만 그라디언트 + 멀티라이브 버튼을 하단 중앙에 배치
      상단 배지(시청자수, 업타임)는 항상 노출
```

**개선안 B — 오버레이 투명도 조정:**
```
현재: Color.black.opacity(0.4)
개선: Color.black.opacity(0.2) + blur(radius: 2)
      버튼을 더 진한 배경 Capsule로 강조
```

#### [O-1] 오프라인 행 높이 하드코딩 제거

**현재:**
```swift
// FollowingView+List.swift offlinePageHeight
let rowHeight: CGFloat = 44
```
**개선안:**
```swift
let rowHeight: CGFloat = layout.offlineRowHeight
```

#### [C-1] 방송 제목 툴팁 추가

```swift
Text(channel.liveTitle)
    .lineLimit(1)
    .help(channel.liveTitle)  // macOS 네이티브 툴팁
```

#### [F-3] 정렬 옵션을 검색/필터 카드 영역에 통합

```
현재 위치: 앱 우상단 툴바 메뉴 (사이드바 너머)
개선 위치: 검색 바 오른쪽 또는 카테고리 칩 행 끝에 Picker/Popup 배치
```
정렬 변경 빈도가 높은 기능을 컨텐츠 영역 내에 배치하여 시선 이동 최소화

#### [M-2] 분할 핸들 발견성 개선

```swift
// 현재: Capsule(3x28)
// 개선: 호버 시 너비 확장 + 색상 강조
Capsule()
    .fill(isHandleHovered ? Colors.chzzkGreen.opacity(0.6) : Colors.textTertiary.opacity(0.3))
    .frame(width: isHandleHovered ? 5 : 3, height: 36)
    .animation(.micro, value: isHandleHovered)
```

#### [M-1] 멀티라이브 시 팔로잉 목록 기본 표시

```swift
// FollowingViewState 초기값 변경
var hideFollowingList: Bool = false  // true → false
```
또는: 멀티라이브 최초 활성화 시 3초간 목록 표시 후 배너로 토글 안내

#### [C-4] 페이지 전환 후 stagger 비활성화

```swift
// 첫 등장 이후에는 stagger delay 제거
.onAppear {
    if !appeared {
        let delay = isFirstPageLoad ? Double(index) * 0.04 : 0
        withAnimation(Animation.cardAppear.delay(delay)) { appeared = true }
    }
}
```

#### [N-2] 라이브 카드 컨텍스트 메뉴에 "채널 정보" 추가

```swift
.contextMenu {
    Button {
        router.navigate(to: .channelDetail(channelId: channel.channelId))
    } label: {
        Label("채널 정보 보기", systemImage: "person.crop.circle")
    }
    // 기존 멀티라이브 + 알림 메뉴 ...
}
```

---

### 🟢 Priority 3 — 중장기 개선 (완성도)

#### [F-2] 카테고리 칩 2행 접히기 또는 드롭다운

10개 초과 시 "▾ 더보기" 버튼으로 전환하거나, 2행까지 wrap 레이아웃 적용

#### [N-4] 페이지네이션 키보드 지원

```swift
.onKeyPress(.leftArrow) {
    if livePageIndex > 0 {
        withAnimation(.snappy) { livePageIndex -= 1 }
    }
    return .handled
}
.onKeyPress(.rightArrow) { ... }
```

#### [O-2] 오프라인 접근성 개선

```swift
// 현재: grayscale(0.5) + opacity(0.5) → 합산 대비 매우 낮음
// 개선: grayscale(0.3) + opacity(0.65) — WCAG AA 기준 4.5:1 충족 목표
```

#### [C-3] 업타임 배지 가독성

```swift
// 현재: clock 6pt, text 8pt
// 개선: clock 8pt, text 9.5pt — 최소 탭 타겟과 무관하게 가독성 확보
```

#### [M-3] 멀티라이브 슬롯 카운터

헤더 멀티라이브 버튼에 `sessions.count / maxSessions` 표시:
```
[▦ 멀티라이브 2/4]
```

#### [F-4] 필터 활성 상태 배지

검색 바 옆에 활성 필터 수 배지 표시:
```
[🔍 채널 검색...]  [필터 2개 적용 ✕]
```
클릭 시 모든 필터 초기화

#### [N-3] 사이드바 아이콘 개선 (선택적)

```
현재: heart.fill (♥) — "라이브" 메뉴
제안: antenna.radiowaves.left.and.right — 방송 송출 의미
대안: play.tv.fill — TV 시청 의미
```
※ 기존 사용자 습관이 있으므로 변경 시 주의 필요

---

## 5. 개선 영향도 매트릭스

```
          난이도 →  낮음          중간          높음
  ──────────────────────────────────────────────
  영  ↑   높음 │ N-1 힌트수정   F-1 검색확장    P-1 가상화
  향       │ O-1 높이수정   C-2 오버레이     N-2 채널상세
  도       │ C-1 툴팁       M-1 기본표시
  │  ──────────────────────────────────────────────
       중간 │ C-4 stagger   F-3 정렬통합     F-2 칩접기
           │ M-2 핸들       M-3 슬롯표시     N-4 키보드
  │  ──────────────────────────────────────────────
  ↓   낮음 │ C-3 업타임     O-2 접근성       N-3 아이콘
           │ F-4 필터배지
```

---

## 6. 권장 실행 순서

| 단계 | 항목 | 예상 변경 파일 |
|------|------|----------------|
| **1단계** | N-1 힌트 수정 | `FollowingCardViews.swift` |
| | F-1 검색 확장 | `FollowingView.swift` (recomputeFiltered) |
| | O-1 높이 수정 | `FollowingView+List.swift` |
| | C-1 제목 툴팁 | `FollowingCardViews.swift` |
| **2단계** | C-2 오버레이 개선 | `FollowingCardViews.swift` |
| | N-2 채널정보 메뉴 | `FollowingView+List.swift` |
| | F-3 정렬 통합 | `FollowingView+Header.swift` |
| | M-1 목록 기본 표시 | `FollowingViewState.swift` |
| | M-2 핸들 개선 | `FollowingView.swift` |
| **3단계** | C-4 stagger 최적화 | `FollowingCardViews.swift` |
| | M-3 슬롯 카운터 | `FollowingView+Header.swift` |
| | 나머지 P3 항목들 | 각 해당 파일 |

---

## 7. 참고: 현재 디자인 토큰 맵

| 용도 | 토큰 | 값 |
|------|------|-----|
| 카드 코너 | `Radius.lg` | 16pt |
| 오프라인 행 코너 | `Radius.md` | 12pt |
| 그리드 간격 | `gridSpacing` | 4~16pt (SizeClass별) |
| 카드 scale (hover) | — | 1.02 |
| 카드 등장 | `cardAppear` | spring(stiffness:300, damping:24) |
| 페이지 전환 | `gridPageTransition` | spring(stiffness:200, damping:22) |
| 썸네일 갱신 주기 | — | 45초 |
| 자동 새로고침 주기 | — | 90초 |
| 검색 디바운스 | — | 200ms |
| 캐시 유효 시간 | — | 300초 (5분) |

---

## 8. 개선 이력

### Round 1 (커밋 bee4738)
15개 항목 적용: N-1, N-2, N-4, F-1, F-4, C-1, C-2, C-3, C-4, O-1, O-2, M-1, M-2, M-3, 검색 placeholder

### Round 2
9개 항목 적용:

| ID | 항목 | 변경 파일 |
|-----|------|-----------|
| F-3 | 정렬 메뉴를 toolbar에서 searchAndFilterCard로 통합 | `FollowingView.swift`, `FollowingView+Header.swift` |
| F-2 | 카테고리 칩 8개 초과 시 "+N 더보기" 메뉴로 전환 | `FollowingView+List.swift` |
| ML-1 | 멀티채팅 전체 해제 시 확인 다이얼로그 추가 | `FollowingView.swift`, `FollowingView+MultiChat.swift` |
| ML-2 | 채팅 탭 닫기 버튼 7pt/14×14 → 9pt/18×18 히트 타겟 확대 | `FollowingView+MultiChat.swift` |
| ML-3 | MLControlOverlay(포커스 모드)에 볼륨 슬라이더 추가 | `MultiLiveOverlays.swift` |
| ML-4 | 방송 종료 오버레이 하드코딩 색상 → DesignTokens로 교체 | `LiveStreamView.swift` |
| ML-5 | 멀티라이브 그리드 호버 시 "더블클릭: 확대" 힌트 표시 | `MultiLiveOverlays.swift` |
| ML-6 | 멀티채팅 스와이프 숨기기에 드래그 피드백(오프셋+투명도) 추가 | `FollowingView+MultiChat.swift`, `FollowingView.swift` |
| ML-7 | MLAddChannelPanel에 Escape 키 닫기 핸들러 추가 | `MultiLiveOverlays.swift` |

### 잔여 항목
| ID | 항목 | 비고 |
|-----|------|------|
| N-3 | 사이드바 아이콘 변경 | 선택적 — 사용자 습관 변경 위험 |
| P-1 | 페이지 전환 시 전체 그리드 리드로(가상화) | 높은 복잡도 |
| P-2 | recomputeFiltered 연쇄 호출 최적화 | 성능 프로파일링 필요 |

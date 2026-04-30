# 화면 크기 조절 개선안 분석

> CView_v2 — 멀티라이브 · 멀티채팅 · 팔로잉 화면 리사이즈 UX 개선

---

## 목차

1. [현황 분석](#1-현황-분석)
2. [문제점 정리](#2-문제점-정리)
3. [개선안](#3-개선안)
4. [구현 우선순위](#4-구현-우선순위)

---

## 1. 현황 분석

### 1.1 전체 레이아웃 구조

```
┌─ MainContentView (NavigationSplitView) ──────────────────────────────┐
│ ┌──────────┐ ┌─────────────────────────────────────────────────────┐ │
│ │ Sidebar  │ │ FollowingView (GeometryReader)                     │ │
│ │          │ │ ┌───────────────┬─┬──────────────┐                 │ │
│ │ · 홈     │ │ │ 사이드 패널   │÷│ 팔로잉 리스트 │                 │ │
│ │ · 라이브 │ │ │ (멀티라이브   │÷│ (채널 목록)   │                 │ │
│ │ · 카테   │ │ │  또는         │÷│              │                 │ │
│ │ · 검색   │ │ │  멀티채팅)    │÷│              │                 │ │
│ │          │ │ └───────────────┴─┴──────────────┘                 │ │
│ └──────────┘ └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                              ↑                 ↑
                   followingListDivider    following list width
```

**듀얼 패널 모드** (멀티라이브 + 멀티채팅 동시):
```
┌─────────────────────────────────────────────┐
│ ┌──────────────┬─┬──────────────┬─┬────────┐│
│ │ 멀티라이브   │÷│ 멀티채팅     │÷│팔로잉  ││
│ │ (60% 기본)   │÷│ (40% 기본)   │÷│리스트  ││
│ └──────────────┴─┴──────────────┴─┴────────┘│
└─────────────────────────────────────────────┘
        ↑ dualPanelSplitRatio        ↑ followingListWidth
```

### 1.2 윈도우 크기

| 윈도우 | 기본 크기 | 최소 크기 | 비고 |
|--------|-----------|-----------|------|
| 메인 | 1200×800 | 900×600 | `hiddenTitleBar` 스타일 |
| 플레이어 | 960×600 | 제한 없음 | 분리 윈도우 |
| 멀티채팅 | 700×550 | 500×400 | 독립 윈도우 |
| 채팅 | 360×600 | 제한 없음 | 팝업 |

### 1.3 패널 크기 상태 관리 (`FollowingViewState`)

| 프로퍼티 | 기본값 | 용도 | 디스크 저장 |
|---------|--------|------|------------|
| `followingListWidth` | **480pt** | 팔로잉 리스트 폭 | ❌ 없음 |
| `dualPanelSplitRatio` | **0.6** | 멀티라이브:채팅 비율 | ❌ 없음 |
| `mlPanelWidth` | **560pt** | (미사용) | ❌ 없음 |
| `hideFollowingList` | `true` | 팔로잉 숨김 토글 | ❌ 없음 |

> ⚠️ **모든 크기 값이 앱 재시작 시 초기화됨** — UserDefaults/디스크 저장 미구현

### 1.4 디바이더(리사이즈 핸들) 현황

#### A. 팔로잉 리스트 디바이더

| 항목 | 현재 값 |
|------|---------|
| 위치 | 사이드 패널 ↔ 팔로잉 리스트 경계 |
| 최소 폭 | **240pt** (하드코딩) |
| 최대 폭 | **전체 너비 × 0.45** |
| 드래그 방식 | `DragGesture` + `@GestureState` |
| 시각 피드백 | 1pt → 5pt, 색상 chzzkGreen |
| 커서 변경 | `NSCursor.resizeLeftRight` |
| 히트 영역 | ±4pt |

#### B. 듀얼 패널 디바이더 (멀티라이브 ↔ 멀티채팅)

| 항목 | 현재 값 |
|------|---------|
| 위치 | 멀티라이브 ↔ 멀티채팅 경계 |
| 최소 비율 | **0.25** (25%) |
| 최대 비율 | **0.75** (75%) |
| 드래그 방식 | `DragGesture` + `@GestureState` |
| 시각 피드백 | 캡슐 핸들(3×28), 고정 색상 |
| 커서 변경 | `NSCursor.resizeLeftRight` |
| 히트 영역 | ±4pt |

#### C. 멀티라이브 내부 디바이더 (`MLResizeDivider`)

| 항목 | 현재 값 |
|------|---------|
| 위치 | 커스텀 그리드 내 스트림 간 |
| 최소 비율 | **0.2** (20%) |
| 최대 비율 | **0.8** (80%) |
| 방향 | 수평/수직 (레이아웃에 따라) |
| 시각 피드백 | Glass.dividerColor → chzzkGreen |
| 히트 영역 | ±6pt |
| 저장 | ✅ UserDefaults (`MultiLivePersistedState`) |

#### D. 멀티채팅 사이드바 (HSplitView)

| 항목 | 현재 값 |
|------|---------|
| 위치 | 채널 목록 ↔ 채팅 콘텐츠 |
| 최소 폭 | **160pt** |
| 최대 폭 | **220pt** |
| 구현 | 시스템 `HSplitView` |
| 저장 | ❌ 없음 |

### 1.5 반응형 레이아웃 (`ResponsiveFollowingLayout`)

팔로잉 리스트 영역의 너비에 따라 4단계 SizeClass 적용:

| 클래스 | 너비 범위 | 라이브 열 수 | 라이브 열 Min–Max | 페이지당 행 |
|--------|-----------|-------------|-------------------|------------|
| ultraCompact | < 400pt | 1열 | 280–500pt | 4행 |
| compact | 400–599pt | 2열+ | 200–340pt | 3행 |
| regular | 600–999pt | 2열+ | 260–400pt | 4행 |
| expanded | ≥ 1000pt | 2열+ | 300–440pt | 4행 |

---

## 2. 문제점 정리

### 🔴 심각 (High)

#### H1. 패널 크기가 앱 재시작 시 초기화

`followingListWidth`, `dualPanelSplitRatio`가 디스크에 저장되지 않아 매번 기본값(480pt, 0.6)으로 복귀. 사용자가 리사이즈한 레이아웃이 유지되지 않음.

**영향**: 매번 수동으로 재조정해야 하는 UX 불편

#### H2. 팔로잉 리스트 최소 폭의 사이드 패널 압박

팔로잉 리스트 최소 폭 240pt + 최대 비율 0.45가 동시에 적용되어, 작은 윈도우에서 사이드 패널(멀티라이브/채팅)이 지나치게 좁아질 수 있음.

- 메인 윈도우 최소폭 900pt, NavigationSplitView 사이드바 ~200pt
- 남은 ~700pt에서 팔로잉 리스트 240pt 사용 → 사이드 패널 ~460pt
- 듀얼 패널(멀티라이브+채팅) 시 460pt를 0.6:0.4로 분할 → 276pt:184pt
- **184pt 멀티채팅 패널은 실질적으로 사용 불가**

#### H3. 사이드 패널에 최소 폭 제약 없음

사이드 패널(멀티라이브/멀티채팅 영역)에 `minWidth` 없음. 팔로잉 리스트를 최대로 넓히면 사이드 패널이 0에 가까워질 수 있음.

### 🟡 보통 (Medium)

#### M1. 듀얼 패널 디바이더 시각 피드백 미흡

팔로잉 리스트 디바이더는 드래그 시 색상·크기 변화가 있지만, 듀얼 패널 디바이더(멀티라이브↔채팅)는 드래그 시 시각 변화가 없음(고정 캡슐 핸들).

**영향**: 사용자가 드래그 가능 여부를 인지하기 어려움

#### M2. 디바이더 히트 영역 불일치

| 디바이더 | 히트 영역 |
|---------|-----------|
| 팔로잉 리스트 | ±4pt |
| 듀얼 패널 | ±4pt |
| ML 내부 | ±6pt |

일관되지 않은 히트 영역. ML 내부 디바이더(±6pt)가 더 넓어 사용감 차이 발생.

#### M3. 멀티채팅 그리드 모드 고정 분할

멀티채팅 그리드 모드에서 셀 크기를 사용자가 조절할 수 없음. `LazyVGrid`의 `.flexible()` 컬럼으로 균등 분할만 가능.

#### M4. 팔로잉 리스트 디바이더의 반대 방향 계산

```swift
followingListWidth -= value.translation.width  // 왼쪽으로 드래그 → 폭 증가
```

디바이더를 오른쪽으로 드래그하면 팔로잉 리스트가 좁아지고, 왼쪽으로 드래그하면 넓어짐. 직관적이긴 하지만, 드래그 방향과 리사이즈 방향이 반대(뺄셈)라서 코드 유지보수성이 떨어짐.

#### M5. 윈도우 리사이즈 시 패널 비율 미조정

`followingListWidth`가 절대값(px)이므로, 윈도우를 크게 늘려도 팔로잉 리스트 폭은 고정됨. clamp(240, 45%)가 최댓값만 제한하므로, 윈도우가 커지면 사이드 패널이 과도하게 넓어짐.

### 🟢 경미 (Low)

#### L1. `mlPanelWidth` 미사용 프로퍼티

`FollowingViewState.mlPanelWidth = 560`이 선언되어 있지만 `FollowingView`에서 사용되지 않음. 남은 공간을 `maxWidth: .infinity`로 채우는 방식.

#### L2. 멀티채팅 사이드바 폭 범위 과소

`HSplitView`의 채널 사이드바가 160–220pt로 제한. 채널 수가 많을 때 좁음.

#### L3. 더블클릭 리셋 미구현

디바이더를 더블클릭하여 기본값으로 복귀하는 macOS 표준 동작이 없음.

---

## 3. 개선안

### Phase 1: 핵심 UX 개선 (필수)

#### P1-1. 패널 크기 디스크 저장 (H1 해결)

`UserDefaults`에 `followingListWidth`, `dualPanelSplitRatio` 저장.

```
FollowingViewState
  ├─ followingListWidth → UserDefaults "followingListWidth"
  ├─ dualPanelSplitRatio → UserDefaults "dualPanelSplitRatio"
  └─ hideFollowingList → UserDefaults "hideFollowingList"
```

**구현 방식**: `didSet`에서 저장, `init()`에서 복원 (MultiLivePersistedState 방식과 동일)

**예상 작업량**: FollowingViewState.swift 수정

---

#### P1-2. 사이드 패널 최소 폭 제약 추가 (H2, H3 해결)

```
상수:
  sidePanelMinWidth = 400pt   (사이드 패널 전체)
  dualLiveMinWidth  = 300pt   (듀얼 중 멀티라이브)
  dualChatMinWidth  = 200pt   (듀얼 중 멀티채팅)
```

팔로잉 리스트 최대 폭 = `totalWidth - sidePanelMinWidth`로 제한:
```swift
let maxListWidth = totalWidth - sidePanelMinWidth
let clampedListWidth = min(
    max(effectiveListWidth, followingListMinWidth),
    min(totalWidth * followingListMaxRatio, maxListWidth)
)
```

듀얼 패널 비율도 최소 폭 기반으로 제약:
```swift
let minLiveRatio = dualLiveMinWidth / panelWidth
let maxLiveRatio = 1 - (dualChatMinWidth / panelWidth)
let clampedRatio = min(max(effectiveRatio, minLiveRatio), maxLiveRatio)
```

**효과**: 어떤 패널도 사용 불가한 크기로 줄어들지 않음

---

#### P1-3. 디바이더 시각 피드백 통일 (M1 해결)

모든 디바이더에 동일한 3단계 시각 피드백 적용:

| 상태 | 핸들 폭 | 색상 | 커서 |
|------|---------|------|------|
| 기본 | 3pt | textTertiary(0.3) | default |
| 호버 | 4pt | textSecondary(0.5) | resizeLeftRight |
| 드래그 | 5pt | chzzkGreen(0.6) | resizeLeftRight |

**구현**: 공통 `ResizeDivider` 컴포넌트 추출

```
ResizeDivider(
    orientation: .horizontal | .vertical,
    isDragging: Bool,
    onDrag: (CGFloat) -> Void,
    onDragEnd: (CGFloat) -> Void
)
```

---

### Phase 2: 세부 개선

#### P2-1. 더블클릭 리셋 (L3 해결)

디바이더 더블클릭 시 기본값으로 복귀:

| 디바이더 | 기본값 |
|---------|--------|
| 팔로잉 리스트 | 480pt |
| 듀얼 패널 | 0.6 (60:40) |
| ML 내부 | 0.5 (50:50) |

```swift
.onTapGesture(count: 2) {
    withAnimation(DesignTokens.Animation.normal) {
        followingListWidth = 480
    }
}
```

---

#### P2-2. 디바이더 히트 영역 통일 (M2 해결)

모든 디바이더 히트 영역을 **±6pt**로 통일. 현재 ±4pt인 팔로잉·듀얼 디바이더 확대.

---

#### P2-3. 윈도우 리사이즈 시 비례 조정 (M5 해결)

`followingListWidth`를 절대값 대신 **비율 기반**으로 전환:

```
현재: followingListWidth = 480 (절대값)
개선: followingListRatio = 0.4 (총 너비 대비 비율)
```

비율 기반으로 전환하면 윈도우 크기 변경 시 패널들이 자연스럽게 비례 조정됨.

**고려사항**:
- 비율 ↔ 절대값 중 하나를 선택해야 함
- 비율 방식이면 최소 폭을 별도로 보장해야 함
- 절대값 유지 + 윈도우 리사이즈 시 비율 보정도 가능한 접근

**권장**: 비율 기반 전환 + `min()` clamp로 최소 폭 보장

---

#### P2-4. 멀티채팅 그리드 셀 리사이즈 (M3 해결)

그리드 모드 세션 2~4개일 때, ML과 동일한 방식의 `MLResizeDivider` 적용:

- 2개: 수평 디바이더 (좌우 비율)
- 3개: 2+1 레이아웃 + 디바이더
- 4개: 2×2 그리드 + 수평/수직 디바이더

**구현**: `MLCustomGridLayout` 패턴을 `MultiChatView` 그리드 모드에 적용

---

### Phase 3: 고급 기능

#### P3-1. 키보드 숏컷으로 패널 너비 조절

| 단축키 | 동작 |
|--------|------|
| `⌘[` | 팔로잉 리스트 20pt 축소 |
| `⌘]` | 팔로잉 리스트 20pt 확대 |
| `⌘\` | 팔로잉 리스트 토글 |
| `⌥⌘[` | 듀얼 패널 비율 0.05 좌측 이동 |
| `⌥⌘]` | 듀얼 패널 비율 0.05 우측 이동 |

---

#### P3-2. 레이아웃 프리셋

자주 사용하는 레이아웃을 저장/복원:

```
프리셋 예시:
  "채팅 집중" → hideFollowingList=true, showMultiChat=true, dualRatio=0.4
  "모니터링"  → hideFollowingList=false, width=300, dualRatio=0.5
  "라이브 집중" → hideFollowingList=true, showMultiLive=true
```

**구현**: `SettingsStore`에 프리셋 배열 저장, 툴바 메뉴에서 선택

---

#### P3-3. 미사용 프로퍼티 정리 (L1)

`mlPanelWidth` 제거 또는 사이드 패널 최소 폭으로 용도 전환.

---

## 4. 구현 우선순위

| 순위 | 항목 | 해결 문제 | 난이도 | 영향도 |
|------|------|-----------|--------|--------|
| ⭐1 | P1-1 패널 크기 저장 | H1 | 낮음 | 높음 |
| ⭐2 | P1-2 최소 폭 제약 | H2, H3 | 중간 | 높음 |
| ⭐3 | P1-3 디바이더 통일 | M1 | 중간 | 중간 |
| 4 | P2-1 더블클릭 리셋 | L3 | 낮음 | 중간 |
| 5 | P2-2 히트영역 통일 | M2 | 낮음 | 낮음 |
| 6 | P2-3 비율 기반 전환 | M5 | 높음 | 중간 |
| 7 | P2-4 채팅 그리드 리사이즈 | M3 | 높음 | 중간 |
| 8 | P3-1 키보드 숏컷 | — | 낮음 | 낮음 |
| 9 | P3-2 레이아웃 프리셋 | — | 중간 | 낮음 |
| 10 | P3-3 미사용 정리 | L1 | 낮음 | 낮음 |

---

## 부록: 관련 파일 맵

| 파일 | 역할 |
|------|------|
| `Sources/CViewApp/ViewModels/FollowingViewState.swift` | 패널 상태 (크기, 토글) |
| `Sources/CViewApp/Views/FollowingView.swift` (L340–470) | 3패널 레이아웃 + 디바이더 |
| `Sources/CViewApp/Views/FollowingView+MultiLive.swift` | 멀티라이브 인라인 패널 |
| `Sources/CViewApp/Views/FollowingView+MultiChat.swift` | 멀티채팅 인라인 패널 |
| `Sources/CViewApp/Views/MultiLiveView.swift` | 멀티라이브 독립 뷰 |
| `Sources/CViewApp/Views/MultiLiveGridLayouts.swift` | ML 그리드 + MLResizeDivider |
| `Sources/CViewApp/Views/MultiChatView.swift` | 멀티채팅 독립 뷰 (3모드) |
| `Sources/CViewApp/Views/ChatResizeHandle.swift` | 독립 채팅 리사이즈 핸들 |
| `Sources/CViewApp/Views/ResponsiveFollowingLayout.swift` | 반응형 SizeClass 토큰 |
| `Sources/CViewApp/CViewApp.swift` (L50–146) | 윈도우 기본 크기 설정 |
| `Sources/CViewPlayer/MultiLiveSession.swift` (L537–605) | ML 비율 저장 (UserDefaults) |

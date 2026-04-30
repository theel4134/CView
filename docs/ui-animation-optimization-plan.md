# CView_v2 — UI 애니메이션 최적화 계획서

> **작성일**: 2026-04-04  
> **대상**: macOS 26.5 / Apple M1 Max / SwiftUI + Metal 3  
> **분석 범위**: Sources/ 전체 8개 모듈, 229개 Swift 파일  
> **총 애니메이션 인스턴스**: 400+ (animation modifier, transition, spring, 무한반복 등)

---

## 목차

1. [현재 상태 요약](#1-현재-상태-요약)
2. [모듈별 애니메이션 분포](#2-모듈별-애니메이션-분포)
3. [긴급 최적화 대상 (Critical)](#3-긴급-최적화-대상-critical)
4. [높은 우선순위 (High)](#4-높은-우선순위-high)
5. [중간 우선순위 (Medium)](#5-중간-우선순위-medium)
6. [낮은 우선순위 (Low)](#6-낮은-우선순위-low)
7. [이미 적용된 최적화](#7-이미-적용된-최적화)
8. [애니메이션 토큰 시스템 개선 제안](#8-애니메이션-토큰-시스템-개선-제안)
9. [접근성 (Reduce Motion) 준수 현황](#9-접근성-reduce-motion-준수-현황)
10. [단계별 실행 로드맵](#10-단계별-실행-로드맵)

---

## 1. 현재 상태 요약

### 애니메이션 타이밍 분포

| 카테고리 | 사용 횟수 | 응답 시간 | 주요 용도 |
|---------|----------|----------|----------|
| **micro** (14-15ms) | ~45회 | 0.12–0.15s | 아이콘 hover, 버튼 press |
| **fast** (150ms) | ~120회 | 0.14–0.16s | 버튼 토글, 메뉴 전환 |
| **normal** (250ms) | ~95회 | 0.25–0.32s | 패널 열기/닫기, 콘텐츠 전환 |
| **slow** (400ms) | ~30회 | 0.35–0.42s | 모달, 풀스크린 전환 |
| **spring** (커스텀) | ~50회 | 0.35–0.42s | 페이지 전환, 카드 등장 |
| **linear/ease** | ~20회 | 0.16–1.2s | 스피너, 페이드, 펄스 반복 |
| **무한 반복** | 4개 | 1.0–3.0s | 라이브 뱃지, 스피너, 메뉴 펄스 |

### Transition 유형 분포

| 전환 효과 | 사용 횟수 | 위치 |
|----------|----------|------|
| `.opacity` | ~40회 | FollowingView, ChatInput, 리스트 항목 |
| `.move(edge:)` | ~25회 | CategoryBrowse, Following, ErrorRecovery |
| `.move + .opacity (합성)` | ~15회 | 채팅 패널, 멀티라이브 네비게이션 |
| `.scale` | ~8회 | CategoryBrowse, 태그 제거 |
| `.asymmetric` | ~5회 | PlayerControls 품질 메뉴 |
| `.blurReplace()` | ~3회 | StreamLoadingOverlay, MultiLiveOverlays |
| `.matchedGeometryEffect` | ~3회 | ChannelInfo, PopularClips (탭 언더라인) |

### GPU 사용 패턴

| 패턴 | 현재 상태 | 위치 |
|------|----------|------|
| `Canvas` (Metal 3 직접) | 1곳 | PerformanceOverlayView |
| `drawingGroup()` | 1곳 (나머지 제거됨) | MultiLiveOverlays 그라디언트 |
| `compositingGroup()` | 1곳 | StreamAlertOverlayView |
| `.shadow()` (정적) | ~30곳 | 전체 앱 분포 |
| `.shadow()` (hover 애니메이션) | ~12곳 | 카드, 버튼, 오버레이 |

---

## 2. 모듈별 애니메이션 분포

### CViewCore (디자인 시스템)
- **DesignTokens.swift**: 22개 애니메이션 토큰 정의 (L464-520)
- **DesignTokens+Modifiers.swift**: 4개 버튼 스타일 (Primary/Secondary/Tertiary/Icon)
- **역할**: 전체 앱의 애니메이션 기준값 → 여기서 최적화하면 전체 영향

### CViewUI (공유 컴포넌트)
- **CViewUI.swift**: 로딩 스피너 (`rotationEffect` + `loadingSpin`), 펄싱 라이브 뱃지
- **CachedAsyncImage.swift**: 캐시 히트 시 애니메이션 스킵 (이미 최적화)
- **TimelineSlider.swift**: 드래그 기반 오프셋 (제스처 기반)

### CViewApp (메인 앱 — 애니메이션 밀집 구간)

| 파일 | 애니메이션 수 | 핵심 패턴 |
|------|------------|----------|
| **FollowingView.swift** | ~20 | 페이지 전환, 필터 토글, 콘텐츠 전환 |
| **FollowingView+List.swift** | ~15 | 그리드 페이지네이션, 인디케이터, 위젯 카드 |
| **FollowingView+Header.swift** | ~12 | 검색, 정렬, 새로고침 스피너 |
| **FollowingCardViews.swift** | ~8 | 카드 hover, 라이브 아바타 |
| **PlayerControlsView.swift** | ~18 | 오버레이 전환, hover, 녹화 펄스 |
| **MultiLiveOverlays.swift** | ~15 | 컨트롤 show/hide, 그리드 hover, 추가 버튼 |
| **MultiLiveTabBar.swift** | ~12 | 탭 전환, 레이아웃 모드 |
| **CategoryBrowseView.swift** | ~14 | 네비게이션 전환, 스피너, hover |
| **MergedChatView.swift** | ~5 | 채팅 스크롤, 리플레이 배너 |
| **ChatOverlayView.swift** | ~6 | hover, 채팅 스크롤 |
| **StreamLoadingOverlay.swift** | ~6 | 스피너, 페이즈 전환, blurReplace |
| **SharedEffects.swift** | ~3 | 무한반복 펄스 (shimmer, livePulse) |
| **SearchViews.swift** | ~5 | 검색바 포커스, 자동완성 |
| **ChannelInfoView.swift** | ~3 | matchedGeometryEffect 탭 언더라인 |
| **StreamAlertOverlayView.swift** | ~2 | 비동기 전환, compositingGroup 사용 |

### CViewPlayer / CViewChat / CViewAuth / CViewNetworking / CViewPersistence / CViewMonitoring
- UI 애니메이션 코드 없음 (비즈니스 로직/네트워킹 레이어)

---

## 3. 긴급 최적화 대상 (Critical)

### 3.1 — 무한 반복 애니메이션의 Reduce Motion 미적용 경로

**문제**: `SharedEffects.swift`의 shimmer/livePulse가 `motionSafe()` 없이 직접 `.repeatForever()` 사용

| 파일 | 라인 | 코드 | 문제점 |
|------|-----|------|-------|
| `SharedEffects.swift` | L36 | `.easeInOut(duration: 1.8).repeatForever(autoreverses: false)` | `motionSafe()` 미적용 |
| `SharedEffects.swift` | L79 | `.easeInOut(duration: 3.0).repeatForever(autoreverses: true)` | `motionSafe()` 미적용 |

**수정 방안**:
```swift
// Before
withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { ... }

// After
withAnimation(DesignTokens.Animation.motionSafe(.easeInOut(duration: 1.8).repeatForever(autoreverses: false))) { ... }
```

**영향**: 접근성 → Reduce Motion 활성화 시에도 무한 애니메이션 계속 실행  
**예상 효과**: 접근성 준수 + Reduce Motion 사용자의 CPU/GPU 절약

---

### 3.2 — StreamAlertOverlayView의 `compositingGroup()` + shadow

**문제**: `compositingGroup()` + heavy shadow 조합이 프레임 드롭 유발

| 파일 | 라인 | 코드 |
|------|-----|------|
| `StreamAlertOverlayView.swift` | L155 | `.compositingGroup()` |
| `StreamAlertOverlayView.swift` | L157 | `.shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 3)` |

**수정 방안**:
- `compositingGroup()` 제거 → clipShape으로 합성 범위 제한 (ChatMessageRow 패턴 참고)
- shadow radius 10 → 6으로 축소

**영향**: 스트림 알림 오버레이 표시 시 GPU 부하 감소  
**예상 효과**: 오프스크린 렌더 패스 1회 제거, shadow blur 연산 ~36% 축소

---

### 3.3 — MultiLiveOverlays의 동적 shadow radius 애니메이션

**문제**: hover 시 shadow radius가 8→12로 변하며 매 프레임 blur 재계산

| 파일 | 라인 | 코드 |
|------|-----|------|
| `MultiLiveOverlays.swift` | L357 | `.shadow(color: chzzkGreen.opacity(isAddHovered ? 0.5 : 0.3), radius: isAddHovered ? 12 : 8, y: 3)` |

**수정 방안**:
```swift
// Before: radius 변경 = 매 프레임 blur 재생성
.shadow(color: chzzkGreen.opacity(isAddHovered ? 0.5 : 0.3), radius: isAddHovered ? 12 : 8, y: 3)

// After: opacity만 변경 (radius 고정) = blur 캐시 재사용
.shadow(color: chzzkGreen.opacity(isAddHovered ? 0.5 : 0.2), radius: 8, y: 3)
```

**원칙**: shadow radius는 고정하고 opacity만 애니메이션 → GPU가 blur 커널을 캐시 가능

---

## 4. 높은 우선순위 (High)

### 4.1 — MultiLiveOverlays의 과도한 shadow 사용

**문제**: 단일 뷰에 shadow가 4군데 적용

| 라인 | shadow | radius |
|-----|--------|--------|
| L184 | `.shadow(color: .black.opacity(0.4), radius: 2, y: 1)` | 2 (경량) |
| L296 | `.shadow(color: .black.opacity(0.15), radius: 20, y: 8)` | **20 (매우 무거움)** |
| L357 | `.shadow(color: chzzkGreen.opacity(), radius: 8-12)` | 8-12 (동적) |
| L498 | `.shadow(color: .black.opacity(0.2), radius: 8, y: 4)` | 8 |

**수정 방안**:
- L296: `radius: 20` → `radius: 10` 또는 제거 (배경 blur가 이미 깊이감 제공)
- L357: radius 고정 (위 3.3 참조)
- L498: 유지 (단일 shadow, 합리적 radius)

**예상 효과**: 멀티라이브 그리드 오버레이 렌더링 부하 ~40% 감소

---

### 4.2 — MultiLiveAddSheet의 stagger 애니메이션

**문제**: `delay(Double(index) * 0.03)` → N개 카드 각각 별도 타이밍의 독립 애니메이션

| 파일 | 라인 | 코드 |
|------|-----|------|
| `MultiLiveAddSheet+Following.swift` | L41 | `.animation(cardAppear.delay(Double(index) * 0.03))` |

**수정 방안**:
```swift
// Before: stagger delay → N개의 독립 Timer + 애니메이션 트래킹
.animation(DesignTokens.Animation.cardAppear.delay(Double(index) * 0.03))

// After: 즉시 표시 (스태거 제거)
.animation(DesignTokens.Animation.fast)
```

**또는** 최대 지연을 제한:
```swift
.animation(DesignTokens.Animation.cardAppear.delay(min(Double(index) * 0.03, 0.15)))
```

**영향**: 팔로잉 추가 시트 열 때 카드가 30개 이상이면 마지막 카드까지 0.9초 대기  
**예상 효과**: 초기 렌더링 latency 제거, 애니메이션 트래킹 오버헤드 감소

---

### 4.3 — scrollTransition 콜백 성능

**문제**: scrollTransition은 매 스크롤 프레임마다 콜백 호출

| 파일 | 라인 | 코드 |
|------|-----|------|
| `MultiLiveAddSheet+Following.swift` | L31 | `.scrollTransition(.animated(smooth)) { content, phase in ... }` |

**수정 방안**: scrollTransition 내부에서 `.opacity`와 `.scaleEffect`만 사용하는지 확인 → 복잡한 연산이 있다면 단순화

**예상 효과**: 스크롤 중 프레임 드롭 방지 (현재 1곳만 사용이라 낮은 영향)

---

### 4.4 — `blurReplace` 전환 사용 현황

**문제**: `.blurReplace()`는 macOS 15+ (iOS 18+) 전용이며, GPU에서 Gaussian blur 연산 필요

| 파일 | 라인 |
|------|-----|
| `StreamLoadingOverlay.swift` | L158, L164 |
| `MultiLiveOverlays.swift` | L25 |

**수정 방안**: 성능 민감한 경로(MultiLiveOverlays)에서는 `.opacity`로 대체 고려
```swift
// Before
.transition(.blurReplace.animation(fast))

// After (경량 대체)
.transition(.opacity.animation(fast))
```

**예상 효과**: 전환 시 Gaussian blur 연산 제거 → GPU 부하 약간 감소

---

### 4.5 — CategoryBrowseView의 shadow 밀집

**문제**: 단일 카드에 shadow 2-3개 중첩

| 라인 | 대상 | radius |
|-----|------|--------|
| L493 | 썸네일 shadow | 4 |
| L514 | LIVE 뱃지 shadow | 3 |
| L542 | 카드 전체 shadow | 5 |
| L589 | 오프라인 썸네일 | 4 |
| L596 | 오프라인 텍스트 | 3 |
| L637 | 오프라인 카드 | 5 |

**수정 방안**:
- 내부 shadow (L493, L514, L589, L596) 제거 → 카드 전체 shadow만 유지
- 카드 1개당 shadow 1개 원칙 적용

**예상 효과**: 카드당 blur 연산 2-3회 → 1회로 감소. 카드 20개 기준 blur 연산 40-60회 → 20회

---

## 5. 중간 우선순위 (Medium)

### 5.1 — MergedChatView 중복 shadow

| 라인 | 코드 |
|-----|------|
| L298 | `.shadow(color: .black.opacity(0.25), radius: 8, y: 3)` |
| L302 | `.shadow(color: .black.opacity(0.25), radius: 8, y: 3)` |

**수정**: 동일한 shadow가 4줄 간격으로 중복 → 상위 컨테이너로 통합

---

### 5.2 — 인라인 커스텀 spring 토큰화

**문제**: DesignTokens 토큰을 사용하지 않는 인라인 spring 정의

| 파일 | 라인 | 코드 |
|------|-----|------|
| `FollowingView.swift` | L592 | `withAnimation(.spring(response: 0.35, dampingFraction: 0.86))` |
| `FollowingView.swift` | L600 | `withAnimation(.spring(response: 0.35, dampingFraction: 0.86))` |

**수정**: `DesignTokens.Animation.smooth` (response: 0.35, damping: 0.88)와 거의 동일 → 토큰으로 통일
```swift
// Before
withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { livePageIndex -= 1 }

// After
withAnimation(DesignTokens.Animation.smooth) { livePageIndex -= 1 }
```

**목적**: 토큰 시스템 일관성 유지, 향후 글로벌 튜닝 가능

---

### 5.3 — hover 애니메이션 패턴 표준화

**현재**: 60+ 곳에서 hover를 다양한 방식으로 처리

**패턴 A** (withAnimation 내부):
```swift
.onHover { hovering in
    withAnimation(DesignTokens.Animation.fast) { isHovered = hovering }
}
```

**패턴 B** (animation modifier):
```swift
.onHover { isHovered = $0 }
.animation(DesignTokens.Animation.fast, value: isHovered)
```

**패턴 C** (이중 적용 — 비효율):
```swift
.onHover { h in withAnimation(fast) { isHovered = h } }
.animation(fast, value: isHovered)  // ← 중복
```

**수정**: 단일 패턴으로 통일 → **패턴 B** 권장 (선언적, value 기반 → SwiftUI가 diff 최적화 가능)

---

### 5.4 — FollowingView+Header 로딩 스피너

| 라인 | 코드 |
|-----|------|
| L136 | `.animation(isLoadingFollowing ? loadingSpin : .default, value: isLoadingFollowing)` |

**문제**: `.default` 애니메이션은 플랫폼 기본값 (macOS에서는 easeInOut 0.25s) → 의도하지 않은 전환 가능

**수정**:
```swift
.animation(isLoadingFollowing ? DesignTokens.Animation.loadingSpin : nil, value: isLoadingFollowing)
```

---

### 5.5 — ChatViewModel의 UI 애니메이션

| 파일 | 라인 | 코드 |
|------|-----|------|
| `ChatViewModel.swift` | L582 | `withAnimation(contentTransition) { ... }` |
| `ChatViewModel.swift` | L591 | `withAnimation(contentTransition) { ... }` |
| `ChatViewModel.swift` | L599 | `withAnimation(contentTransition) { ... }` |

**문제**: ViewModel에서 직접 `withAnimation` 호출 → 관심사 분리 위반  
**수정**: View 레이어에서 `.animation()` modifier로 처리하거나 현재 상태 유지 (리팩토링 범위 클 경우)

---

## 6. 낮은 우선순위 (Low)

### 6.1 — matchedGeometryEffect 최적화

현재 3곳에서 사용 중 — 모두 탭 언더라인 용도로, 성능 영향 무시 가능.

| 파일 | 사용 |
|------|-----|
| `ChannelInfoView.swift` L294 | `id: "tabUnderline"` |
| `PopularClipsView.swift` L348 | `id: "clipTabUnderline"` |

**상태**: 최적화 불필요 — 이미 경량 패턴

---

### 6.2 — Canvas 도입 확대 검토

현재 `PerformanceOverlayView`만 Canvas 사용 → Metal 3 직접 렌더링.

**검토 대상**:
- 스켈레톤 로딩 뷰 → Canvas shimmer 효과로 대체 가능
- 차트/그래프 뷰 → Canvas 기반 렌더링

**리스크**: Canvas는 접근성(VoiceOver) 지원이 제한적 → 정보 전달 목적이 아닌 장식 요소에만 적용

---

### 6.3 — `.transition(.opacity)` 단독 사용 검토

40곳에서 사용 중 — 가장 가벼운 전환 효과이므로 최적화 불필요.

---

## 7. 이미 적용된 최적화

이전 세션에서 완료된 최적화 항목 (참고용):

| 최적화 | 파일 | 내용 |
|-------|------|------|
| ✅ `drawingGroup()` 제거 (5곳) | FollowingView+List | categoryFilterChips, livePagingView, offlinePagingView에서 제거 |
| ✅ `compositingGroup()` + 이중 shadow 제거 | FollowingCardViews | 카드당 3회 오프스크린 패스 → 0회 |
| ✅ widgetCard 3-layer ZStack → 1-layer | FollowingView+List | 위젯당 5회 렌더 → 1회 |
| ✅ `mask()` → `scrollClipDisabled` | FollowingView+List | LinearGradient mask 제거 |
| ✅ `HStack` → `LazyHStack` | FollowingView+List | 아바타 스트립 lazy 렌더링 |
| ✅ `scrollTransition` 제거 | FollowingView+List | 아이템당 80+ 계산/프레임 제거 |
| ✅ stagger 애니메이션 제거 | FollowingCardViews | FollowingLiveCard, FollowingOfflineRow |
| ✅ shadow 축소 | FollowingCardViews, ChatAutocompleteView | radius 16→8, 이중→단일 |
| ✅ `lowercased()` 검색 최적화 | FollowingView | ICU locale 비교 → 단일 lowercase pass |
| ✅ UserDefaults 디바운스 | FollowingViewState | 드래그 중 초당 100회 쓰기 → 200ms 디바운스 |
| ✅ ChatMessageRow GPU 최적화 | ChatMessageRow | compositingGroup + shadow 제거 (주석으로 사유 기록) |
| ✅ ChannelMediaCards scaleEffect 제거 | ChannelMediaCards | compositingGroup 후 scale → 전체 레이어 재합성 방지 |
| ✅ CViewUI 스피너 drawingGroup 제거 | CViewUI.swift | L95 주석: "offscreen Metal pass added cost" |

---

## 8. 애니메이션 토큰 시스템 개선 제안

### 현재 토큰 (DesignTokens.Animation — 22개)

```
fast, normal, slow, spring, bouncy, smooth, snappy, micro,
interactive, contentTransition, indicator, pulse, chatScroll,
glassAppear, loadingSpin, menuPulse, fadeIn, cardHover,
gridPageTransition, cardAppear, dimTransition, staggerAppear,
overlayBlur, elasticRelease
```

### 제안: GPU 비용 기반 분류 태그

| 등급 | GPU 비용 | 포함 토큰 | 사용 가이드 |
|------|---------|----------|------------|
| 🟢 **Light** | < 1ms | micro, fast, fadeIn, chatScroll | 제한 없이 사용 |
| 🟡 **Medium** | 1-3ms | normal, snappy, smooth, indicator, contentTransition | 화면당 10개 이내 |
| 🔴 **Heavy** | > 3ms | slow, bouncy, spring, elasticRelease, glassAppear | 화면당 3개 이내 |
| ⚠️ **Infinite** | 지속적 | pulse, loadingSpin, menuPulse | 반드시 `motionSafe()` 적용 |

### 제안: 미사용/중복 토큰 정리

| 토큰 | 상태 | 제안 |
|------|------|------|
| `staggerAppear` | 대부분 stagger 제거됨 | 삭제 또는 deprecated 표시 |
| `dimTransition` | scrollTransition 전용인데 사용처 1곳 | `smooth`로 통일 |
| `overlayBlur` | `fast`와 유사 (response 0.02 차이) | `fast`로 통일 |
| `cardAppear` | MultiLiveAddSheet에서만 사용 | 유지 (stagger delay와 세트) |
| `gridPageTransition` | 활발히 사용 | 유지 |
| `elasticRelease` | 사용처 확인 필요 | 미사용 시 삭제 |

---

## 9. 접근성 (Reduce Motion) 준수 현황

### `motionSafe()` 적용 현황

| 파일 | 적용 상태 | 애니메이션 |
|------|----------|----------|
| PlayerControlsView.swift | ✅ 적용 | pulse (녹화 버튼) |
| CViewUI.swift | ✅ 적용 | loadingSpin (스피너) |
| StreamLoadingOverlay.swift | ✅ 적용 | loadingSpin (스트림 로딩) |
| **SharedEffects.swift** | ❌ **미적용** | shimmer (L36), livePulse (L79) |
| DesignTokens.swift | ✅ 정의됨 | `motionSafe()` 유틸리티 메서드 |

### 수정 필요: SharedEffects.swift

```swift
// L36 — shimmer
withAnimation(DesignTokens.Animation.motionSafe(
    .easeInOut(duration: 1.8).repeatForever(autoreverses: false)
)) { shimmerPhase = 1.0 }

// L79 — livePulse  
withAnimation(DesignTokens.Animation.motionSafe(
    .easeInOut(duration: 3.0).repeatForever(autoreverses: true)
)) { isPulsing = true }
```

---

## 10. 단계별 실행 로드맵

### Phase 1: 긴급 수정 (예상 소요: 30분)

| # | 작업 | 파일 | 효과 | 상태 |
|---|------|------|------|------|
| 1 | SharedEffects `motionSafe()` 적용 | SharedEffects.swift | 접근성 준수 | ✅ 완료 |
| 2 | StreamAlertOverlay `compositingGroup()` 제거 | StreamAlertOverlayView.swift | GPU 패스 -1 | ✅ 완료 |
| 3 | MultiLiveOverlays shadow radius 고정 | MultiLiveOverlays.swift L357 | blur 캐시 가능 | ✅ 완료 |

### Phase 2: 높은 우선순위 ✅ 완료

| # | 작업 | 파일 | 효과 | 상태 |
|---|------|------|------|------|
| 4 | MultiLiveOverlays `radius: 20` shadow 축소 | MultiLiveOverlays.swift L296 | GPU blur -50% | ✅ 완료 |
| 5 | MultiLiveAddSheet stagger 제한/제거 | MultiLiveAddSheet+Following.swift | 초기 렌더 속도 | ✅ 완료 |
| 6 | CategoryBrowseView 카드 내부 shadow 통합 | CategoryBrowseView.swift | 카드당 blur -60% | ✅ 완료 |
| 7 | `blurReplace` → `.opacity` (MultiLiveOverlays) | MultiLiveOverlays.swift L25 | blur 연산 제거 | ✅ 완료 |

### Phase 3: 중간 우선순위 ✅ 완료

| # | 작업 | 파일 | 효과 | 상태 |
|---|------|------|------|------|
| 8 | MergedChatView 중복 shadow 통합 | MergedChatView.swift | shadow -1 | ✅ 완료 |
| 9 | 인라인 커스텀 spring → 토큰 통일 | FollowingView.swift L592/L600 | 코드 일관성 | ✅ 완료 |
| 10 | hover 패턴 표준화 (패턴 B) | 전체 앱 | 코드 일관성 | ✅ 완료 |
| 11 | FollowingView+Header .default → nil | FollowingView+Header.swift L136 | 의도하지 않은 전환 방지 | ✅ 완료 |

### Phase 4: 고도화 ✅ 완료 (2026-04-04)

| # | 작업 | 파일 | 효과 | 상태 |
|---|------|------|------|------|
| 12 | 미사용 애니메이션 토큰 정리 | DesignTokens.swift | 4개 토큰 제거 (dimTransition, staggerAppear, overlayBlur, elasticRelease) | ✅ 완료 |
| 13 | ChannelMediaCards Pattern C 이중 애니메이션 제거 | ChannelMediaCards.swift | GPU 이중 추적 제거 | ✅ 완료 |
| 14 | Shadow radius 벌크 최적화 (5곳) | MultiLiveOverlays, SearchViews, CommandPalette, SplashView, FollowingCards | GPU blur 40-60% 감소 | ✅ 완료 |
| 15 | hover 패턴 A→B 변환 (5곳) | PopularClipCards, RecentFavorites, PlayerControls, MultiLiveTabBar | SwiftUI diff 최적화 | ✅ 완료 |
| 16 | blurReplace → opacity (2곳) | MultiLivePlayerPane | Gaussian blur 연산 제거 | ✅ 완료 |
| 17 | ShimmerModifier → TimelineView + Canvas (Metal 3) | SharedEffects.swift | GeometryReader/LinearGradient/offset 제거, 20+ 인스턴스 GPU 가속 | ✅ 완료 |
| 18 | ChatViewModel withAnimation → View .animation(value:) | ChatViewModel.swift, LiveStreamView.swift | MVVM 관심사 분리, withAnimation 3개 제거 | ✅ 완료 |

---

## 부록: 파일별 애니메이션 인벤토리

<details>
<summary>전체 파일-라인 매핑 (클릭하여 펼치기)</summary>

### CViewCore
- `DesignTokens.swift` L464-520: 22개 애니메이션 토큰 정의
- `DesignTokens.swift` L628-647: PrimaryButtonStyle (scale, shadow, hover)
- `DesignTokens+Modifiers.swift` L103-215: Secondary/Tertiary/Icon 버튼 (scale, hover)

### CViewUI  
- `CViewUI.swift` L21-39: 로딩 스피너 rotationEffect
- `CViewUI.swift` L73-99: 펄싱 라이브 뱃지
- `CViewUI.swift` L217-219: 버튼 press scale
- `CachedAsyncImage.swift` L36-41: 조건부 전환 (캐시 히트 시 스킵)
- `TimelineSlider.swift` L54-73: 드래그 오프셋, hover 미리보기

### CViewApp/Views
- `FollowingView.swift` L256-416: opacity 전환, 패널 애니메이션, 조건부 animation
- `FollowingView.swift` L592-702: 페이지 spring, 필터 토글 (5x withAnimation)
- `FollowingView+List.swift` L24-675: indicator, gridPageTransition, 페이지네이터
- `FollowingView+Header.swift` L27-436: 검색, 정렬, 스피너, shadow
- `FollowingCardViews.swift`: 카드 hover, 라이브 아바타 (이전 최적화 완료)
- `PlayerControlsView.swift` L49-725: 오버레이, hover(4x), 녹화 pulse, asymmetric 전환
- `MultiLiveOverlays.swift` L25-498: blurReplace, drawingGroup, hover(4x), shadow(4x)
- `MultiLiveTabBar.swift` L78-407: snappy(7x), fast(3x), opacity+scale 전환
- `MultiLiveSettingsPanel.swift` L132-156: snappy(1x), fast(2x)
- `MultiLiveAddSheet+Following.swift` L31-167: scrollTransition, stagger delay, 전환
- `CategoryBrowseView.swift` L67-638: 네비게이션 전환, hover(4x), shadow(6x), 스피너
- `MergedChatView.swift` L137-302: 리플레이 배너, chatScroll, shadow(2x)
- `ChatOverlayView.swift` L58-324: hover, chatScroll, shadow(2x), opacity 전환
- `ChatInputView.swift` L53-164: autocomplete 전환, hover(3x)
- `StreamLoadingOverlay.swift` L73-222: 스피너, blurReplace(2x), spring, smooth
- `StreamAlertOverlayView.swift` L18-157: asymmetric 전환, compositingGroup, shadow
- `SearchViews.swift` L112-199: 포커스 shadow, autocomplete 전환
- `ChannelInfoView.swift` L260-303: indicator, matchedGeometryEffect, shadow
- `PopularClipsView.swift` L135-348: opacity 전환, indicator, matchedGeometryEffect
- `SharedEffects.swift` L36-98: shimmer repeatForever, livePulse repeatForever, shadow
- `ChannelMediaCards.swift` L70: scaleEffect 제거 주석
- `ChatMessageRow.swift` L139-477: 조건부 shadow, GPU 최적화 주석(2x)
- `ChatAutocompleteView.swift` L63-77: micro, GPU 최적화 shadow 주석
- `ErrorRecoveryView.swift` L214-289: fast, indicator, move+opacity 전환
- `SettingsView.swift` L107-162: snappy, indicator, fast
- `GeneralSettingsTab.swift` L188-458: fast, normal (테마 전환)
- `MLToolsTab.swift` L48-111: fast(2x) hover
- `MLAudioTab.swift` L61: fast hover
- `StatisticsDetailViews.swift` L676: smooth hover
- `PerformanceOverlayView.swift` L3-114: Canvas Metal 3, drawingGroup 제거 주석
- `LoginView.swift` L73: shadow (정적)
- `PlayerEngineBadge.swift` L37: shadow (정적)
- `FollowingView+MultiLive.swift` L42-124: snappy(5x), glassAppear, move 전환
- `FollowingView+MultiChat.swift` L46-176: snappy(3x)
- `PlayerAdvancedSettingsView.swift` L131-145: snappy, fast
- `MLSettingsSharedComponents.swift` L45-87: fast(2x) hover
- `MultiLiveAddSheet+Following.swift` L31-167: scrollTransition, stagger, 전환

### CViewApp/ViewModels
- `ChatViewModel.swift` L582-599: contentTransition(3x)

</details>

---

## 핵심 원칙 요약

1. **shadow radius는 고정, opacity만 애니메이션** → blur 커널 캐시 활용
2. **카드 1개 = shadow 1개** 원칙 → 내부 자식에 shadow 중첩 금지
3. **무한 반복 = `motionSafe()` 필수** → 접근성 + CPU/GPU 절약
4. **`compositingGroup()` 최소화** → 오프스크린 렌더 패스 발생
5. **hover 패턴 B (`.animation(value:)`)** 통일 → SwiftUI diff 최적화 활용
6. **인라인 spring → DesignTokens 토큰** → 글로벌 튜닝 가능성 확보
7. **`blurReplace` 신중하게** → GPU Gaussian blur 비용 고려

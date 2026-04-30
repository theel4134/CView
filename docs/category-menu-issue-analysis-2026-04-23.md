# 카테고리 메뉴 문제점 정밀 분석 리포트

- **문서 버전**: 2026-04-23
- **분석 대상**: `Sources/CViewApp/Views/CategoryBrowseView.swift` (629 LOC)
- **연관 파일**: `Sources/CViewApp/ViewModels/HomeViewModel.swift` (`categoryChannels`, `allStatChannels`, `loadAllStatsChannels`)
- **분석 범위**: 데이터 플로우 · UI/UX · 성능 · GPU · 접근성 · 상태 관리 · 디자인 일관성
- **총 이슈 수**: **34건** (Critical 6 · High 11 · Medium 12 · Low 5)

---

## 1. Executive Summary

`CategoryBrowseView`는 **치지직 라이브 채널을 카테고리별로 집계/탐색**하는 2단 화면(카테고리 그리드 → 채널 그리드) 뷰입니다. 기능은 동작하지만, 분석 결과 다음과 같은 **구조적 결함** 이 존재합니다.

| 영역 | 핵심 결함 | 영향 |
|---|---|---|
| **데이터 플로우** | `liveChannels` ↔ `allStatChannels` 이중 소스 전환으로 카테고리 수/채널 수가 **로딩 중 요동** | UX 혼란, 숫자 깜박임 |
| **결정성 (Determinism)** | `hashValue` 기반 accentColor/icon — Swift 런타임 hash seed 랜덤화로 **재실행마다 색/아이콘 변경** | 사용자 인식 학습 방해 |
| **정렬 안정성** | 카운트 동률 카테고리의 순서가 `Dictionary` 해시 순서에 의존 — **매 tick 마다 순서 변경** | 시각적 난동 |
| **새로고침** | `allStatChannels = []` 즉시 비우기 → **캐시/데이터 손실**, 에러 시 복구 불가 | 치명적 (데이터 로스) |
| **GPU** | `strokeBorder(lineWidth: 0.75↔1.5)` hover 애니메이션으로 **CAShapeLayer re-tessellation** | FollowingView 최근 최적화 지침 위배 |
| **접근성** | 모든 버튼에 `.buttonStyle(.plain)`, label 부재, keyboard/focus 지원 없음 | VoiceOver/키보드 이용자 차단 |

**권장 우선순위**: Critical → High → Medium → Low. Critical 6건은 단독 PR로 즉시 수정 필요.

---

## 2. Critical 이슈 (6건)

### C1. `categoryChannels` 이중 소스로 인한 데이터 깜박임
- **위치**: [HomeViewModel.swift#L85-L87](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L85-L87)
  ```swift
  public var categoryChannels: [LiveChannelItem] {
      allStatChannels.isEmpty ? liveChannels : allStatChannels
  }
  ```
- **증상**: 진입 시 `liveChannels`(페이지 하나, 약 20개) → 수 초 후 `allStatChannels`(수백 개)로 **원자적 스왑**. 카테고리 개수·카드 구성·라이브 수 카운터가 동시에 점프.
- **원인**: 두 데이터셋이 **완전히 다른 스키마/크기**인데 같은 그리드에서 공유.
- **영향**: 사용자가 첫 데이터에서 카드를 탭하는 순간 정답 카테고리가 사라지는 race 발생 가능.
- **권장 해결**:
  1. **로딩 상태 3단 분리**: `.initial` / `.partial` / `.complete`. partial 상태에는 "부분 데이터" 배지 명시.
  2. 또는 항상 `allStatChannels`만 사용하고 빈 상태에선 스켈레톤.

### C2. 새로고침 시 즉시 데이터 wipe
- **위치**: [CategoryBrowseView.swift#L185-L192](../Sources/CViewApp/Views/CategoryBrowseView.swift#L185-L192)
  ```swift
  Task {
      isRefreshing = true
      await viewModel.loadLiveChannels()
      viewModel.allStatChannels = []           // ← 즉시 wipe
      await viewModel.loadAllStatsChannels()
      isRefreshing = false
  }
  ```
- **증상**:
  - 새로고침 버튼 탭 즉시 화면이 빈 상태로 전환 → 스피너만 표시 → 수십 초 후 재구성.
  - `loadAllStatsChannels()`가 실패하면 **이전 데이터가 영원히 손실**됨.
- **권장 해결**:
  - wipe 하지 말고 `loadAllStatsChannels()` **내부에서 성공 후 replace** 하는 패턴으로. (지금도 `allStatChannels = items` 로 replace 하고 있어 wipe는 불필요.)
  - refresh 중 중복 탭 방지 가드(`guard !isRefreshing` 이미 존재하나 `isLoadingStats` 체크와 조합 필요).

### C3. `hashValue` 기반 accentColor/icon — 비결정적
- **위치**:
  - [CategoryBrowseView.swift#L413-L418](../Sources/CViewApp/Views/CategoryBrowseView.swift#L413-L418) `accentColor(for:)`
  - [CategoryBrowseView.swift#L437-L443](../Sources/CViewApp/Views/CategoryBrowseView.swift#L437-L443) `categoryIcon`
  ```swift
  return palette[abs(category.hashValue) % palette.count]
  ```
- **증상**: Swift 5+ 의 `Hashable.hashValue`는 **프로세스마다 랜덤화된 seed**를 사용 → 앱 재시작마다 "리그 오브 레전드"가 다른 색/아이콘으로 표시.
- **영향**: 사용자가 색상/아이콘으로 카테고리를 인식·학습하는 패턴 **완전 파괴**.
- **권장 해결**:
  - 문자열 해시는 `SipHasher` 대신 **결정적 FNV-1a / CRC32** 로 대체.
  ```swift
  private func stableHash(_ s: String) -> UInt64 {
      var h: UInt64 = 0xcbf29ce484222325
      for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
      return h
  }
  ```
  - 더 이상적으로는 치지직 API의 `categoryType` (GAME/SPORTS/ETC) + 알려진 메이저 게임 화이트리스트 기반 **룩업 테이블**.

### C4. `Dictionary` grouping — 동률 카테고리 순서 불안정
- **위치**: [CategoryBrowseView.swift#L45-L51](../Sources/CViewApp/Views/CategoryBrowseView.swift#L45-L51)
  ```swift
  let grouped = Dictionary(grouping: filtered) { $0.categoryName ?? "기타" }
  return grouped
      .map { (category: $0.key, channels: $0.value) }
      .sorted { $0.channels.count > $1.channels.count }
  ```
- **증상**: `.sorted` 는 count만 비교하므로 **동률인 카테고리의 상대 순서**가 Dictionary 내부 hash 순서(=Swift seed 랜덤)에 의존 → 페이지 리로드 때마다 순서 바뀜.
- **권장 해결**: tie-breaker로 카테고리명 정렬 추가.
  ```swift
  .sorted { ($0.channels.count, $1.category) > ($1.channels.count, $0.category) }
  ```

### C5. `.task` 중복 호출 가드 부재
- **위치**: [CategoryBrowseView.swift#L79-L86](../Sources/CViewApp/Views/CategoryBrowseView.swift#L79-L86)
  ```swift
  .task {
      if viewModel.liveChannels.isEmpty {
          await viewModel.loadLiveChannels()
      }
      if viewModel.allStatChannels.isEmpty && !viewModel.isLoadingStats {
          await viewModel.loadAllStatsChannels()
      }
  }
  ```
- **증상**: `.task` 는 뷰가 onAppear/onDisappear 될 때마다 재실행. 카테고리 ↔ 채널 상세 왔다갔다 하면 **전체 통계 수집이 매번 트리거** (수십 초 소요, 네트워크 다량 소비).
- **참고**: `isEmpty` 가드로 일부 방어되지만, 새로고침으로 `allStatChannels = []` 한 직후 네비게이션 시 재수집 발생.
- **권장 해결**:
  - `.task(id:)` + 명시적 cacheKey 사용, 또는 `loadAllStatsChannelsIfStale(ttl: 600)` 래퍼.

### C6. 에러 상태 UI 부재
- **위치**: [HomeViewModel.swift#L573-L575](../Sources/CViewApp/ViewModels/HomeViewModel.swift#L573-L575)
  ```swift
  } catch {
      logger.error("전체 통계 수집 실패: \(error)")
  }
  ```
- **증상**: `loadAllStatsChannels()` 실패 시 로그만 찍고 **UI 변화 없음**. 사용자는 "영원히 로딩 중"이라고 오해하고 앱을 강제 종료하는 경향.
- **권장 해결**:
  - `@Published var statsLoadError: Error?` 추가
  - 뷰에서 배너/토스트로 표출 + 재시도 버튼 노출.

---

## 3. High 이슈 (11건)

### H1. `isLoading` 분기 중첩 — 스파게티 가드 구조
- [CategoryBrowseView.swift#L98-L145](../Sources/CViewApp/Views/CategoryBrowseView.swift#L98-L145)
- `viewModel.isLoading && liveChannels.isEmpty` → `isLoadingStats && allStatChannels.isEmpty` → `categorizedChannels.isEmpty` → else.
- 3중 분기 내부에서 **같은 grid 코드가 2번 중복** (statsLoading 분기 내부 & else 분기).
- **권장**: `enum ContentState { case loading, partialWithStats, ready, empty, error }` 로 flatten.

### H2. 카테고리 타입 필터 하드코딩
- [CategoryBrowseView.swift#L328-L335](../Sources/CViewApp/Views/CategoryBrowseView.swift#L328-L335)
  ```swift
  typeFilterButton(label: "게임", icon: "gamecontroller.fill", value: "GAME")
  typeFilterButton(label: "스포츠", icon: "sportscourt.fill", value: "SPORTS")
  typeFilterButton(label: "기타", icon: "ellipsis.circle.fill", value: "ETC")
  ```
- 치지직 API가 새로운 `categoryType`(예: `TALK`, `MUSIC`)을 추가해도 UI에 노출되지 않음. 무언의 누락 발생.
- **권장**: `sourceChannels` 스캔하여 **동적으로 타입 목록 생성** + 다국어(i18n) 분리.

### H3. "기타" 버킷 폴백 로직 혼란
- `categoryName == nil` → "기타" 로 병합 ([CategoryBrowseView.swift#L47](../Sources/CViewApp/Views/CategoryBrowseView.swift#L47))
- 하지만 `categoryType == "ETC"` 필터와 일치하지 않는 채널(categoryName nil이지만 type이 다른 경우)도 "기타"에 섞임.
- 결과: ETC 필터를 선택해도 "기타" 버킷이 비어있거나 반대 현상 발생.
- **권장**: `categoryName ?? "분류 없음"` 으로 rename + ETC 타입과 구분된 별도 집계.

### H4. Hover 시 테두리 lineWidth 애니메이션 (GPU 이슈)
- [CategoryBrowseView.swift#L519-L524](../Sources/CViewApp/Views/CategoryBrowseView.swift#L519-L524) 및 [#L611-L617](../Sources/CViewApp/Views/CategoryBrowseView.swift#L611-L617)
  ```swift
  .strokeBorder(
      isHovered ? accentColor.opacity(0.65) : ...,
      lineWidth: isHovered ? 1.5 : 0.75    // ← CAShapeLayer 재테셀레이션
  )
  ```
- **FollowingView 에서 2026-04-23 에 이미 제거한 동일 패턴** — 카테고리 뷰만 누락.
- **영향**: 그리드에 카드 30+개 있는 상태에서 마우스 이동 시 GPU spike.
- **권장 해결**: lineWidth 고정(1 또는 1.25) + color opacity로만 변화.

### H5. `onGeometryChange` 매 프레임 grid 재계산
- [CategoryBrowseView.swift#L73-L78](../Sources/CViewApp/Views/CategoryBrowseView.swift#L73-L78)
  ```swift
  .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width }
  action: { width in contentWidth = width }
  ```
- `gridColumns` / `channelGridColumns` 가 `contentWidth`에 의존하는 computed property → 윈도우 리사이즈 중 **매 프레임 칼럼 배열 재생성** + LazyVGrid 전체 레이아웃 재계산.
- **권장**: `debounce(200ms)` 적용 or 너비를 임계값(예: 100px 단위)으로 quantize.

### H6. `channelsInCategory` 비 메모이즈 필터링
- [CategoryBrowseView.swift#L53-L61](../Sources/CViewApp/Views/CategoryBrowseView.swift#L53-L61)
- `sourceChannels.filter` + `.lowercased()` 이 **body 재렌더마다** 실행. 대량 데이터 시 호버·타이핑마다 수천 비교.
- **권장**: `Observable` 뷰모델로 로직 이관 + `@State` 결과 캐시.

### H7. 채널 카드 `onTapGesture` — 키보드/접근성 누락
- [CategoryBrowseView.swift#L240-L243](../Sources/CViewApp/Views/CategoryBrowseView.swift#L240-L243)
  ```swift
  CategoryChannelCard(channel: channel)
      .onTapGesture { router.navigate(to: .live(channelId: channel.channelId)) }
  ```
- Button이 아니므로 **스페이스/엔터 키 접근 불가**, VoiceOver `traits` 없음, hover press 시각 피드백 없음.
- **권장**: `Button` 으로 래핑 + `PressScaleButtonStyle`.

### H8. 새로고침 버튼 회전 애니메이션 끊김
- [CategoryBrowseView.swift#L201-L207](../Sources/CViewApp/Views/CategoryBrowseView.swift#L201-L207)
  ```swift
  .rotationEffect(.degrees(isRefreshing ? 360 : 0))
  .animation(isRefreshing ? .loadingSpin : .default, value: isRefreshing)
  ```
- `isRefreshing = false` 시 `.default` 로 전환되며 각도가 **0으로 튕기듯 되돌아감**.
- **권장**: `TimelineView(.animation)` 기반 continuous rotation 또는 `ProgressView` 대체.

### H9. `selectedCategory` 복귀 후 필터/검색 상태 누수
- [CategoryBrowseView.swift#L252-L257](../Sources/CViewApp/Views/CategoryBrowseView.swift#L252-L257) — `selectedCategory = nil` 시 `channelSearchText = ""` 만 리셋, **`selectedTypeFilter` 는 유지**.
- 채널 상세에서 타입 필터 관련 상태가 의도치 않게 섞임.
- **권장**: 명시적 "세션 리셋" 함수로 일관 처리.

### H10. 새로고침 중 다중 Task 방지 부재
- `.task` 가드(`guard !isLoadingStats`)는 있지만, **버튼 클릭 경로**는 `isRefreshing` 체크 없이 새 Task 생성.
- 빠른 연속 탭 시 여러 Task 스폰 → 결과 race.

### H11. ScrollView + LazyVStack + LazyVGrid 중첩
- [CategoryBrowseView.swift#L93-L147](../Sources/CViewApp/Views/CategoryBrowseView.swift#L93-L147)
- LazyVStack 내부 최상위 child가 LazyVGrid 하나 + 헤더들.
- Lazy 중첩은 **SwiftUI 레이아웃 캐시 충돌** 발생 가능(특히 macOS 15.x). 외부 LazyVStack 불필요.
- **권장**: 외부를 `VStack`으로 변경. 내부 LazyVGrid만 유지.

---

## 4. Medium 이슈 (12건)

### M1. `previewChannels` 데이터 무용
- [CategoryBrowseView.swift#L112-L117](../Sources/CViewApp/Views/CategoryBrowseView.swift#L112-L117) — `previewChannels: Array(group.channels.prefix(2))` 전달.
- `CategoryGridCard` body에서 `previewChannels`가 **한 번도 참조되지 않음** ([CategoryBrowseView.swift#L444-L537](../Sources/CViewApp/Views/CategoryBrowseView.swift#L444-L537) 확인).
- 불필요한 메모리/복사 비용.

### M2. `LiveThumbnailView(isLive: false)` — 자동 갱신 의도적 비활성화
- [CategoryBrowseView.swift#L546-L551](../Sources/CViewApp/Views/CategoryBrowseView.swift#L546-L551)
- 주석에는 "자동갱신 비활성화" 로 의도 명시되어 있지만, **라이브 중 채널을 정적 이미지로 렌더** → 2–5분 경과 시 실제 방송과 다른 썸네일.
- **권장**: 카테고리 내 채널 ≤ 20개일 때만 `isLive: true`, 초과 시 수동 새로고침 유도.

### M3. 카테고리 상세 검색 — 글로벌 검색 부재
- 카테고리별로만 검색 가능. "전체 라이브에서 채널 검색" 기능은 `FollowingView` 에만 있고 카테고리에는 없음.
- **권장**: 카테고리 그리드 헤더에 글로벌 검색바 추가 + 검색 시 자동으로 채널 모드로 flatten.

### M4. 정렬 옵션 없음
- 카테고리 그리드: 라이브 수(내림차순) 고정
- 채널 그리드: 입력 배열 순서 그대로 (사실상 정렬 안 됨)
- **권장**: 시청자수 / 가나다 / 최근 시작 중 선택 가능.

### M5. 즐겨찾기/고정 카테고리 기능 없음
- 자주 보는 카테고리를 상단 고정하는 기능 부재.
- **권장**: `@AppStorage` 배열로 pinnedCategories 관리.

### M6. Empty state 아이콘 부적절
- [CategoryBrowseView.swift#L408-L411](../Sources/CViewApp/Views/CategoryBrowseView.swift#L408-L411) — `EmptyStateView(icon: "tv.slash", ...)`.
- 카테고리 탐색 맥락에서는 `square.grid.2x2.slash` 가 더 적합.

### M7. CategoryGridCard 내부 5층 ZStack
- [CategoryBrowseView.swift#L454-L500](../Sources/CViewApp/Views/CategoryBrowseView.swift#L454-L500): 그라디언트 → 아이콘 → 페이드 오버레이 → 텍스트 → 우상단 뱃지.
- 카드 30+개 × 5 레이어 = 150+ Metal draw.
- **권장**: 아이콘과 배경을 `compositingGroup()` + `drawingGroup()`으로 래스터화 캐시.

### M8. `channelImageUrl` nil 시 `URL(string: "")` 생성
- [CategoryBrowseView.swift#L567-L570](../Sources/CViewApp/Views/CategoryBrowseView.swift#L567-L570)
  ```swift
  CachedAsyncImage(url: URL(string: channel.channelImageUrl ?? "")) { ... }
  ```
- `URL(string: "")` 는 nil 반환이라 큰 이슈는 없으나, 명시적 옵셔널 chaining이 바람직.
- **권장**: `URL(string: channel.channelImageUrl ?? "") ?? nil` 대신 `channel.channelImageUrl.flatMap(URL.init)`.

### M9. 접근성 라벨/힌트 부재 (기존 H7 외)
- 새로고침 버튼: `.help` 도 없음
- 타입 필터 버튼: `accessibilityLabel` 없음 → "게임 카테고리 필터, 선택됨" 음성 안내 불가.
- 카테고리 카드: "리그 오브 레전드, 라이브 12개" 같은 결합 라벨 없음.

### M10. 키보드 네비게이션 전무
- ESC 로 카테고리 뒤로가기 불가. 화살표 키로 카드 탐색 불가. 1–9 숫자키 단축 없음.
- 명령 팔레트와의 연동 없음 (`CommandPaletteView` 존재).

### M11. FollowingView와 디자인 일관성 결여
- Button style: FollowingView `PressScaleButtonStyle(...)` vs Category `.plain`.
- matchedGeometryEffect / symbolEffect 등 최신 모션 미적용.
- 필터 pill 애니메이션 불일치.

### M12. statsLoadingBanner와 grid 동시 표시 레이아웃 점프
- [CategoryBrowseView.swift#L104-L124](../Sources/CViewApp/Views/CategoryBrowseView.swift#L104-L124) — 배너가 VStack 상단에 추가되면 grid 전체가 아래로 밀리는 **레이아웃 shift** 발생.
- **권장**: 배너를 overlay(.top) 로 배치하거나 fixed-height placeholder.

---

## 5. Low 이슈 (5건)

### L1. `Color(hex:)` 사용 — 다크/라이트 모드 미대응
- [CategoryBrowseView.swift#L416-L417](../Sources/CViewApp/Views/CategoryBrowseView.swift#L416-L417) — `Color(hex: 0x00C9A7)`, `Color(hex: 0xFF6B6B)`, `Color(hex: 0x4ECDC4)`.
- DesignTokens 외부 값, 라이트 모드 대비율 검증 안 됨.

### L2. 고정 폰트 크기 (Dynamic Type 미지원)
- `font(.system(size: 10))`, `size: 22, 24` 등 하드코딩. macOS 시스템 "큰 글씨" 설정 영향 받지 않음.

### L3. `categoryHeader` 의 "CATEGORY" 영문 tracking
- `tracking(1.8)` 하드코딩. 로컬라이제이션(일본어/영어) 시 가독성 저하.

### L4. `selectedCategory` 뷰 전환 애니메이션 한 방향 고정
- 카테고리 → 채널: `.trailing`
- 채널 → 카테고리: `.leading`
- RTL 로케일 지원 시 반대로 적용되지 않음.

### L5. Preview 매크로 부재
- `#Preview` / `PreviewProvider` 없음 → 빠른 UI 반복 테스트 곤란.

---

## 6. 영역별 위험도 매트릭스

| 영역 | Critical | High | Medium | Low | 합계 |
|---|:-:|:-:|:-:|:-:|:-:|
| 데이터 플로우 | C1, C2, C5, C6 | H1, H3, H10 | M2 | — | **8** |
| 결정성/정렬 | C3, C4 | — | — | — | **2** |
| 성능/GPU | — | H4, H5, H6, H11 | M7, M8, M12 | — | **7** |
| UX/네비게이션 | — | H9 | M3, M4, M5, M6, M11 | L4 | **7** |
| 접근성 | — | H7 | M9, M10 | L2, L3 | **5** |
| 비주얼/일관성 | — | H8 | — | L1, L5 | **3** |
| 기타 | — | H2 | M1 | — | **2** |
| **합계** | **6** | **11** | **12** | **5** | **34** |

---

## 7. 권장 수정 순서 (단계별 로드맵)

### Phase 1 — 긴급 (1–2일)
1. **C2 새로고침 wipe 제거** — 한 줄 삭제 (`viewModel.allStatChannels = []`)
2. **C3 hashValue 제거** — FNV-1a 도입 (20줄)
3. **C4 tie-breaker 정렬** — `.sorted` 수정 (1줄)
4. **C6 에러 상태 UI** — `statsLoadError` + 배너 추가 (30줄)
5. **H4 lineWidth 고정** — FollowingView 패턴 이식 (카드 2종)

### Phase 2 — 구조 개선 (3–5일)
6. **C1 + C5 데이터 상태 머신** — `ContentState` enum 도입, `.task(id:)` 로 재진입 제어
7. **H1 분기 flatten** — switch-case 재작성
8. **H6 필터링 memoize** — `HomeViewModel`로 이관
9. **H7 Button 래핑 + 접근성**

### Phase 3 — UX 확장 (1주+)
10. **M3 글로벌 검색 / M4 정렬 / M5 즐겨찾기**
11. **M11 FollowingView와 모션·스타일 통일** (PressScaleButtonStyle, matchedGeometryEffect, symbolEffect)
12. **M10 키보드 네비게이션** — focusable + onKeyPress

### Phase 4 — Polish
13. L1–L5 (디자인 토큰화, Dynamic Type, RTL, Preview)

---

## 8. 코드 스멜 요약

- **중복**: statsLoading 분기와 else 분기의 LazyVGrid 코드가 거의 동일 (DRY 위배).
- **Magic numbers**: `240`, `160`, `140`, `34`, `0.75`, `1.5` 등 DesignTokens 외부 상수 다수.
- **Side effect in computed property**: `categorizedChannels` 가 매 렌더마다 sort + filter + group.
- **God view**: 단일 파일 629 LOC, 2개 화면 + 5개 카드/버튼 + 3개 상태 뷰. `CategoryGridScreen` / `CategoryDetailScreen` / `CategoryTypeFilterBar` 등으로 분해 권장.

---

## 9. 테스트 누락

- `Tests/` 하위에 `CategoryBrowseView` 관련 테스트 **0건** (검색 결과 없음).
- 필요한 테스트:
  - `categorizedChannels` 정렬 결정성 (같은 입력 → 같은 순서)
  - `accentColor(for:)` 결정성 (runtime 재시작 후 동일 색)
  - "기타" 폴백 로직 — categoryName nil vs categoryType ETC 분리
  - 새로고침 실패 시 기존 데이터 보존
  - TypeFilter ALL/GAME/SPORTS/ETC 교집합 정확성

---

## 10. 결론

`CategoryBrowseView`는 **기능적으로는 동작**하지만, 데이터 플로우의 취약성(C1/C2/C5), 결정성 부재(C3/C4), 에러 처리 부재(C6)가 결합되어 **"믿을 수 없는 뷰"** 로 작용할 여지가 큽니다. 또한 최근 `FollowingView`에 적용된 모션 시스템 / GPU 최적화 지침이 **이 뷰에만 미적용**되어 있어 일관성이 훼손되어 있습니다.

**Phase 1의 5건 수정**만으로도 체감 품질이 크게 개선되며, **Phase 2까지 완료 시 FollowingView 수준**의 완성도에 도달할 것으로 예상됩니다.

---

_분석 완료. 기준 파일: `CategoryBrowseView.swift@HEAD (629 LOC)` · `HomeViewModel.swift@HEAD`._

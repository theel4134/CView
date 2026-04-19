# 멀티라이브 · 멀티채팅 정밀 분석 및 통합 개선안

> **작성일**: 2026-04-18
> **대상**: CView_v2 macOS 앱 (Swift 6.0 / SwiftUI / Actor)
> **범위**: MultiLive(다채널 영상) + MultiChat(다채널 채팅) 양 축 통합
> **선행 문서**: [docs/multichat-improvement-analysis.md](multichat-improvement-analysis.md) (Phase 1~3 완료 기준)
> **기준 코드량**: MultiLive ≈ **5,750줄** / MultiChat ≈ **5,900줄** = 합계 약 **11,650줄**

---

## 목차

1. [현재 아키텍처 요약](#1-현재-아키텍처-요약)
2. [멀티라이브 정밀 분석](#2-멀티라이브-정밀-분석)
3. [멀티채팅 정밀 분석](#3-멀티채팅-정밀-분석)
4. [멀티라이브 ↔ 멀티채팅 연동 분석](#4-멀티라이브--멀티채팅-연동-분석)
5. [개선안 — 우선순위 P0~P3](#5-개선안--우선순위-p0p3)
6. [구현 로드맵](#6-구현-로드맵)
7. [부록: 파일 수정 맵](#부록-파일-수정-맵)

---

## 1. 현재 아키텍처 요약

### 1.1 전체 구조

```
┌──────────────────────────────────────────────────────────────────────┐
│                              AppState                                │
│  ┌────────────────────────┐         ┌────────────────────────────┐   │
│  │   MultiLiveManager     │         │   MultiChatSessionManager  │   │
│  │   @Observable @MainActor│         │   @Observable @MainActor   │   │
│  │  ─────────────────────  │         │  ────────────────────────  │   │
│  │  sessions: [MLSession]  │  ◀─?─▶  │  sessions: [ChatSession]   │   │
│  │  selectedSessionId      │         │  selectedChannelId         │   │
│  │  audioSessionId         │         │  + grid/merged ratios      │   │
│  │  isGridLayout           │         │                            │   │
│  │  gridLayoutMode         │         │  📌 두 매니저는 독립 동작   │   │
│  │  layoutRatios           │         │     → 연동 부재 (P1 이슈)  │   │
│  └─────────┬──────────────┘         └─────────┬──────────────────┘   │
│            │                                  │                      │
│   ┌────────▼─────────┐                ┌──────▼──────────┐            │
│   │ MultiLiveSession │                │   ChatSession   │            │
│   │  - playerVM      │                │  - chatVM       │            │
│   │  - chatVM (별개) │  ←—— 중복! ——→ │  - WebSocket    │            │
│   │  - engine        │                │                 │            │
│   └──────────────────┘                └─────────────────┘            │
│                                                                      │
│   ┌──────────────────────┐    ┌────────────────────────────┐         │
│   │ MultiLiveEnginePool  │    │  ReconnectionPolicy (Actor)│         │
│   │  (Actor)             │    │  지수 백오프 + 지터        │         │
│   │  VLC/AV/HLS.js 풀링  │    └────────────────────────────┘         │
│   └──────────────────────┘                                           │
│                                                                      │
│   ┌──────────────────────────────────────┐                           │
│   │ MultiLiveBandwidthCoordinator (Actor)│                           │
│   │  flashls P20 추정 + 가중 분배        │                           │
│   │  버퍼 히스테리시스 + 긴급 강등       │                           │
│   └──────────────────────────────────────┘                           │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.2 코드 규모 비교

| 측면 | MultiLive | MultiChat |
|------|-----------|-----------|
| 매니저/세션 | `MultiLiveManager` (~960) + `MultiLiveSession` (~750) | `MultiChatSessionManager` (~270) |
| 메인 뷰 | `MultiLiveView` (~210) + 그리드/탭바/오버레이/패인 (~1,480) | `MultiChatView` (~450) + `FollowingView+MultiChat` (~400) |
| 통합 뷰 | `MLSplitVideoChat` (~280, NSSplitView) | `MergedChatView` (~550) |
| 추가 기능 | EnginePool/Bandwidth/Settings (~1,300) | Engine/WebSocket/Parser/Reconnect/Models (~1,750) |
| 메시지 렌더 | (영상이라 없음) | `ChatMessageRow` (~550) + `ChatViewModel` (~1,100) |
| **총합** | **~5,750줄** | **~5,900줄** |

---

## 2. 멀티라이브 정밀 분석

### 2.1 잘 동작하는 부분 (Strengths)

| # | 항목 | 평가 |
|---|------|------|
| ✅ | **엔진 풀링** (`MultiLiveEnginePool`) | VLC/AVPlayer/HLS.js 타입별 idle 큐, `resetForReuse()` 패턴 |
| ✅ | **대역폭 코디네이터** | flashls 알고리즘 이식 — P20 백분위 + 가중 분배(선택 1.5배) + 버퍼 히스테리시스(3↔5s) |
| ✅ | **세션 복원** | UserDefaults 영속화 → 300ms 안정화 대기 → 500ms staggered 시작 → drawable 복구 |
| ✅ | **3가지 그리드** | preset(자동) / custom(드래그 리사이즈 30~70%) / focusLeft(70:30) |
| ✅ | **NSSplitView 격리** | VLC Metal 렌더 오버플로우 방지를 위한 AppKit 클리핑 |
| ✅ | **가속 예산(Rate Budget)** | 4세션 총 +12% (선택 +7.2% / 비선택 +4.8%) — Low-latency 페이싱과 연동 |
| ✅ | **엔진 전환 절차** | `stop() → detach() → release() → acquire() → inject() → yield(20ms) → start()` (블랙프레임 방지) |
| ✅ | **백그라운드 모드** | 비선택 세션은 720p + 짧은 버퍼 + 프레임 드롭 허용 |

### 2.2 문제점 (Pain Points)

#### 🔴 P0 — Drawable 재바인딩 취약성

- **현상**: VLC Metal 렌더 서피스 바인딩이 SwiftUI 레이아웃 패스에 민감함. drawable 복구 호출이 `restoreState`, `switchEngine`, `applyMultiLiveConstraints` 등 여러 지점에 산재.
- **영향**: 레이아웃 모드 전환 / 엔진 전환 / 복원 시 일시적 검은 화면(black flash) 발생 가능.
- **근거**: `MultiLiveManager.restoreState()` Phase 4의 `vlc.refreshDrawable()` + `switchEngine()` 내 `Task.yield() + 20ms sleep` 등 방어 코드 다수.

#### 🔴 P0 — Race condition 부분 해결

- **현상**: `addSession()`이 `await apiClient.liveDetail()` 후 다시 sessions/maxSessions 검증하지만, `addingChannelIds: Set<String>` 플래그에만 의존.
- **영향**: 동일 channelId를 매우 짧은 간격으로 두 번 호출 시 race 가능. 엔진 풀에서 중복 acquire 발생.
- **근거**: [ISSUE-4 Fix] 주석에서 부분 해결만 언급.

#### 🟡 P1 — Staggered 딜레이 하드코딩

- **현상**: 복원 시 `300ms 안정화 + 500ms × index` 고정.
- **영향**: 빠른 네트워크에선 느리고, 느린 네트워크에선 동시 connect로 CDN 거절 가능.
- **개선 방향**: 첫 세션의 manifest 응답 시간을 측정하여 동적 조정.

#### 🟡 P1 — 메모리 누수 리스크

- **현상**: `MultiLiveBandwidthCoordinator` 콜백, `MetricsForwarder` 참조가 일부 strong.
- **영향**: 세션 제거 후에도 actor 참조가 유지되어 ARC 해제 지연.

#### 🟡 P1 — 4개 동시 HLS = 16개 병렬 연결

- **현상**: 4 세션 × ~4 segment fetch thread = 최대 16 동시 connection.
- **영향**: ISP/공유기 NAT table 압박, 일부 모바일 핫스팟에서 throttling.
- **개선 방향**: HTTP/2 muxing 활용 또는 fetch concurrency cap.

#### 🟡 P1 — 채팅 동시 연결 16개 (4 ML × 4 MC)

- **현상**: 멀티라이브와 멀티채팅 세션이 독립이라 동일 채널을 시청 + 멀티채팅 모두 추가 시 WebSocket 2개 동시 유지.
- **개선 방향**: 동일 channelId의 chat WebSocket 공유 풀링.

#### 🟢 P2 — 오디오 동기화 부재

- **현상**: `isMultiAudioMode`로 여러 세션 음성 동시 재생 가능하지만, A/V sync가 세션 내부로만 한정.
- **영향**: 같은 e스포츠를 여러 캐스터로 동시 시청 시 약간의 시차.
- **개선 방향**: 마스터 세션 PTS 기반 슬레이브 오디오 보정 (구현 난이도 높음).

#### 🟢 P2 — 5+ 세션 그리드 변종 부재

- **현상**: 그리드는 1/2/3-4개만 가정. 6개 세션은 2x3 자동 배치 부재.
- **영향**: 설정에서 maxConcurrentSessions=6로 올려도 레이아웃 깨짐.

#### 🟢 P2 — 대역폭 조정 시각화 없음

- **현상**: 코디네이터 어드바이스가 내부 로그만 출력.
- **영향**: 디버깅/사용자 신뢰도 저하.
- **개선 방향**: 디버그 오버레이 또는 통계 패널.

---

## 3. 멀티채팅 정밀 분석

### 3.1 잘 동작하는 부분 (Strengths)

| # | 항목 | 평가 |
|---|------|------|
| ✅ | **세션 수 제한** | `maxSessions = 8`, `AddSessionResult` enum으로 명확한 피드백 |
| ✅ | **세션 영속화** | `SavedChatSession` 구조 + 마지막 선택 채널 복구 |
| ✅ | **3가지 레이아웃** | sidebar(탭) / grid(2x2 분할) / merged(통합 타임라인) |
| ✅ | **배치 페이싱** | 33ms 활성 / 3,000ms 비활성 + **적응형 drip** (count별 1~8개 상한) |
| ✅ | **이벤트 우선 flush** | 후원/구독/공지는 drip 페이싱 무시하고 즉시 노출 |
| ✅ | **백그라운드 메모리 절약** | 비활성 세션은 200→50개로 ring buffer 축소 |
| ✅ | **재연결 정책** | 지수 백오프(1→2→4→8s) + ±20% 지터 + 30초 안정 후 attempt 리셋 |
| ✅ | **전체 재연결 (TaskGroup)** | `reconnectAll()` 병렬 처리 |
| ✅ | **뱃지 시스템** | `UserRole` enum + 다중 뱃지(최대 3개) + 칭호 + 구독 티어 테두리 |
| ✅ | **닉네임 색상 적용** | `nicknameColor`가 UserRole 분기 (스트리머=치지직그린 / 매니저=#5C9DFF / 일반=hash 기반) |
| ✅ | **MergedChatView 증분 병합** | O(k log k) — Ring buffer eviction 3가지 케이스 모두 처리 |
| ✅ | **MergedChatView 리플레이** | 250ms debounce로 배치 노이즈 제거 + ESC 해제 |

### 3.2 문제점 (Pain Points)

#### 🔴 P0 — 그리드 모드 채팅 입력 불가 (실측 확인됨)

- **현상**: `MultiChatView.gridCell()` (L197~) 은 `ChatMessagesView`만 포함하고 **`ChatInputView` 부재**.
- **영향**: 그리드 모드를 선택하면 4개 채팅을 동시에 볼 수 있지만 **어떤 채널에도 메시지를 보낼 수 없다**. 기능 결손.
- **근거**:
  ```swift
  // MultiChatView.swift L196~236 — gridCell 본문 발췌
  private func gridCell(...) -> some View {
      VStack(spacing: 0) {
          // 채널 헤더 (이름, 카운트, X 버튼)
          ...
          ChatMessagesView(viewModel: session.chatViewModel)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          // ❌ ChatInputView 없음
      }
  }
  ```

#### 🔴 P0 — 통합 모드(Merged) 입력 불가

- **현상**: `MergedChatView`는 모든 세션의 메시지를 시간순으로 합쳐 보여주지만 입력창 자체가 없음.
- **영향**: 통합 모드 사용 중 댓글 작성 불가 → 모드 이탈 강요.
- **개선 방향**: 입력창 + 발송 채널 선택 드롭다운("어느 채널로 보낼지") 또는 "활성 탭 채널" 자동 선택.

#### 🟡 P1 — 비방송 채널 추가 시 무성 실패 흐름

- **현상**: `addSession()`은 `chatChannelId == nil`인 경우 `connectionFailed`를 거치지 않고 단순 무시 (호출처에서만 분기).
- **근거**: `FollowingView+MultiChat.addChatChannel()`의 switch에서 `.connectionFailed`는 `break`로 무시.
- **영향**: 사용자가 "왜 안 추가되지?" 모름.

#### 🟡 P1 — 세션 복원 부분 실패 피드백 없음

- **현상**: `restoreSessions()`이 채널별 do-catch로 silent fail.
- **영향**: 8개 저장 → 3개 오프라인 → 5개만 복구되는데 알림 없음.

#### 🟡 P1 — 재연결 진행 상태 UI 미표시

- **현상**: 탭에 dot(빨강)만 표시. attempt 횟수, 다음 재시도까지 남은 시간 등 정보 없음.
- **개선 방향**: 탭 hover tooltip 또는 헤더 상세 인디케이터.

#### 🟡 P1 — 그리드 5+ 세션 처리 부재

- **현상**: `gridContent`는 `count >= 3`을 모두 2x2로 처리. 5~8 세션은 일부만 표시.
- **개선 방향**: 3x3 / 동적 행렬 자동 산출.

#### 🟡 P1 — 동일 채널 멀티라이브+멀티채팅 동시 시 WebSocket 중복

- **현상**: MultiLiveSession은 자체 chatViewModel 보유, MultiChatSessionManager도 별도 chatViewModel 보유.
- **영향**: 같은 channelId를 두 곳에서 추가하면 동일 chat WebSocket 2개 (서버 부하 + 사용자 메시지가 두 번 echo).

#### 🟢 P2 — 활동 뱃지(activityBadges) 미렌더링

- **현상**: 모델에 `activityBadges: [ChatBadge]` 있지만 ChatMessageRow가 `badges`만 사용.
- **영향**: 활동 뱃지 정보 노출 안됨.

#### 🟢 P2 — 통합 뷰 8채널 시 CPU 부담

- **현상**: 33ms마다 8 세션 × 평균 20개 비교 = 4,800회/s 정렬 비교 (메인스레드).
- **영향**: 인기 채널 다수 추가 시 타이핑 끊김 가능성.
- **개선 방향**: `Task.detached(priority: .utility)`에서 병합 후 메인 스레드로 commit.

#### 🟢 P2 — 에코 필터 해시 충돌 가능

- **현상**: `"\(userId)_\(content.hashValue)"` 기반 5초 dedup → 동일 사용자가 5초 내 동일 메시지 재전송 시 미표시.
- **영향**: 매크로 채팅("ㅋ" 연타)이 일부 누락.
- **개선 방향**: 서버 message ID 기반 dedup으로 전환.

---

## 4. 멀티라이브 ↔ 멀티채팅 연동 분석

### 4.1 현재 상태: 완전 독립

| 측면 | 현재 동작 | 문제 |
|------|----------|------|
| 세션 모델 | `MultiLiveSession.chatVM` ↔ `MultiChatSessionManager.sessions[].chatVM` 별개 | 동일 채널 두 곳에서 시청 시 WebSocket 중복 |
| 상태 동기화 | 멀티라이브 추가 → 멀티채팅 자동 추가 안 됨 | 사용자가 두 번 작업 |
| UI 진입점 | 각 메뉴 분리 (멀티라이브 메뉴 / 팔로잉 → 멀티채팅 토글) | 동선 분산 |
| 채팅 풀링 | 없음 | 메모리/네트워크 낭비 |

### 4.2 통합 가능성 평가

#### 옵션 A: ChatSession 공유 풀 (추천)

```
┌────────────────────────────────────────────────────────┐
│              SharedChatSessionPool (actor)             │
│  channelId → ChatSession (refcounted)                  │
│  ─────────────────────────────────────────────────     │
│  acquire(channelId, owner: .multiLive | .multiChat)    │
│     → 기존 세션 있으면 retain++, 없으면 신규 생성      │
│  release(channelId, owner)                             │
│     → retain-- 후 0이면 disconnect + remove            │
└────────────────────────────────────────────────────────┘
              ▲                          ▲
              │                          │
   MultiLiveSession           MultiChatSessionManager
   (시청 시 acquire)            (추가 시 acquire)
```

- **장점**: WebSocket 1개로 양쪽 모두 채팅 표시. 메모리/네트워크 절약. 일관된 메시지 상태.
- **단점**: refcounting 라이프사이클 복잡. 백그라운드 모드 정책 충돌(시청 중=foreground / 멀티채팅 비활성=background).
- **해결**: `BackgroundMode = max(activeOwners.modes)` 정책으로 가장 활성화된 owner 기준 적용.

#### 옵션 B: Event Bus 동기화 (간단)

- 멀티라이브 추가 시 NotificationCenter로 멀티채팅에 신호 → 멀티채팅이 자동 추가.
- **단점**: WebSocket 중복은 여전. UX만 일치.

**권고**: Phase 1은 옵션 B(저비용 동기화), Phase 2에서 옵션 A(공유 풀) 단계 적용.

---

## 5. 개선안 — 우선순위 P0~P3

### 🔴 P0: 즉시 수정 (기능 결손 / 버그)

#### P0-1. 그리드 모드 채팅 입력 추가 ⭐
- **파일**: `Sources/CViewApp/Views/MultiChatView.swift`
- **변경**: `gridCell()` 하단에 컴팩트 `ChatInputView` 추가
- **세부**:
  - 셀 폭이 좁으므로 placeholder 짧게 ("메시지...")
  - 발송 버튼은 SF Symbol(`arrow.up.circle.fill`)만
  - Enter로 전송, Shift+Enter는 줄바꿈
  - 셀별 독립적 sendMessage 동작
- **예상 코드**:
  ```swift
  private func gridCell(session: ..., width: CGFloat, height: CGFloat) -> some View {
      VStack(spacing: 0) {
          gridCellHeader(session: session)
          Divider().opacity(DesignTokens.Opacity.divider)
          ChatMessagesView(viewModel: session.chatViewModel)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          Divider().opacity(DesignTokens.Opacity.divider)
          ChatInputView(viewModel: session.chatViewModel, compactMode: true)
              .frame(height: 32)
      }
  }
  ```
- **추가 작업**: `ChatInputView`에 `compactMode: Bool = false` 파라미터 추가 (좌우 패딩/폰트 축소).

#### P0-2. 통합 모드 채팅 입력 추가 ⭐
- **파일**: `Sources/CViewApp/Views/MergedChatView.swift`
- **변경**: 하단에 입력 영역 + 채널 선택 드롭다운
- **UX 정책**:
  - 기본 발송 대상 = `sessionManager.selectedSession`
  - 드롭다운으로 명시적 채널 변경 가능
  - 입력창 상단에 "→ 채널명" 라벨 표시 (혼동 방지)
- **예상 코드**:
  ```swift
  HStack(spacing: 8) {
      ChannelTargetPicker(
          sessions: sessionManager.sessions,
          selectedId: $targetChannelId
      )
      ChatInputView(viewModel: targetChatVM, compactMode: false)
  }
  ```

#### P0-3. Drawable 재바인딩 통합 게이트
- **파일**: `Sources/CViewPlayer/MultiLiveEnginePool.swift` + `Sources/CViewApp/Views/MultiLivePlayerPane.swift`
- **변경**: drawable 복구 호출을 단일 `MLDrawableCoordinator`로 통합
- **세부**: PlayerContainerView의 `attachVideoView()` 완료 콜백 후에만 `refreshDrawable()` 호출 (Promise 패턴).
- **효과**: 레이아웃 전환 / 엔진 전환 / 복원 시 black flash 제거.

#### P0-4. addSession Race 완전 봉쇄
- **파일**: `Sources/CViewApp/ViewModels/MultiLiveManager.swift`
- **변경**: `addSession`을 actor-isolated atomic operation으로 재작성
  ```swift
  private actor SessionGuard {
      var pending: Set<String> = []
      func tryReserve(_ id: String) -> Bool { pending.insert(id).inserted }
      func release(_ id: String) { pending.remove(id) }
  }
  ```
- **효과**: `addingChannelIds` 플래그 제거, race 완전 차단.

---

### 🟡 P1: 안정성 / UX 개선 (1~2주 내 권장)

#### P1-1. 동일 채널 ChatSession 공유 풀 (옵션 B 우선)
- **파일**: 신규 `Sources/CViewChat/SharedChatSessionPool.swift`
- **단계**:
  1. **Phase 1 (Event Bus)**: 멀티라이브 세션 추가 시 멀티채팅도 자동 추가 (NotificationCenter)
  2. **Phase 2 (refcount Pool)**: 동일 channelId WebSocket 1개로 통합
- **효과**: 사용자 작업량 감소 + 네트워크 부하 절감.

#### P1-2. 비방송 채널 추가 명시적 피드백
- **파일**: `MultiChatSessionManager.swift`
- **변경**: `addSession()`이 `chatChannelId == nil`이면 `.connectionFailed("현재 방송 중이 아닙니다")` 반환
- **호출처**: switch case에서 명시 처리 + 안내 토스트.
- **선택**: "방송 시작 시 자동 연결" 옵션 (백그라운드 polling, 30s 주기).

#### P1-3. 세션 복원 결과 토스트
- **파일**: `MultiChatSessionManager.swift`, `MultiLiveManager.swift`
- **변경**: `restoreSessions()` 반환값을 `RestoreSummary { restored: Int, failed: [(channelId, reason)] }`로 변경
- **UI**: 메인 화면에 "8개 중 3개 복원, 5개 오프라인" 토스트 (4초 노출).

#### P1-4. 재연결 진행 상태 UI 상세화
- **파일**: `Sources/CViewChat/ChatEngine.swift`, `Sources/CViewApp/Views/FollowingView+MultiChat.swift`
- **변경**:
  - `ChatEngine`이 `reconnectionProgress: ReconnectionProgress` 게시
    ```swift
    public struct ReconnectionProgress: Sendable {
        let attempt: Int
        let maxAttempts: Int
        let nextDelaySeconds: Double
    }
    ```
  - 탭 hover 시 tooltip 표시: "재연결 중... (3/12, 다음 시도 4.2s 후)"

#### P1-5. Staggered 딜레이 적응화
- **파일**: `MultiLiveManager.restoreState()`
- **변경**: 첫 세션의 manifest 응답 시간 측정 → `delay = max(200ms, manifestRTT × 1.5)` 동적 산출.

#### P1-6. 그리드 5+ 세션 동적 행렬
- **파일**: `MultiChatView.swift`, `MultiLiveGridLayouts.swift`
- **변경**: `gridDimensions(count: Int) -> (rows: Int, cols: Int)` 헬퍼 추가
  ```swift
  func gridDimensions(_ n: Int) -> (Int, Int) {
      switch n {
      case 1: return (1, 1)
      case 2: return (1, 2)
      case 3, 4: return (2, 2)
      case 5, 6: return (2, 3)
      case 7, 8: return (3, 3)
      default: return (4, 4)
      }
  }
  ```

#### P1-7. 메모리 누수 감사
- **대상**: `MultiLiveBandwidthCoordinator`, `MetricsForwarder`, `ChatEngine` 콜백
- **작업**: `[weak self]` 캡처 점검 + `deinit` 로그 추가하여 해제 검증.

---

### 🟢 P2: 기능 확장

#### P2-1. 활동 뱃지(activityBadges) 렌더링
- **파일**: `ChatMessageRow.swift`
- **변경**: `allBadges`에 `message.activityBadges` 포함, 표시 한도 5개로 확장.

#### P2-2. MergedChatView 백그라운드 병합
- **파일**: `MergedChatView.swift`
- **변경**: `mergeNewMessages()` 정렬 부분을 `Task.detached(priority: .userInitiated)`로 이동, 결과만 메인 스레드로 commit.
- **주의**: ChatMessageItem이 Sendable이므로 안전.

#### P2-3. 서버 message ID 기반 dedup
- **파일**: `ChatViewModel+Processing.swift`
- **변경**: 에코 필터 키를 `content.hashValue` 대신 `serverMessageId` 사용. (서버에서 echo back 시 동일 ID).

#### P2-4. 5+ 세션용 멀티라이브 그리드 변종
- **파일**: `MultiLiveGridLayouts.swift`
- **변경**: P1-6과 함께 2x3, 3x3 변종 추가.

#### P2-5. 대역폭 코디네이터 디버그 오버레이
- **파일**: 신규 `Sources/CViewApp/Views/MultiLiveBandwidthDebugOverlay.swift`
- **변경**: 각 세션의 `maxAllowedBitrate / cappedHeight / bufferPhase` 실시간 표시 (Cmd+Shift+B 토글).

---

### 🔵 P3: 미래 개선

| # | 항목 | 비고 |
|---|------|------|
| P3-1 | 오디오 PTP 동기화 | 마스터 세션 PTS 추적, 슬레이브 ±25ms 보정. 구현 난이도 매우 높음. |
| P3-2 | HTTP/2 muxing | 동일 호스트 segment fetch 다중화. ATS/URLSession config 검토 필요. |
| P3-3 | 4x4 (16 세션) 모드 | 미니 프리뷰 모드 + 클릭 시 1x1 확대. e스포츠 토너먼트용. |
| P3-4 | 채팅 통합 검색/필터 | 모든 세션에서 "키워드"가 들어간 메시지만 추출. |
| P3-5 | 다채널 동시 채팅 발송 | 한 입력으로 여러 채널 동시 발송 (체크박스). |

---

## 6. 구현 로드맵

### Sprint 1 (1주) — 기능 결손 즉시 수정
- [ ] P0-1: 그리드 모드 ChatInputView 추가
- [ ] P0-2: 통합 모드 입력 + 채널 선택
- [ ] P1-2: 비방송 채널 명시적 피드백
- [ ] P1-3: 세션 복원 결과 토스트

### Sprint 2 (1~2주) — 안정성 강화
- [ ] P0-3: Drawable 재바인딩 통합 게이트
- [ ] P0-4: addSession race 봉쇄 (SessionGuard actor)
- [ ] P1-4: 재연결 진행 UI
- [ ] P1-5: Staggered 딜레이 적응화
- [ ] P1-7: 메모리 누수 감사

### Sprint 3 (2주) — 멀티라이브 ↔ 멀티채팅 연동
- [ ] P1-1 Phase 1: Event Bus 동기화 (NotificationCenter)
- [ ] P1-1 Phase 2: SharedChatSessionPool refcount
- [ ] P1-6: 그리드 5+ 세션 동적 행렬

### Sprint 4 (선택) — 기능 확장
- [ ] P2-1: 활동 뱃지 렌더링
- [ ] P2-2: Merged 백그라운드 병합
- [ ] P2-3: 서버 ID 기반 dedup
- [ ] P2-5: 디버그 오버레이

---

## 7. 핵심 효과 예측

| 항목 | 현재 | 개선 후 |
|------|------|---------|
| 그리드 모드 채팅 발송 | ❌ 불가 | ✅ 셀별 입력 |
| 통합 모드 채팅 발송 | ❌ 불가 | ✅ 채널 선택 후 발송 |
| 동일 채널 동시 시청 + MC 시 WebSocket | 2개 | 1개 (공유 풀) |
| 4 세션 복원 시 black flash | 빈번 | 거의 없음 |
| 재연결 상태 가시성 | dot only | tooltip 상세 |
| 5~8 세션 그리드 | 잘림 | 정상 표시 |
| 비방송 채널 추가 피드백 | 무성 실패 | 명확한 안내 |
| 메모리 사용량(8 세션) | ~350MB | ~280MB (공유 풀 + 누수 수정) |

---

## 부록: 파일 수정 맵

```
Sources/
├── CViewChat/
│   ├── SharedChatSessionPool.swift        🆕 P1-1 채팅 공유 풀
│   ├── ChatEngine.swift                   ✏️  P1-4 ReconnectionProgress 게시
│   └── ReconnectionPolicy.swift           (변경 없음)
│
├── CViewApp/
│   ├── Services/
│   │   └── MultiChatSessionManager.swift  ✏️  P1-2 비방송 피드백, P1-3 RestoreSummary
│   ├── ViewModels/
│   │   ├── MultiLiveManager.swift         ✏️  P0-4 SessionGuard, P1-5 적응 딜레이
│   │   ├── MultiLiveSession.swift         ✏️  P1-1 공유 풀 acquire/release
│   │   └── ChatViewModel+Processing.swift ✏️  P2-3 서버 ID dedup
│   └── Views/
│       ├── MultiChatView.swift            ✏️  P0-1 grid 입력, P1-6 동적 행렬
│       ├── MergedChatView.swift           ✏️  P0-2 입력+채널 선택, P2-2 백그라운드 병합
│       ├── ChatInputView.swift            ✏️  compactMode 파라미터
│       ├── ChatMessageRow.swift           ✏️  P2-1 activityBadges
│       ├── FollowingView+MultiChat.swift  ✏️  P1-2,3,4 UI 노출
│       ├── MultiLivePlayerPane.swift      ✏️  P0-3 Drawable Coordinator 연동
│       ├── MultiLiveGridLayouts.swift     ✏️  P1-6 5~8 세션 변종
│       └── MultiLiveBandwidthDebugOverlay.swift  🆕 P2-5
│
└── CViewPlayer/
    ├── MultiLiveEnginePool.swift          ✏️  P0-3 attach 완료 콜백
    └── MLDrawableCoordinator.swift        🆕 P0-3 통합 게이트
```

**예상 변경 라인 수**: 신규 ~600줄 / 수정 ~900줄 / 합계 약 **1,500줄** (전체 11,650줄의 ~13%)

---

## 결론

CView_v2의 멀티라이브/멀티채팅은 **이미 정교한 아키텍처**(엔진 풀, 대역폭 조정자, 적응형 배치, 증분 병합 등)를 갖추고 있으나, 다음 두 영역에서 즉시 개선이 필요합니다:

1. **기능 결손 (P0)**: 그리드/통합 모드의 채팅 입력 부재 — 사용자 가치 손실 직접적
2. **연동 부재 (P1)**: 멀티라이브와 멀티채팅이 독립 동작 — 동일 채널 중복 자원 사용

P0~P1 작업(약 4주)으로 일상 사용성이 크게 향상되고, P2~P3는 점진적 확장으로 충분합니다.

> **다음 단계**: Sprint 1의 P0-1, P0-2 구현을 먼저 진행 권장. 코드 레벨 PR 단위로 분해 가능.

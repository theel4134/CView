# CView_v2 채팅 시스템 정밀 분석

> 분석 일시: 2025-01  
> 분석 대상: 총 17개 파일, 5,900+ 라인  
> 대상 모듈: CViewChat, CViewApp(ViewModels/Views), CViewCore(Models), CViewUI

---

## 목차

1. [아키텍처 개요](#1-아키텍처-개요)
2. [네트워크 계층 — WebSocket](#2-네트워크-계층--websocket)
3. [프로토콜 파싱](#3-프로토콜-파싱)
4. [엔진 — 오케스트레이터](#4-엔진--오케스트레이터)
5. [모더레이션 서비스](#5-모더레이션-서비스)
6. [재연결 정책](#6-재연결-정책)
7. [ViewModel 계층](#7-viewmodel-계층)
8. [뷰 계층](#8-뷰-계층)
9. [이모티콘 시스템](#9-이모티콘-시스템)
10. [자동완성](#10-자동완성)
11. [TTS (Text-to-Speech)](#11-tts-text-to-speech)
12. [데이터 모델](#12-데이터-모델)
13. [성능 최적화 요약](#13-성능-최적화-요약)
14. [치지직 웹 채팅 대비 비교](#14-치지직-웹-채팅-대비-비교)
15. [CView 전용 우위 기능](#15-cview-전용-우위-기능)
16. [구현 격차 및 권장 로드맵](#16-구현-격차-및-권장-로드맵)

---

## 1. 아키텍처 개요

```
┌────────────────────────────────────────────────────────────────┐
│  View Layer (SwiftUI, @MainActor)                              │
│  ┌─────────────┐ ┌──────────────┐ ┌────────────────────────┐  │
│  │ChatPanelView│ │ChatOverlayView│ │MergedChatView (멀티)   │  │
│  └─────┬───────┘ └──────┬───────┘ └────────┬───────────────┘  │
│        └────────────┬───┘                   │                  │
│              ┌──────▼────────┐              │                  │
│              │ ChatViewModel │◄─────────────┘                  │
│              │ (@Observable) │                                  │
│              └──────┬────────┘                                  │
│                     │ .handleEvent()                            │
├─────────────────────┼──────────────────────────────────────────┤
│  Engine Layer       │ (actor-isolated, Sendable)               │
│              ┌──────▼────────┐                                  │
│              │  ChatEngine   │── ChatEngineEvent (AsyncStream)  │
│              │  (actor)      │                                   │
│              └─┬─────────┬──┘                                   │
│                │         │                                      │
│     ┌──────────▼──┐  ┌──▼──────────────┐                      │
│     │WebSocket    │  │ChatMessage      │                       │
│     │Service      │  │Parser           │                       │
│     │(actor)      │  │(Sendable struct)│                       │
│     └─────────────┘  └─────────────────┘                       │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │ChatModeration    │  │Reconnection      │                    │
│  │Service (actor)   │  │Policy (actor)    │                    │
│  └──────────────────┘  └──────────────────┘                    │
├─────────────────────────────────────────────────────────────────┤
│  Model Layer (CViewCore, Sendable)                              │
│  ChatMessage · ChatMessageItem · ChatProfile · ChatBadge       │
│  EmoticonPack · EmoticonItem · ChatContentSegment              │
│  StreamAlertItem · AutocompleteTrigger · ChatSettings          │
│  ChatMessageBuffer (ring buffer)                                │
└─────────────────────────────────────────────────────────────────┘
```

### 설계 원칙

| 원칙 | 적용 |
|------|------|
| **Swift 6 strict concurrency** | 전 계층 actor 또는 Sendable — data race 원천 차단 |
| **관심사 분리** | WebSocket → Parser → Engine → ViewModel → View, 단방향 데이터 흐름 |
| **계층 간 통신** | AsyncStream (이벤트), async/await (명령) |
| **off-MainActor 파싱** | `nonisolated static func parseOffActor` — 멀티코어 활용 |
| **배치 렌더링** | 250ms flush interval로 SwiftUI 업데이트 빈도 제한 |

---

## 2. 네트워크 계층 — WebSocket

**파일**: `Sources/CViewChat/WebSocketService.swift` (385줄)

### 커넥션 라이프사이클

```
State: disconnected → connecting → connected → disconnecting → disconnected
                                           └→ failed(reason)
```

| 항목 | 값 |
|------|----|
| URL 패턴 | `wss://kr-ss{N}.chat.naver.com/chat` (N = 1~9) |
| 서버 선택 | `chatChannelId` UTF-8 바이트 합 % 9 + 1 |
| Ping 간격 | 20초 |
| Max 메시지 크기 | 64KB |
| Request timeout | 90초 |
| Resource timeout | 900초 |

### HTTP 헤더

```swift
"Origin": "https://chzzk.naver.com"
"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)..."
"Sec-WebSocket-Extensions": "permessage-deflate"
// + NID_AUT, NID_SES 쿠키 (로그인 시)
```

### Ping/Pong 메커니즘

- `Mutex<UnsafeContinuation?>` 로 ping 응답 대기 guard
- 10초 타임아웃 → 1회 재시도 → 실패 시 연결 종료
- 동시 ping 요청 방지 (이전 continuation 취소 후 교체)

### 메시지 전달

- `AsyncStream<URLSessionWebSocketTask.Message>` 로 수신 메시지 비동기 전달
- `AsyncStream<State>` 로 상태 변경 전달
- 수신 루프: `receiveLoop()` 에서 재귀적 `.receive()` 호출

---

## 3. 프로토콜 파싱

**파일**: `Sources/CViewChat/ChatMessageParser.swift` (789줄)

### 치지직 채팅 프로토콜 명령 (18종)

| 코드 | 명령 | 방향 | 설명 |
|------|------|------|------|
| 0 | `ping` | ← Server | 서버 핑 |
| 10000 | `pong` | → Server | 클라이언트 퐁 |
| 100 | `connect` | → Server | 인증 연결 요청 |
| 10100 | `connected` | ← Server | 연결 완료 응답 |
| 5101 | `requestRecentChat` | → Server | 최근 메시지 요청 |
| 15101 | `recentChat` | ← Server | 최근 메시지 응답 |
| 3101 | `sendChat` | → Server | 메시지 전송 요청 |
| 13101 | `sendChatResponse` | ← Server | 전송 응답 |
| 93101 | `chatMessage` | ← Server | 실시간 채팅 메시지 |
| 93102 | `donation` | ← Server | 후원 메시지 |
| 93103 | `emoteMessage` | ← Server | 이모트 메시지 |
| 93006 | `systemMessage` | ← Server | 시스템 메시지 |
| 94005 | `kick` | ← Server | 추방 알림 |
| 94008 | `blind` | ← Server | 메시지 블라인드 |
| 94010 | `notice` | ← Server | 공지 메시지 |
| 94015 | `penalty` | ← Server | 패널티 알림 |
| 3103 | `sendEmote` | → Server | 이모트 전송 |

### 파싱 아키텍처

```swift
struct ChatMessageParser: Sendable {
    // 상태 비저장 (Stateless) — 완전한 thread-safety
    
    func parseFrame(_ data: Data) -> (command: ChzzkChatCommand, body: [String: Any])?
    func parseMessages(_ body: [String: Any]) -> [ChatMessage]
    func parseDonations(_ body: [String: Any]) -> [ChatMessage]
    func parseProfile(_ dict: [String: Any]) -> ChatProfile
    func parseExtras(_ dict: [String: Any]) -> ChatExtras
}
```

### 프로필 파싱 — Dual Path

프로필(`profile` 필드)이 두 가지 형태로 올 수 있음:

1. **JSON 문자열** (String) → JSONSerialization 디코딩
2. **딕셔너리** (AnyCodable) → 직접 접근

### 뱃지 체계 (3중 소스)

| 소스 | 필드 | 설명 |
|------|------|------|
| 기본 뱃지 | `badge.imageUrl` | 역할 뱃지 (스트리머/매니저) |
| 구독 뱃지 | `streamingProperty.subscription.badge.imageUrl` | 구독 등급 뱃지 |
| 시청자 뱃지 | `viewerBadges[].badge.imageUrl` | 팬뱃지 등 |
| 활동 뱃지 | `activityBadges[].imageUrl` | 활동 기반 뱃지 |

### 메시지 ID 충돌 방지

```swift
// 원본: {uid}_{msgTime}
// 문제: 동시 전송 시 같은 uid+timestamp 충돌 가능
// 해결: monotonic _msgSequence 카운터 추가
"\(uid)_\(msgTime)_\(_msgSequence)"
```

### 빌드 메시지

| 메시지 | 주요 필드 |
|--------|----------|
| `connectMessage` | svcid: "game", ver: "3", auth: "SEND"/"READ", devName: "CView_v2" |
| `sendMessage` | chatType: "STREAMING", emojis, extraToken |
| `recentChatRequest` | recentMessageCount: 50 |
| `pong` | ver: "3" |

---

## 4. 엔진 — 오케스트레이터

**파일**: `Sources/CViewChat/ChatEngine.swift` (467줄)

### ChatEngineEvent (12종)

```swift
enum ChatEngineEvent {
    case connected
    case disconnected(reason: String?)
    case reconnecting
    case stateChanged(ChatConnectionState)
    case newMessages([ChatMessage])
    case recentMessages([ChatMessage])
    case donations([ChatMessage])
    case notice(ChatMessage)
    case messageBlinded(messageId: String)
    case kicked
    case userPenalized(userId: String, penaltyType: String?)
    case systemMessage(String)
    case messagesCleared
}
```

### 이벤트 처리 흐름

```
WebSocket 메시지 수신
  ↓
nonisolated parseOffActor (멀티코어)
  ↓
actor 내부 handleParsedFrame
  ↓
ChatEngineEvent 발행 (AsyncStream)
  ↓
ChatViewModel.handleEvent (MainActor)
```

### 연결 시퀀스

1. `connect()` → WebSocketService 연결
2. WSS 연결 성공 → `connectMessage` 전송 (auth: SEND/READ)
3. `connected` 응답 수신 → `requestRecentMessages` 전송
4. `recentChat` 수신 → ViewModel에 메시지 전달
5. 이후 실시간 `chatMessage`, `donation` 등 수신

### 상태 동기화

- WebSocketService 상태 변경 → `stateChanged` 이벤트 발행
- 연결 끊김 → ReconnectionPolicy에 위임
- 중복 reconnect 방지: `reconnectTask?.cancel()` 후 새 Task 생성

---

## 5. 모더레이션 서비스

**파일**: `Sources/CViewChat/ChatModerationService.swift` (332줄)

### 슬래시 명령 (13종)

| 명령 | 권한 | 유형 | 설명 |
|------|------|------|------|
| `/mute {user} [duration]` | 매니저 | 서버 | 사용자 채팅금지 |
| `/unmute {user}` | 매니저 | 서버 | 채팅금지 해제 |
| `/ban {user}` | 매니저 | 서버 | 영구 차단 |
| `/unban {user}` | 매니저 | 서버 | 영구 차단 해제 |
| `/slow [seconds]` | 매니저 | 서버 | 슬로우 모드 설정 |
| `/clear` | 매니저 | 서버 | 채팅 전체 클리어 |
| `/notice {text}` | 매니저 | 서버 | 공지 메시지 |
| `/host {channel}` | 매니저 | 서버 | 호스팅 |
| `/filter` | 로컬 | 클라이언트 | 키워드 필터 토글 |
| `/export` | 로컬 | 클라이언트 | 채팅 로그 내보내기 |
| `/block {user}` | 로컬 | 클라이언트 | 사용자 차단 (로컬) |
| `/unblock {user}` | 로컬 | 클라이언트 | 차단 해제 (로컬) |
| `/help` | 로컬 | 클라이언트 | 명령어 도움말 |

### 필터 시스템

```swift
enum ChatFilterType {
    case keyword([String])       // 대소문자 무시 포함 검사
    case regex(String)           // NSRegularExpression 컴파일 + 캐싱
    case user([String])          // userId 목록 기반 필터
    case donationOnly            // 후원 메시지만 표시
}
```

### 메시지 필터링 파이프라인

```
수신 메시지 배열
  ↓ isBlocked(userId) 체크 — 차단 사용자 제거
  ↓ isMuted(userId) 체크 — 채팅금지 사용자 제거
  ↓ content filter 적용 — keyword/regex/donationOnly
  ↓ 필터링된 메시지 배열 반환
```

---

## 6. 재연결 정책

**파일**: `Sources/CViewChat/ReconnectionPolicy.swift` (206줄)

### 설정 프리셋

| 파라미터 | 기본 (default) | 공격적 (aggressive) |
|----------|---------------|-------------------|
| initialDelay | 1.0초 | 0.5초 |
| maxDelay | 30초 | 10초 |
| maxAttempts | 10회 | 20회 |
| backoffMultiplier | 2.0 | 1.5 |
| jitterFactor | 0.25 | 0.15 |
| resetThreshold | 60초 | 30초 |

### 상태 머신

```
idle → waiting(delay) → connecting → connected
                                   ↓
                               exhausted (최대 시도 초과)
```

### 지터 연산

```swift
let jitter = baseDelay * config.jitterFactor * Double.random(in: -1...1)
let delay = min(baseDelay + jitter, config.maxDelay)
```

### 서킷 브레이커

- 연결 성공 후 `resetThreshold` 이상 유지 → 시도 카운트 리셋
- 짧은 시간 내 반복 실패 → `exhausted` 상태 진입

---

## 7. ViewModel 계층

**파일**: `Sources/CViewApp/ViewModels/ChatViewModel.swift` (606줄)  
**파일**: `Sources/CViewApp/ViewModels/ChatViewModel+Processing.swift` (~290줄)  
**파일**: `Sources/CViewApp/ViewModels/ChatViewModel+Autocomplete.swift` (~180줄)

### 핵심 데이터 구조

| 구조 | 타입 | 용량 | 용도 |
|------|------|------|------|
| `messages` | `ChatMessageBuffer` (ring buffer) | 200 | 현재 표시 메시지 (O(1) append/eviction) |
| `chatHistory` | `[ChatMessageItem]` | 2,500 | 히스토리 (리플레이 모드) |
| `pendingMessages` | `[ChatMessageItem]` | 64 (예약) | 배치 대기열 |
| `seenMessageIDs` | `Set<String>` | 400 (cap) | 중복 메시지 방지 |
| `recentChatters` | `[MentionSuggestion]` | 100 | @멘션 자동완성 |
| `collectedEmoticons` | `[String: URL]` | 동적 | 채팅에서 수집된 이모티콘 |

### 배치 플러시 메커니즘

```
메시지 수신 → pendingMessages에 축적
               ↓ (250ms 간격, 백그라운드: 1초)
           flushPendingMessages()
               ↓ 중복 필터 (seenMessageIDs)
               ↓ TTS 큐잉
               ↓ recentChatters 업데이트
               ↓ chatHistory 추가
               ↓ 증분 통계 업데이트
               ↓ messages에 일괄 추가 (SwiftUI 1회 업데이트)
```

**효과**: SwiftUI 업데이트 빈도 1000/s → ~4/s (250ms flush)

### 증분 통계 캐시

```swift
uniqueUserCount: Int        // O(batch) 증분 (Set 기반)
donationCount: Int          // 후원 횟수
totalDonationAmount: Int    // 후원 총액
subscriptionCount: Int      // 구독 횟수
messagesPerSecond: Double   // 5초 윈도우 이동 평균 (3초 갱신)
```

### 리플레이 모드

```
자동 스크롤 ON ←→ 위로 스크롤 시 OFF (250ms debounce)
                    ↓
              리플레이 모드 진입
              · 새 메시지 unreadCount에 누적
              · 배지 UI로 미읽음 수 표시
              · "↓" 버튼으로 최신으로 복귀
```

### 디스플레이 모드

| 모드 | 설명 | 뷰 |
|------|------|----|
| `.side` | HSplitView 오른쪽 패널 | ChatPanelView |
| `.overlay` | 플레이어 위 반투명 오버레이 | ChatOverlayView |
| `.hidden` | 채팅 비표시 | — |

### 설정 동기화

```swift
applySettings(_ settings: ChatSettings)  // SettingsStore → ViewModel
exportSettings(base:) → ChatSettings     // ViewModel → SettingsStore 스냅샷
```

24개 설정 항목 양방향 동기화: 폰트 크기, 투명도, 라인 스페이싱, 타임스탬프, 뱃지, 하이라이트, 이모티콘, 후원, TTS, 오버레이 크기 등

### 스트림 알림

```
후원/구독/공지 메시지 수신
  ↓ StreamAlertItem 변환
  ↓ enqueueStreamAlert()
  ↓ 최대 3개 동시 표시
  ↓ 5초 후 자동 해제 (애니메이션)
```

### 로컬 메시지 에코

치지직 서버는 본인 메시지를 에코백하지 않음 → `sendMessage()` 시 로컬에서 직접:
- `ChatMessageItem` 생성 (uid + 마이크로초 타임스탬프 ID)
- 배치 우회 → 즉시 `messages.append()` — 입력 즉시 반영

---

## 8. 뷰 계층

### ChatPanelView (433줄)

**구조:**
```
ChatPanelView
├── 헤더 (연결 상태, 채널 이름, 설정 버튼)
├── 고정 메시지 배너 (pinnedMessage)
├── ChatMessagesView
│   ├── ScrollViewReader + LazyVStack
│   ├── ForEach(messages) → EquatableChatMessageRow
│   ├── 자동 스크롤 + onScrollGeometryChange
│   └── 리플레이 모드 "↓ N" 버튼
└── ChatInputView
```

**최적화 포인트:**
- `EquatableChatMessageRow`: message + config 동일성 비교로 불필요한 재렌더 방지
- `.defaultScrollAnchor(.bottom)` — 기본 앵커 하단
- 스크롤 위치 감지: `onScrollGeometryChange` — 컨테이너 높이 10% 적응형 임계값

### ChatOverlayView (335줄)

**특징:**
- 드래그 이동 (position clamp) + 리사이즈 핸들 (240×200 ~ 600×800)
- 호버 시만 제어 UI 표시 (사이드 전환, 숨기기)
- GPU 최적화: Material blur → 솔리드 반투명 색상 (매 프레임 blur 커널 재계산 제거)
- Shadow radius 12→4 축소 (offscreen pass 비용 절감)
- 오버레이 전용 `OverlayChatMessageRow`: compact 레이아웃, shadow text, 3줄 제한
- 닉네임 색상: userId 해시 기반 10색 자동 할당

### ChatInputView (214줄)

**구성:**
```
ChatInputView
├── 로그인 필요 배너 (connected but no uid)
├── 이모티콘 피커 버튼 (popover)
├── Glass TextField (focus state, chzzkGreen 테두리 glow)
├── 자동완성 팝업 (↑↓ 이동, Tab 선택, Esc 닫기)
└── 전송 버튼 (pill circle, green when ready)
```

**canSend 조건**: `connectionState.isConnected && currentUserUid != nil`

### ChatMessageRow (640줄)

**메시지 타입별 렌더링:**

| 타입 | 렌더링 |
|------|--------|
| **일반** | Text concat (닉네임 + ": " + 메시지), ChatContentRenderer |
| **후원** | 4-tier 금액별 그라데이션 카드 (1K/5K/10K/50K+) |
| **구독** | 티어 + 마일스톤 (개월수) 카드 |
| **공지** | 상단 고정 스타일 배너 |
| **시스템** | 중앙 정렬 작은 텍스트 |

**닉네임 렌더링:**
- 역할 아이콘: 스트리머 🎬, 매니저 🔧
- 뱃지: badge/subscription/viewer/activity 순서 표시
- 타임스탬프: monospaced, 작은 글씨

**호버 액션:**
- 닉네임 클릭 → ChatUserProfileSheet
- 복사, 차단, 하이라이트 토글

### MergedChatView (151줄)

**멀티 채널 병합 채팅:**
- 8가지 채널 구분 색상 (빨/초/파/노/분/보/오/청)
- 500ms 재빌드 타이머 (debounce)
- 최대 300 메시지
- EquatableChatMessageRow 재사용

### ChatUserProfileSheet (~150줄)

**프로필 팝업:**
- 프로필 이미지 (CachedAsyncImage)
- 닉네임 + 역할 뱃지
- 칭호 (titleName + hex 색상)
- 뱃지 목록 (최대 5개)
- 사용자 ID (monospaced)
- 액션: 닉네임 복사, 메시지 복사, 치지직 열기, 차단

### 기타 뷰

| 뷰 | 줄 수 | 기능 |
|----|-------|------|
| BlockedUsersView | ~100 | 차단 목록 관리 (검색 + 해제) |
| KeywordFilterView | ~350 | 키워드/사용자 필터 (2탭: keywords/users) |
| ChatExportView | ~150 | 채팅 로그 내보내기 (text/json/csv, 타입 필터) |
| ChatAutocompleteView | 176 | 이모티콘/멘션 자동완성 팝업 |

---

## 9. 이모티콘 시스템

### 이모티콘 데이터 흐름

```
API 로드 (EmoticonDeploy)
  ↓ emoticonPacks ([EmoticonPack])
  ↓ channelEmoticons (retroactive enrichment)
  ↓ 프리페치 (ImageCacheService.shared)
  
채팅 수신 시
  ↓ msg.extras.emojis 수집 → collectedEmoticons
  ↓ 새 URL 발견 시 백그라운드 프리페치
  ↓ enrichWithChannelEmoticons (merge into item)
```

### 이모티콘 소스 (3중)

| 소스 | 출처 | 우선순위 |
|------|------|----------|
| `emoticonPacks` | API 응답 | 1순위 |
| `channelEmoticons` | 채널 설정 | 2순위 |
| `collectedEmoticons` | 채팅에서 수집 | 3순위 |

### 이모티콘 렌더링

```swift
EmoticonParser.parse(content:emojis:) → [ChatContentSegment]
  .text(String)      → Text 뷰
  .emoticon(id, url) → EmoticonImageView (GIF: AnimatedGIFView / 정적: CachedAsyncImage)
```

**FlowLayout** (Layout 프로토콜): 텍스트·이모티콘 혼합을 좌→우→줄바꿈 방식 배치

**최적화**: 이모티콘 없는 메시지 → 순수 `Text` 렌더 (FlowLayout 오버헤드 제거)

### 이모티콘 피커

- `EmoticonPickerView` (380×340)
- 팩 선택 탭바 (가로 스크롤)
- 검색바 + 6열 52pt 그리드
- 클릭 시 `{:emoticonId:}` 패턴 입력

---

## 10. 자동완성

### 트리거 감지

```swift
// 커서 앞 텍스트에서 정규식 매칭
":"  → :[a-zA-Z0-9_가-힣]{1,20}$ → 이모티콘 모드
"@"  → @[a-zA-Z0-9_가-힣]{0,20}$ → 멘션 모드
```

### 이모티콘 자동완성

- 소스: `gatherAllEmoticons()` — 3중 소스 통합
- 매칭: displayName + emoticonId 부분 일치 (대소문자 무시)
- 최대 8개 제안
- 적용: 트리거 range를 `{:emoticonId:}`로 교체

### 멘션 자동완성

- 소스: `recentChatters` (최근 100명, 최신순)
- 빈 쿼리시 최근 8명 표시
- 매칭: nickname 부분 일치
- 적용: 트리거 range를 `@nickname `로 교체

### 키보드 인터랙션

| 키 | 동작 |
|----|------|
| ↑/↓ | 선택 이동 (순환) |
| Tab/Enter | 선택 항목 적용 |
| Esc | 팝업 닫기 |

---

## 11. TTS (Text-to-Speech)

**파일**: `Sources/CViewApp/ViewModels/ChatTTSService.swift` (~100줄)

| 항목 | 값 |
|------|----|
| 엔진 | AVSpeechSynthesizer |
| 큐 | 최대 5개 대기 |
| 대상 | 후원 + 구독 메시지 |
| 설정 | isEnabled, volume, rate |
| 포맷 | "닉네임님이 10000원 후원. 응원 메시지" |

---

## 12. 데이터 모델

### ChatMessage (도메인 모델)

```swift
struct ChatMessage {
    id, userId, nickname, content, timestamp
    type: MessageType  // normal|donation|subscription|systemMessage|notice
    profile: ChatProfile?
    extras: ChatExtras?
}
```

### ChatMessageItem (뷰 모델)

```swift
struct ChatMessageItem: Identifiable, Equatable, Hashable {
    // 21 properties — ChatMessage를 평탄화
    id, userId, nickname, content, timestamp, type
    badgeImageURL, emojis, donationAmount, donationType
    subscriptionMonths, profileImageUrl, isNotice, isSystem
    userRole, badges, titleName, titleColor
    
    init(from: ChatMessage)          // 변환 생성자
    static func system(_) -> Self    // 시스템 메시지 팩토리
}
```

### ChatConnectionState

```swift
enum ChatConnectionState {
    case disconnected
    case connecting
    case connected(serverIndex: Int)
    case reconnecting(attempt: Int)
    case failed(reason: String)
    
    var isConnected: Bool
}
```

### ChatMessageBuffer (링 버퍼)

```swift
struct ChatMessageBuffer: RandomAccessCollection {
    // capacity: 200 (기본), O(1) append + eviction
    func append(_), append(contentsOf:)
    func removeAll(where:), replaceAll(with:)
    func mapInPlace(_)  // 채널 이모티콘 소급 적용
    func toArray() → [ChatMessageItem]
}
```

### ChatSettings (영속 설정)

24개 항목: fontSize, chatOpacity, lineSpacing, showTimestamp, showBadge, highlightMentions, highlightRoles, maxVisibleMessages, emoticonEnabled, showDonation, showDonationsOnly, autoScroll, chatFilterEnabled, blockedWords, blockedUsers, ttsEnabled, ttsVolume, ttsRate, displayMode, overlayWidth, overlayHeight, overlayBackgroundOpacity, overlayShowInput

---

## 13. 성능 최적화 요약

| 기법 | 위치 | 효과 |
|------|------|------|
| **배치 플러시** (250ms) | ViewModel | SwiftUI 업데이트 1000/s → 4/s |
| **링 버퍼** (200 cap) | ChatMessageBuffer | O(1) append, 메모리 고정 |
| **증분 통계** | ViewModel | O(n) computed → O(batch) 증분 |
| **nonisolated 파싱** | ChatEngine/Parser | 멀티코어 파싱 (off-MainActor) |
| **seenMessageIDs 400 cap** | ViewModel | Set 무한 증가 방지 |
| **FlowLayout 조건부** | EmoticonViews | 이모티콘 없으면 Text 직접 렌더 |
| **EquatableChatMessageRow** | ChatMessageRow | msg+config 동일 시 재렌더 스킵 |
| **GPU: 솔리드 반투명** | ChatOverlayView | Material blur 제거 → alpha compositing만 |
| **GPU: shadow 축소** (4px) | ChatOverlayView | offscreen pass 비용 절감 |
| **GPU: shadow 축소** (8px) | AutocompleteView | shadow blur 연산 절반 |
| **이미지 프리페치** | Processing | 이모티콘 미리 다운로드 |
| **백그라운드 모드** (1s flush) | ViewModel | 비활성 세션 CPU 절약 |
| **히스토리 2500 cap** | ViewModel | 메모리 상한 |
| **recentChatters 100 cap** | Autocomplete | 멘션 캐시 상한 |
| **스크롤 debounce** (250ms) | ViewModel | replay 진입/해제 반복 방지 |

---

## 14. 치지직 웹 채팅 대비 비교

### ✅ 동등 구현

| 기능 | 웹 | CView | 비고 |
|------|----|---------|----|
| 실시간 메시지 표시 | ✅ | ✅ | 동일 WebSocket 프로토콜 |
| 채팅 메시지 전송 | ✅ | ✅ | auth SEND/READ 구분 |
| 후원(치즈) 메시지 | ✅ | ✅ | 4-tier 금액별 카드 |
| 구독 메시지 | ✅ | ✅ | 티어 + 마일스톤 |
| 이모티콘 | ✅ | ✅ | GIF 지원, 3중 소스 |
| 이모티콘 피커 | ✅ | ✅ | 팩 탭 + 검색 + 그리드 |
| 뱃지 표시 | ✅ | ✅ | 3중 소스 (기본/구독/시청자) |
| 칭호 표시 | ✅ | ✅ | titleName + hex 색상 |
| 공지 메시지 | ✅ | ✅ | notice 이벤트 처리 |
| 메시지 블라인드 | ✅ | ✅ | blind 이벤트 → 메시지 제거 |
| 추방 알림 | ✅ | ✅ | kick 이벤트 → 연결 종료 |
| 유저 패널티 | ✅ | ✅ | penalty 이벤트 로그 |
| 시스템 메시지 | ✅ | ✅ | systemMessage 이벤트 |
| 닉네임 클릭 프로필 | ✅ | ✅ | ChatUserProfileSheet |

### ⚠️ 부분 구현 / 차이

| 기능 | 웹 | CView | 차이점 |
|------|----|---------|----|
| 고정 메시지 (핀) | 서버 기반 | 로컬 전용 | 서버 pin API 미연동 |
| 채팅 규칙 표시 | 채팅창 상단 | 미구현 | 채팅 규칙 API 조회 없음 |
| 슬로우 모드 | 서버 제어 | /slow 명령 | 타이머 UI 없음 |
| 매니저 모드 UI | 전용 패널 | 슬래시 명령 | 전용 관리 UI 없음 |

### ❌ 미구현

| 기능 | 웹 설명 | 우선순위 |
|------|---------|----------|
| **미션 시스템** | 치즈 모금 목표+진행률, 미션 생성/종료, 채팅 연동 | 높음 |
| **영상 후원** | 치즈 후원 시 영상(TTS 외) 재생 | 중간 |
| **투표** | 스트리머가 생성하는 투표 UI, 실시간 결과 | 중간 |
| **채팅 규칙** | 방 입장 시 규칙 팝업 (스트리머 설정) | 낮음 |
| **실시간 참여자 수** | 채팅 참여자 수 실시간 표시 | 낮음 |
| **채팅 테마** | 웹의 다크/라이트 외 테마 | 낮음 |

---

## 15. CView 전용 우위 기능

치지직 웹에 없고 **CView에만 존재**하는 기능:

| 기능 | 설명 | 파일 |
|------|------|------|
| **오버레이 채팅** | 플레이어 위 반투명 채팅 (드래그+리사이즈) | ChatOverlayView |
| **멀티 채널 병합 채팅** | 최대 4채널 채팅 1개 뷰로 통합 (색상 구분) | MergedChatView |
| **TTS 후원 읽기** | 후원/구독 메시지 음성 읽기 (AVSpeech) | ChatTTSService |
| **키워드 필터** | 키워드/정규식/사용자별 메시지 필터링 | ChatModerationService |
| **채팅 내보내기** | text/json/csv 형식 로그 내보내기 | ChatExportView |
| **스트림 알림 오버레이** | 후원/구독/공지 플레이어 위 팝업 (5초) | StreamAlertItem |
| **리플레이 모드** | 스크롤 유지 + 미읽음 카운트 배지 | ChatViewModel |
| **이모티콘 자동완성** | `:keyword` 입력 시 이모티콘 제안 팝업 | Autocomplete |
| **@멘션 자동완성** | `@name` 입력 시 최근 참여자 제안 | Autocomplete |
| **후원 전용 모드** | showDonationsOnly — 후원만 필터 표시 | ViewModel |
| **실시간 통계** | MPS, 고유 유저, 후원 횟수/총액, 구독 수 | ViewModel |
| **사용자 하이라이트** | 특정 유저 메시지 강조 표시 | ViewModel |
| **로컬 차단** | 서버 무관하게 클라이언트 측 차단 | ModerationService |
| **히스토리 2500** | 웹 기본 150~300 vs CView 2500 | chatHistory |
| **백그라운드 최적화** | 비활성 탭 1s flush로 CPU 절약 | ViewModel |

---

## 16. 구현 격차 및 권장 로드맵

### Phase 1 — 높은 우선순위 (채팅 직접 관련)

| # | 기능 | 설명 | 예상 범위 |
|---|------|------|-----------|
| 1 | **고정 메시지 API 연동** | 현재 로컬 pin만 → 서버 고정 메시지 이벤트 수신·표시 | Parser + ViewModel |
| 2 | **채팅 규칙 표시** | 채널 설정에서 채팅 규칙 API 조회 → 입장 시 배너/팝업 | API + View |
| 3 | **슬로우 모드 타이머 UI** | /slow 시 전송 버튼에 쿨다운 타이머 표시 | ChatInputView |

### Phase 2 — 중간 우선순위

| # | 기능 | 설명 | 예상 범위 |
|---|------|------|-----------|
| 4 | **미션 UI** | 미션 진행률 바 + 금액 표시 + 후원 참여 연동 | 신규 View + API |
| 5 | **투표 UI** | 투표 실시간 결과 + 참여 | 신규 View + Protocol |
| 6 | **영상 후원 재생** | donationType = VIDEO 시 영상 표시 (AVPlayer) | View + Player |

### Phase 3 — 품질 향상

| # | 기능 | 설명 | 예상 범위 |
|---|------|------|-----------|
| 7 | **매니저 전용 UI** | 슬래시 명령 → 전용 관리 패널 (뮤트/밴/공지 버튼) | 신규 View |
| 8 | **이모티콘 팩 관리** | 보유 팩 확인, 즐겨찾기, 최근 사용 | EmoticonPickerView 확장 |
| 9 | **채팅 참여자 수** | 실시간 접속자/참여자 수 표시 | API + Header |

---

## 부록: 파일 목록 & 라인 수

| 계층 | 파일 | 줄 수 |
|------|------|-------|
| **CViewChat** | ChatConstants.swift | 55 |
| | ChatEngine.swift | 467 |
| | ChatMessageParser.swift | 789 |
| | ChatModerationService.swift | 332 |
| | ReconnectionPolicy.swift | 206 |
| | WebSocketService.swift | 385 |
| **ViewModel** | ChatViewModel.swift | 606 |
| | ChatViewModel+Processing.swift | ~290 |
| | ChatViewModel+Autocomplete.swift | ~180 |
| | ChatTTSService.swift | ~100 |
| **View** | ChatPanelView.swift | 433 |
| | ChatMessageRow.swift | 640 |
| | ChatOverlayView.swift | 335 |
| | ChatInputView.swift | 214 |
| | ChatAutocompleteView.swift | 176 |
| | MergedChatView.swift | 151 |
| | ChatUserProfileSheet.swift | ~150 |
| | KeywordFilterView.swift | ~350 |
| | BlockedUsersView.swift | ~100 |
| | ChatExportView.swift | ~150 |
| **CViewCore** | ChatModels.swift | ~250 |
| | ChatMessageItem.swift | ~100 |
| | AutocompleteModels.swift | ~80 |
| | StreamAlertItem.swift | ~100 |
| | EmoticonModels.swift | ~150 |
| | ChatMessageBuffer.swift | ~150 |
| | SettingsModels.swift (chat부분) | ~120 |
| **CViewUI** | EmoticonViews.swift | ~400 |
| | EmoticonPickerView.swift | ~100 |
| **합계** | **29개 파일** | **~6,700+** |

# 치지직 라이브 vs CView_v2 정밀 격차 분석

> **분석 대상**: https://chzzk.naver.com/live/458f6ec20b034f49e0fc6d03921646d2 (서새봄 채널)
> **분석 일자**: 2026-04-03
> **플랫폼**: macOS (Swift 6, SwiftUI)

---

## 1. 치지직 웹 라이브 기능 정밀 분석

### 1.1 플레이어 영역

| 기능 | 치지직 웹 | 상세 |
|---|:---:|---|
| HLS 스트림 재생 | ✅ | 적응형 비트레이트 (ABR) 기반 라이브 스트리밍 |
| 화질 선택 | ✅ | 1080p/720p/480p/360p + 자동 |
| 저지연 모드 | ✅ | 실시간/일반 모드 전환 |
| 음소거/볼륨 | ✅ | 슬라이더 + 단축키 |
| 전체화면 | ✅ | F 키 또는 버튼 |
| 극장 모드 | ✅ | 사이드바 축소 + 플레이어 확대, 채팅은 유지 |
| PiP | ✅ | 브라우저 네이티브 PiP |
| LIVE 뱃지 | ✅ | 좌상단 빨간 펄스 LIVE 표시 |
| 스트림 시간 | ✅ | HH:MM:SS 실시간 표시 |
| 시청자 수 | ✅ | 실시간 동접 표시 |
| 타임시프트 (되감기) | ❌ | 라이브 중 되감기 미지원 |
| 클립 생성 | ✅ | 라이브 시청 중 클립 캡처 |
| 스크린샷 | ❌ | 브라우저 기본 기능 없음 |
| 녹화 | ❌ | 웹에서 직접 지원 안함 |
| 키보드 단축키 | ✅ | Space(재생), M(음소거), F(전체화면), Esc |
| VLC 고급 설정 | ❌ | 웹은 브라우저 렌더링 |

### 1.2 채널 정보 영역

| 기능 | 치지직 웹 | 상세 |
|---|:---:|---|
| 방송 제목 | ✅ | 플레이어 하단에 크게 표시 |
| 카테고리/태그 | ✅ | `붉은사막`, `종합게임`, `서새봄` 등 클릭 가능 태그 |
| 스트리머 프로필 | ✅ | 아바타 + 채널명 + LIVE 뱃지 |
| 팔로워 수 | ✅ | `18.6만명` 표시 |
| 팔로우 버튼 | ✅ | API 연동 실시간 팔로우/언팔로우 |
| 구독 버튼 | ✅ | 유료 구독 결제 플로우 |
| 구독 선물 | ✅ | 다른 사용자에게 구독 선물 |
| 더보기 메뉴 | ✅ | 알림 설정, 신고 등 |
| 채널 클립 | ✅ | "이 채널의 클립" 섹션 (최신순/인기순) |
| 채널 동영상 (VOD) | ✅ | "이 채널의 동영상" 섹션 |
| 19+ 성인 표시 | ✅ | 성인 방송 표시 |
| 공유 | ✅ | URL 복발 + SNS 공유 |
| 알림 설정 | ✅ | 방송 시작 시 알림 수신 토글 |

### 1.3 채팅 영역

| 기능 | 치지직 웹 | 상세 |
|---|:---:|---|
| 실시간 채팅 | ✅ | WebSocket 기반 실시간 메시지 |
| 이모티콘 | ✅ | 커스텀 이모티콘 + 이모티콘 피커 |
| 후원 (치즈) | ✅ | 금액별 티어 카드 표시 |
| 영상 후원 | ✅ | 후원 시 미디어 재생 |
| 미션 후원 | ✅ | 진행률 바 + 완료 표시 + 상금 표시 |
| 구독 메시지 | ✅ | 구독 알림 카드 |
| 고정 메시지 | ✅ | 스트리머가 고정한 메시지 상단 배너 |
| 투표/설문 | ✅ | 방송 중 투표 참여 |
| 슬로우 모드 | ✅ | 슬로우 모드 활성 시 타이머 표시 |
| 차단/신고 | ✅ | 사용자 차단 + 신고 |
| 채팅 규칙 | ✅ | 입장 시 "쾌적한 시청 환경..." 안내 |
| 채팅 접기 | ✅ | 채팅 패널 숨기기/보이기 |
| 채팅 전용 팝업 | ✅ | 별도 창으로 분리하기 |

### 1.4 미션 시스템 (서새봄 채널 확인)

- **진행 중인 미션 표시**: 채팅 상단에 미션 카드
- **미션 시간**: 카운트다운 타이머 (MM:SS)
- **미션 제목**: "종겜 모금함" 등
- **치즈 누적**: 현재 모금액 표시 (예: `101,010`)
- **상금 쌓기 공지**: 미션 완료 시 알림

---

## 2. CView_v2 현재 구현 상태

### 2.1 플레이어 (매우 우수 — 웹 기능 초과)

| 기능 | 지원 | 구현 파일 | 비고 |
|---|:---:|---|---|
| HLS 스트림 재생 | ✅ | `StreamCoordinator.swift` | actor 기반 오케스트레이터 |
| 듀얼 엔진 | ✅⭐ | `VLCPlayerEngine.swift`, `AVPlayerEngine.swift` | **웹 초과** — VLC 4.0 + AVPlayer 선택 |
| ABR (적응형 비트레이트) | ✅ | `ABRController.swift` | 대역폭 기반 자동 전환 (safety 0.7) |
| 수동 화질 선택 | ✅ | `ChatSettingsQualityView.swift` | 자동/1080p/720p/480p/360p |
| 저지연 모드 | ✅⭐ | `LowLatencyController.swift` | **웹 초과** — PID 제어 + 3단 프리셋 |
| 로컬 프록시 | ✅⭐ | `LocalStreamProxy.swift` | **웹 초과** — 토큰 리프레시 + 모니터링 |
| PiP | ✅⭐ | `PiPController.swift` | **웹 초과** — 플로팅 NSPanel, 위치 기억 |
| 전체화면 | ✅ | `LiveStreamView.swift` | macOS 네이티브 |
| 스크린샷 | ✅⭐ | `PlayerControlsView.swift` | **웹 초과** |
| 녹화 | ✅⭐ | `StreamRecordingService.swift` | **웹 초과** — HLS 세그먼트 .ts 녹화 |
| VLC 이퀄라이저 | ✅⭐ | `SettingsModels.swift` | **웹 초과** — 프리셋+커스텀 밴드 |
| 비디오 조정 | ✅⭐ | 동일 | **웹 초과** — 밝기/대비/채도/색조/감마 |
| 재생 재연결 | ✅⭐ | `PlaybackReconnectionHandler.swift` | **웹 초과** — Watchdog 기반 stall 감지 |
| 성능 오버레이 | ✅⭐ | `PerformanceOverlayView.swift` | **웹 초과** — FPS/메모리/네트워크 진단 |
| 키보드 단축키 | ✅⭐ | `LiveStreamView.swift` | **웹 초과** — 완전 커스텀 가능 |
| 극장 모드 | ❌ | — | 미구현 |
| 타임시프트 | ❌ | — | 미구현 (웹도 미지원) |

### 2.2 채널 정보 (양호 — 일부 누락)

| 기능 | 지원 | 구현 파일 | 비고 |
|---|:---:|---|---|
| 방송 제목 | ✅ | `ChannelInfoTabContent.swift` | |
| 카테고리/태그 | ✅ | 동일 | 최대 8개 태그 |
| 스트리머 프로필 | ✅ | `ChannelInfoHeaderView.swift` | 라이브 시 그라데이션 테두리 |
| 팔로워 수 | ✅ | 동일 | |
| 시청자 수/업타임 | ✅ | `ChannelInfoView.swift` | 실시간 타이머 |
| LIVE 뱃지 | ✅ | `PlayerControlsView.swift` | 펄스 애니메이션 |
| 즐겨찾기 | ✅⭐ | `ChannelInfoHeaderView.swift` | **웹 초과** — 로컬 즐겨찾기 |
| 채널 메모 | ✅⭐ | `ChannelMemoSheet.swift` | **웹 초과** |
| VOD 목록 | ✅ | `ChannelVODClipTab.swift` | 무한스크롤 |
| 클립 목록 | ✅ | 동일 | |
| 3탭 구조 | ✅ | `ChannelInfoView.swift` | 정보/VOD/클립 |
| 팔로우 버튼 (API) | ❌ | — | 로컬 즐겨찾기만 (API 팔로우 미연동) |
| 구독 버튼 | ❌ | — | 결제 플로우 미구현 |
| 구독 선물 | ❌ | — | |
| 알림 설정 | ❌ | — | 방송 시작 알림 미구현 |
| 공유 (SNS) | ❌ | — | URL 복사만 지원 |
| 신고 | ❌ | — | |

### 2.3 채팅 (우수 — 일부 누락)

| 기능 | 지원 | 구현 파일 | 비고 |
|---|:---:|---|---|
| 실시간 메시지 | ✅ | `WebSocketService.swift` | |
| 후원 (치즈) | ✅ | `ChatMessageRow.swift` | 4단계 티어 카드 |
| 영상 후원 레이블 | ✅ | 동일 | 레이블만 (미디어 재생 없음) |
| 미션 후원 레이블 | ✅ | 동일 | 레이블만 |
| 구독 메시지 | ✅ | 동일 | 개월 티어 + 마일스톤 |
| 이모티콘 렌더링 | ✅ | `EmoticonViews.swift` | GIF 애니메이션 + FlowLayout |
| 이모티콘 피커 | ✅ | `EmoticonPickerView.swift` | 팩/검색/6열 그리드 |
| 채팅 입력 | ✅ | `ChatInputView.swift` | |
| 자동완성 | ✅ | `ChatAutocompleteView.swift` | @멘션 + 이모티콘 |
| 3가지 모드 | ✅ | `ChatPanelView.swift` | side/overlay/hidden |
| 오버레이 채팅 | ✅⭐ | `ChatOverlayView.swift` | **웹 초과** — 이동/리사이즈/투명도 |
| 멘션 하이라이트 | ✅ | `ChatMessageRow.swift` | 오렌지 배경 |
| 역할 하이라이트 | ✅ | 동일 | 스트리머/매니저 테두리 |
| 사용자 차단 | ✅ | `ChatModerationService.swift` | |
| 키워드 필터 | ✅⭐ | `KeywordFilterView.swift` | **웹 초과** — 정규식 필터 |
| 프로필 시트 | ✅ | `ChatUserProfileSheet.swift` | |
| 채팅 내보내기 | ✅⭐ | `ChatPanelView.swift` | **웹 초과** |
| 슬래시 명령어 | ✅⭐ | `ChatModerationService.swift` | **웹 초과** — 15종 명령어 |
| 참여자 수 | ✅ | `ChatPanelView.swift` | |
| 고정 메시지 배너 | ⚠️ | `ChatPanelView.swift` (pinnedMessage) | 구조는 있으나 수신·표시 검증 필요 |
| 슬로우 모드 UI | ❌ | — | 명령어만 (시각 표시 없음) |
| 투표/설문 | ❌ | — | |
| 채팅 규칙 안내 | ❌ | — | |
| 영상 후원 미디어 재생 | ❌ | — | 레이블만 표시 |

### 2.4 멀티라이브 (웹 대비 앱 독자 기능 — 매우 우수)

| 기능 | 지원 | 구현 파일 | 비고 |
|---|:---:|---|---|
| 최대 4세션 동시 | ✅ | `MultiLiveManager` | 웹에 없는 독자 기능 |
| 탭 전환 모드 | ✅ | `MultiLiveTabBar.swift` | |
| 3가지 그리드 레이아웃 | ✅ | `MultiLiveGridLayouts.swift` | Preset/Custom/FocusLeft |
| 포커스 모드 | ✅ | 동일 | 더블클릭 확대 |
| 드래그 재정렬 | ✅ | 동일 | |
| 커스텀 분할 비율 | ✅ | `MLResizeDivider` | |
| 2채널 자동 방향 | ✅ | 동일 | aspect ratio 기반 |
| 채널 추가 | ✅ | `MultiLiveAddSheet.swift` | 팔로잉+검색 |
| 엔진 풀 | ✅ | `MultiLiveEnginePool.swift` | 리소스 효율 관리 |
| 세션별 설정 (8탭) | ✅ | `MultiLiveSettingsPanel.swift` | |
| 오디오 전환 | ✅ | `MultiLiveTabBar.swift` | |
| 세션 상태 오버레이 | ✅ | `MultiLivePlayerPane.swift` | |
| 세션 상태 유지 | ✅ | `FollowingView+MultiLive.swift` | restoreState |

### 2.5 멀티채팅 (웹 대비 앱 독자 기능 — 우수)

| 기능 | 지원 | 구현 파일 | 비고 |
|---|:---:|---|---|
| 멀티채팅 패널 | ✅ | `FollowingView+MultiChat.swift` | |
| 채널 탭 전환 | ✅ | 동일 | 연결상태/메시지수/재정렬 |
| 통합 타임라인 | ✅ | `MergedChatView.swift` | 시간순 합산 (300개, 500ms) |
| 3가지 레이아웃 모드 | ✅ | `MultiChatView.swift` | sidebar/grid/merged |
| 그리드 채팅 | ✅ | 동일 | 리사이즈 디바이더 |
| 전체 재연결/해제 | ✅ | `FollowingView+MultiChat.swift` | |
| 스와이프 숨기기 | ✅ | 동일 | |
| 채널 색상 구분 | ✅ | `MergedChatView.swift` | 8색 해시 기반 |

---

## 3. 격차 분석 (수정·개발 필요 항목)

### 3.1 🔴 High Priority (핵심 기능 부재)

#### H-1. 미션 시스템 UI

**현재**: 미션 후원 메시지에 `MISSION` 레이블만 표시
**치지직 웹**: 채팅 상단에 미션 카드 (제목, 타이머, 모금액, 진행률 바, 상금 쌓기)

```
필요 작업:
├── API: 미션 정보 폴링 (진행 중 미션 목록, 현재 금액, 목표 금액, 남은 시간)
├── UI: ChatPanelView 상단에 미션 카드 컴포넌트
│   ├── 미션 제목 + 카운트다운 타이머
│   ├── 진행률 바 (LinearGradient)
│   └── 누적 치즈 금액 표시 (NumberFormatter)
├── WebSocket: 미션 상태 변경 실시간 수신 (완료/실패/금액 갱신)
└── Animation: 미션 완료 시 축하 이펙트
```

**관련 파일**: `ChatPanelView.swift`, `ChzzkAPIClient.swift`, `WebSocketService.swift`
**예상 난이도**: ★★★☆☆ (API 스펙 확인 필요)

---

#### H-2. 팔로우 API 연동

**현재**: 로컬 즐겨찾기 (`FavoriteStore`) — 치지직 계정과 동기화되지 않음
**치지직 웹**: 팔로우/언팔로우 API 호출 → 팔로잉 목록 실시간 반영

```
필요 작업:
├── API: POST /service/v1/channels/{channelId}/follow (팔로우)
│         DELETE /service/v1/channels/{channelId}/follow (언팔로우)
├── UI: ChannelInfoHeaderView에 "팔로우" 버튼 추가
│   ├── 팔로우 상태별 UI (팔로우/팔로잉/호버 시 "팔로우 취소")
│   └── 로그인 필수 체크 (미로그인 시 로그인 유도)
├── State: AppState에 followedChannelIds Set 관리
└── Sync: 앱 시작 시 서버 팔로잉 목록과 동기화
```

**관련 파일**: `ChannelInfoHeaderView.swift`, `ChzzkAPIClient.swift`, `AppState.swift`
**예상 난이도**: ★★☆☆☆

---

#### H-3. 고정 메시지 (Pinned Message) 수신 확인

**현재**: `ChatPanelView`에 `pinnedMessage` 배너 UI는 존재하지만, 웹소켓에서 pin 이벤트를 정확히 수신하는지 검증 필요
**치지직 웹**: 스트리머가 고정한 메시지가 채팅 상단에 지속 표시

```
필요 작업:
├── 검증: WebSocketService에서 pin/unpin 커맨드 코드 처리 확인
├── 수정: ChatViewModel.pinnedMessage 바인딩이 실시간 반영되는지 테스트
└── 보완: 고정 메시지 해제 시 애니메이션 트랜지션 추가
```

**관련 파일**: `WebSocketService.swift`, `ChatViewModel.swift`, `ChatPanelView.swift`
**예상 난이도**: ★☆☆☆☆ (기존 구조 활용)

---

#### H-4. 영상 후원 미디어 재생

**현재**: `donationType == "VIDEO"` → 재생 아이콘 + "영상 후원" 레이블만 표시
**치지직 웹**: 후원 시 실제 영상/사운드가 플레이어 위에 재생

```
필요 작업:
├── API: 후원 메시지에 포함된 미디어 URL 파싱
├── Player: 인라인 미디어 플레이어 (AVPlayer 기반, 짧은 클립 전용)
│   ├── 오버레이 위에 미디어 프리뷰 카드
│   ├── 자동 재생 + 자동 닫힘 (지속시간 종료 후)
│   └── 볼륨 조절 + 닫기 버튼
└── Settings: 영상 후원 자동 재생 On/Off 토글
```

**관련 파일**: `ChatMessageRow.swift`, `LiveStreamView.swift`, `SettingsModels.swift`
**예상 난이도**: ★★★☆☆

---

### 3.2 🟡 Medium Priority (사용성 향상)

#### M-1. 극장 모드 (Theater Mode)

**현재**: 전체화면만 지원 (macOS 네이티브)
**치지직 웹**: 사이드바 숨김 + 플레이어 극대화 + 채팅만 유지

```
필요 작업:
├── State: AppState에 isTheaterMode 토글 추가
├── Layout: MainContentView에서 극장 모드 시:
│   ├── NavigationSidebar 숨기기 (withAnimation .snappy)
│   ├── 플레이어 영역 극대화 (safeArea 무시)
│   └── 채팅 패널 유지 (좁은 폭)
├── UI: PlayerControlsView에 극장 모드 버튼 추가
├── Shortcut: T 키 → 극장 모드 토글
└── Transition: 사이드바 slide-out + 플레이어 expand 동시 애니메이션
```

**관련 파일**: `MainContentView.swift`, `PlayerControlsView.swift`, `LiveStreamView.swift`
**예상 난이도**: ★★☆☆☆

---

#### M-2. 투표/설문 기능

**현재**: 미구현
**치지직 웹**: 스트리머가 만든 투표에 시청자 참여

```
필요 작업:
├── API: WebSocket 투표 이벤트 수신 (커맨드 코드 확인)
├── Model: VotePoll (제목, 옵션[], 투표수, 종료시간, 참여여부)
├── UI: ChatPanelView 상단에 투표 카드 오버레이
│   ├── 투표 제목 + 남은 시간
│   ├── 옵션별 버튼 + 투표율 바
│   ├── 투표 완료 상태 (내 선택 표시)
│   └── 결과 공개 시 비율 애니메이션
├── WebSocket: 투표 생성/갱신/종료 이벤트 핸들링
└── 인증: 투표 참여 시 로그인 필수
```

**관련 파일**: `WebSocketService.swift`, `ChatPanelView.swift` (신규 `VotePollView.swift`)
**예상 난이도**: ★★★☆☆ (API 스펙 확인 필요)

---

#### M-3. 클립 생성 (라이브 시청 중)

**현재**: 클립 브라우저·재생만 지원
**치지직 웹**: 라이브 시청 중 하이라이트 구간 클립 생성

```
필요 작업:
├── API: POST /service/v1/clips (클립 생성 엔드포인트)
│   ├── channelId, liveId, startOffset, endOffset
│   └── 응답: clipId, clipUrl, thumbnailUrl
├── UI: PlayerControlsView에 가위 아이콘 버튼 추가
│   ├── 클릭 시 ClipCreationSheet 모달
│   ├── 구간 선택 슬라이더 (직전 N초~현재)
│   ├── 제목 입력
│   └── 생성 완료 → 클립 URL 복사/공유
└── 인증: 로그인 필수 체크
```

**관련 파일**: `PlayerControlsView.swift`, `ChzzkAPIClient.swift` (신규 `ClipCreationSheet.swift`)
**예상 난이도**: ★★★☆☆

---

#### M-4. 슬로우 모드 UI 표시

**현재**: `/slow` 명렝어 지원, 시각적 표시 없음
**치지직 웹**: 슬로우 모드 활성 시 입력창에 카운트다운 타이머

```
필요 작업:
├── WebSocket: 슬로우 모드 상태 이벤트 수신 (간격 초)
├── State: ChatViewModel에 slowModeInterval, lastMessageTime 추가
├── UI: ChatInputView에서:
│   ├── 슬로우 모드 활성 시 입력 비활성화 + 남은 시간 표시
│   ├── "메시지를 보내려면 N초 기다리세요" 안내
│   └── 타이머 종료 시 입력 활성화 + haptic feedback
└── Animation: 카운트다운 프로그레스링 (subtle)
```

**관련 파일**: `ChatInputView.swift`, `ChatViewModel.swift`, `WebSocketService.swift`
**예상 난이도**: ★★☆☆☆

---

#### M-5. 후원 대형 이펙트

**현재**: 후원 카드만 표시 (정적)
**치지직 웹**: 대형 후원 시 화면 이펙트 (파티클 등)

```
필요 작업:
├── Trigger: ₩50,000+ 후원 감지 시 이펙트 트리거
├── Effect: Canvas 기반 파티클 시스템
│   ├── 파티클 타입: confetti, sparkle, burst
│   ├── 방향: 하단→상단 or 좌우→중앙
│   └── 지속시간: 2~3초, easeOut 감쇠
├── Sound: 시스템 사운드 재생 (NSSound or AVAudioPlayer)
├── Settings: 후원 이펙트 On/Off + 볼륨 토글
└── Performance: Metal 가속 or TimelineView 기반 (GPU 부하 최소)
```

**관련 파일**: `LiveStreamView.swift` (신규 `DonationEffectView.swift`)
**예상 난이도**: ★★★☆☆

---

### 3.3 🟢 Low Priority (완성도 향상)

| ID | 기능 | 현재 상태 | 필요 작업 | 난이도 |
|---|---|---|---|---|
| L-1 | 알림 설정 | 미구현 | macOS UserNotifications + 방송 시작 감지 폴링 | ★★☆☆☆ |
| L-2 | 채팅 규칙 안내 | 미구현 | 입장 시 systemMessage로 채팅 규칙 표시 | ★☆☆☆☆ |
| L-3 | 방송 신고 | 미구현 | API + 신고 사유 선택 시트 | ★☆☆☆☆ |
| L-4 | SNS 공유 | URL 복사만 | `NSSharingServicePicker` 연동 | ★☆☆☆☆ |
| L-5 | 구독 선물 UI | 미구현 | API + 선물 대상 선택 시트 (결제 웹뷰) | ★★★☆☆ |
| L-6 | 채팅 블라인드 시각화 | 파싱만 | 블라인드 메시지 dim + "메시지 숨김" 표시 | ★☆☆☆☆ |

---

## 4. CView_v2 우위 기능 (치지직 웹 대비)

치지직 웹에 **없는** CView_v2 독자 기능:

| 기능 | 상세 |
|---|---|
| **듀얼 엔진** | VLC 4.0 + AVPlayer 선택 (웹은 브라우저 렌더링만) |
| **멀티라이브** | 최대 4세션 동시 재생 + 3가지 그리드 레이아웃 |
| **멀티채팅** | 복수 채널 채팅 동시 모니터링 + 통합 타임라인 |
| **스트림 녹화** | HLS 세그먼트 .ts 녹화 |
| **스크린샷** | 비디오 프레임 캡처 |
| **PiP 플로팅 윈도우** | 독립 NSPanel + 위치 기억 |
| **채팅 오버레이** | 비디오 위 반투명 드래그/리사이즈 채팅 |
| **저지연 PID 제어** | 3단 프리셋 + 자동 catchup |
| **VLC 이퀄라이저** | 10밴드 + 프리셋 |
| **비디오 조정** | 밝기/대비/채도/색조/감마 |
| **키워드 필터** | 정규식 지원 키워드 차단 |
| **슬래시 명령어** | 15종 채팅 관리 명령 |
| **채팅 내보내기** | 히스토리 파일 내보내기 |
| **채널 메모** | 채널별 개인 메모 |
| **성능 모니터링** | FPS/메모리/네트워크 디버그 오버레이 |
| **분리 창 재생** | 다른 탭 이동 시에도 재생 유지 |
| **명령 팔레트** | 빠른 명령 검색 (⌘K) |

---

## 5. 구현 로드맵 제안

### Phase 1 — 핵심 격차 해소 (1~2주)
1. **H-3** 고정 메시지 수신 검증/수정
2. **H-2** 팔로우 API 연동
3. **M-4** 슬로우 모드 UI

### Phase 2 — 라이브 체험 완성 (2~3주)
4. **H-1** 미션 시스템 UI
5. **H-4** 영상 후원 미디어 재생
6. **M-1** 극장 모드

### Phase 3 — 부가 기능 (3~4주)
7. **M-3** 클립 생성
8. **M-2** 투표/설문
9. **M-5** 후원 이펙트

### Phase 4 — 완성도 (선택적)
10. L-1 ~ L-6 낮은 우선순위 항목

---

## 6. 기술 참고 사항 (Swift 6 / macOS)

### Concurrency
- 기존 `StreamCoordinator`가 `actor` 패턴 사용 → 새 API 호출도 동일 패턴 적용
- `@MainActor` UI 업데이트, `Task { }` 비동기 작업 분리
- Swift 6 strict concurrency: `Sendable` 준수 필수

### 성능
- 채팅 렌더링: `EquatableChatMessageRow` 패턴 유지 (message + config 기반 재렌더 방지)
- 미션/투표 카드: `LazyVStack` 내 삽입 시 id 충돌 방지
- 이펙트: `Canvas` + `TimelineView` 조합 권장 (Metal 불필요)

### 네트워킹
- `ChzzkAPIClient` 통합 → 새 엔드포인트 추가 시 기존 패턴 (`URLSession` + `Codable`) 따르기
- WebSocket 커맨드 코드 추가 시 `ChatCommandCode` enum 확장
- 인증서 피닝 (`CertificatePinningDelegate`) 자동 적용됨

### 테스트
- 기존 테스트 모듈 (`CViewChatTests`, `CViewPlayerTests` 등) 활용
- 새 기능별 유닛 테스트 추가 (특히 WebSocket 메시지 파싱)

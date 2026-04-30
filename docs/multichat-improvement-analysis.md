# 멀티채팅 기능 개선점 정밀 분석 및 채팅 뱃지 시스템 개선안

> **작성일**: 2026-04-02  
> **대상**: CView_v2 macOS 앱  
> **범위**: 멀티채팅 아키텍처 + 채팅 뱃지/역할 시스템

---

## 목차

1. [현재 아키텍처 분석](#1-현재-아키텍처-분석)
2. [멀티채팅 개선점 분석](#2-멀티채팅-개선점-분석)
3. [채팅 뱃지/역할 시스템 현황 및 개선안](#3-채팅-뱃지역할-시스템-현황-및-개선안)
4. [구현 우선순위 및 로드맵](#4-구현-우선순위-및-로드맵)

---

## 1. 현재 아키텍처 분석

### 1.1 멀티채팅 시스템 구조

```
┌─────────────────────────────────────────────────────────┐
│                    MultiChatSessionManager               │
│  (@Observable @MainActor)                               │
│                                                         │
│  sessions: [ChatSession]     selectedChannelId: String? │
│      │                              │                   │
│      ▼                              ▼                   │
│  ┌──────────┐  ┌──────────┐   selectedSession           │
│  │ Session 1│  │ Session 2│   (computed)                │
│  │ channelId│  │ channelId│                             │
│  │ chatVM   │  │ chatVM   │                             │
│  └────┬─────┘  └────┬─────┘                             │
│       │              │                                   │
│       ▼              ▼                                   │
│  ┌──────────┐  ┌──────────┐                             │
│  │ChatEngine│  │ChatEngine│   (각 세션 독립 WebSocket)   │
│  │(Actor)   │  │(Actor)   │                             │
│  └──────────┘  └──────────┘                             │
└─────────────────────────────────────────────────────────┘
```

### 1.2 코드 규모

| 모듈 | 파일 수 | 코드량 (약) | 역할 |
|------|---------|------------|------|
| `MultiChatSessionManager` | 1 | ~95줄 | 세션 생명주기 관리 |
| `MultiChatView` | 1 | ~340줄 | HSplitView 독립 뷰 |
| `FollowingView+MultiChat` | 1 | ~270줄 | 팔로잉 뷰 내 인라인 패널 |
| `ChatPanelView` | 1 | ~300줄 | 공용 채팅 패널 (헤더+메시지+입력) |
| `ChatMessageRow` | 1 | ~550줄 | 메시지 렌더링 (일반/후원/구독/공지) |
| `ChatViewModel` | 1 | ~700줄 | 채팅 상태 관리 + 메시지 배치 처리 |
| `ChatEngine` | 1 | ~335줄 | WebSocket 오케스트레이터 |
| `ChatMessageParser` | 1 | ~700줄 | 프로토콜 파서 |
| **총합** | **8+** | **~3,300줄** | |

### 1.3 멀티채팅 진입 경로

| 경로 | 뷰 | 레이아웃 |
|------|-----|---------|
| 메뉴 → 멀티채팅 | `MultiChatView` | HSplitView (사이드바 + 채팅) |
| 팔로잉 뷰 → 멀티채팅 토글 | `FollowingView+MultiChat` | 인라인 탭바 + 채팅 패널 |
| 방송 시청 중 채팅 | `ChatPanelView` (단일) | 사이드/오버레이/숨김 모드 |
| 채팅 전용 뷰 | `ChatOnlyView` | 전체 화면 채팅 |

---

## 2. 멀티채팅 개선점 분석

### 2.1 세션 관리 한계

#### 🔴 P0 — 세션 상한 없음
- **현상**: `addSession()`에 최대 세션 수 제한이 없음
- **문제**: 채널 10개 이상 추가 시 메모리/CPU 과다 사용 (각 세션 독립 WebSocket + ChatEngine Actor)
- **개선안**: `maxSessions` 상수 도입 (권장: 6~8개), 초과 시 안내 다이얼로그

```swift
// 현재 코드 (MultiChatSessionManager.swift)
public func addSession(...) async {
    guard !sessions.contains(where: { $0.id == channelId }) else { return }
    // ← 세션 수 제한 없음
    let vm = ChatViewModel()
    ...
}
```

#### 🔴 P0 — 세션 복원 미지원
- **현상**: 앱 재시작 시 모든 멀티채팅 세션 소실
- **문제**: 사용자가 매번 채널을 다시 추가해야 함
- **개선안**: `SettingsStore`/`DataStore`에 마지막 세션 목록 (channelId + channelName) 저장 후 복원

#### 🟡 P1 — 채널 추가 시 방송 종료 채널 미처리
- **현상**: 방송 중이 아닌 채널 추가 시 `chatChannelId`가 nil → 무시됨
- **문제**: 사용자에게 왜 추가가 안 되는지 피드백이 없음
- **개선안**: 비방송 채널에 대해 "현재 방송 중이 아닙니다" 안내 + 방송 시작 시 자동 연결 옵션

#### 🟡 P1 — 중복 채널 추가 무시 피드백 없음
- **현상**: 이미 존재하는 channelId는 `guard` 문에서 무음 리턴
- **개선안**: "이미 추가된 채널입니다" 피드백 제공

### 2.2 UI/UX 개선점

#### 🔴 P0 — 단일 채팅만 동시 조회 가능 (탭 전환 방식)
- **현상**: `selectedChannelId`에 의해 한 번에 하나의 채팅만 표시
- **문제**: "멀티채팅"이라는 이름에도 불구하고 실질적으로 탭 전환 방식
- **개선안** (3단계):
  1. **그리드 모드**: 2×N 그리드로 여러 채팅 동시 표시 (컴팩트 모드)
  2. **분할 뷰**: HSplitView로 2~3개 채팅 수평 분할
  3. **팝아웃**: 세션별 독립 윈도우 분리

```
현재:  [탭1] [탭2] [탭3]          개선:  ┌──────┬──────┐
       ┌──────────────────┐             │ 채팅1 │ 채팅2 │
       │  선택된 채팅 1개  │             │      │      │
       │                  │             ├──────┼──────┤
       └──────────────────┘             │ 채팅3 │ 채팅4 │
                                        └──────┴──────┘
```

#### 🟡 P1 — 채팅 탭 바 드래그 순서 변경 미지원
- **현상**: 탭 순서가 추가 순서 고정
- **개선안**: `onMove` 또는 드래그앤드롭으로 순서 변경

#### 🟡 P1 — MultiChatView와 FollowingView+MultiChat 코드 중복
- **현상**: 채널 검색/추가 로직이 두 파일에 거의 동일하게 구현됨
- **개선안**: `ChatChannelPickerView` 공용 컴포넌트 추출

#### 🟢 P2 — 채팅 통합 뷰 미지원
- **현상**: 채널별로만 채팅 조회 가능
- **개선안**: "전체 보기" 모드 — 모든 세션 메시지를 시간순 통합 (채널 라벨 표기)

#### 🟢 P2 — 채널별 미읽은 메시지 인디케이터 개선
- **현상**: 탭에 메시지 카운트만 표시 (예: "150")
- **개선안**: 비활성 탭에 빨간 dot 인디케이터 + 새 메시지 수 표시

### 2.3 연결 안정성

#### 🟡 P1 — 세션간 독립 재연결 상태 미표시
- **현상**: 재연결 중인 세션의 상태가 탭 dot(빨간색)만으로 표시
- **문제**: 어떤 서버에 어떤 이유로 연결 실패했는지 파악 어려움
- **개선안**: 탭 hover 시 툴팁으로 연결 상태 상세 표시

#### 🟡 P1 — 전체 세션 일괄 재연결 미지원
- **현상**: 개별 세션 재연결만 가능 (ChatEngine 내부 자동)
- **개선안**: "모두 재연결" 버튼 추가

#### 🟢 P2 — 서버 부하 분산 최적화
- **현상**: 각 세션이 독립적으로 서버 선택 (`chatChannelId` 해시 기반)
- **개선안**: 동일 서버 연결 세션 수 제한 또는 커넥션 풀링

### 2.4 성능 관련

#### 🟡 P1 — 비활성 탭 메시지 축적
- **현상**: 비활성 탭도 ChatMessageBuffer에 메시지 계속 축적 (200개 기본)
- **개선안**: 비활성 세션의 버퍼 크기를 동적으로 축소 (예: 50개), 활성 시 복원
- **참고**: 현재 배치 간격은 비활성 시 1초로 이미 최적화됨

#### 🟢 P2 — 메시지 통계 메모리
- **현상**: `uniqueUserCount` 계산을 위한 Set이 세션별로 독립 유지
- **개선안**: 주기적 리셋 또는 HyperLogLog 같은 확률적 자료구조로 메모리 효율화

---

## 3. 채팅 뱃지/역할 시스템 현황 및 개선안

### 3.1 치지직 웹 채팅 뱃지 체계 (참조 기준)

치지직 웹 채팅에서 표시되는 뱃지/역할 체계:

| 카테고리 | 유형 | 표시 방식 | 위치 |
|---------|------|----------|------|
| **스트리머** | `userRoleCode: "streamer"` | 🎙️ 녹색 왕관 아이콘 + 닉네임 강조 | 닉네임 앞 |
| **매니저** | `userRoleCode: "streaming_chat_manager"` | 🔧 렌치 아이콘 (파란색) | 닉네임 앞 |
| **구독 뱃지** | `badge.imageURL` (구독 개월별) | 구독 아이콘 이미지 (1/3/6/12/24개월별 차등) | 닉네임 앞 |
| **칭호** | `title.name` + `title.color` | 컬러 라벨 텍스트 | 닉네임 앞 |
| **후원** | `donation.amount` | 💰 후원 카드 전체 스타일링 | 메시지 영역 전체 |
| **구독 알림** | `subscription.months` | ⭐ 구독 카드 전체 스타일링 | 메시지 영역 전체 |
| **인증 마크** | 파트너/인증 스트리머 | ✓ 체크 마크 | 채널명 옆 |
| **커스텀 뱃지** | 채널별 커스텀 이미지 | 채널 고유 이미지 | 닉네임 앞 |

### 3.2 현재 CView_v2 구현 상태

#### 데이터 수집 (ChatMessageParser.swift)

```swift
// 현재 parseProfile() — 프로필 파싱
private func parseProfile(_ value: AnyCodable?) -> ParsedProfile {
    // ✅ nickname: 파싱됨
    // ✅ profileImageUrl: 파싱됨
    // ✅ userRoleCode: 파싱됨 ("streamer", "manager" 감지)
    // ⚠️ badge: 첫 번째 뱃지만 추출 (다중 뱃지 미지원)
    // ❌ title: 파싱 안됨 (항상 nil)
    // ❌ 활동 뱃지: 미파싱
    // ❌ 구독 개월별 뱃지 구분: 미지원
}
```

#### 데이터 모델 (ChatModels.swift, ChatMessageItem.swift)

| 필드 | 도메인 모델 | UI 모델 | 상태 |
|------|-----------|---------|------|
| `userRoleCode` | `ChatProfile.userRoleCode` | **없음** (미전달) | ⚠️ 파싱만 됨, UI 미사용 |
| `badge` | `ChatProfile.badge.imageURL` | `ChatMessageItem.badgeImageURL` | ✅ 이미지 URL 1개만 전달 |
| `title` | `ChatProfile.title` (항상 nil) | **없음** | ❌ 완전 미구현 |
| `subscription badge` | — | — | ❌ 미구현 |

#### 뷰 렌더링 (ChatMessageRow.swift)

```swift
// 현재 뱃지 렌더링 — 이미지 URL 하나만 16×16으로 표시
if showBadge, let badgeURL = message.badgeImageURL {
    CachedAsyncImage(url: badgeURL) {
        EmptyView()   // ← 로딩 실패 시 아무것도 안 보임
    }
    .frame(width: 16, height: 16)
    .padding(.trailing, 4)
}
// ❌ userRoleCode 기반 아이콘 없음
// ❌ 칭호(title) 표시 없음
// ❌ 스트리머/매니저 닉네임 색상 구분 없음
// ❌ 다중 뱃지 표시 불가
```

### 3.3 개선안: 치지직 웹 채팅과 유사한 뱃지/역할 표시

#### Phase 1: 데이터 파이프라인 보강

##### 1-A. userRoleCode를 강타입 enum으로 전환

```swift
// CViewCore/Models/ChatModels.swift — 추가
public enum UserRole: String, Sendable, Codable, Hashable {
    case streamer = "streamer"
    case manager = "streaming_chat_manager"
    case channelManager = "streaming_channel_manager"
    case viewer = ""
    
    public init(from code: String?) {
        switch code {
        case "streamer": self = .streamer
        case let c? where c.contains("manager"): self = .manager
        default: self = .viewer
        }
    }
    
    /// SF Symbol 아이콘
    public var iconName: String? {
        switch self {
        case .streamer: return "mic.circle.fill"
        case .manager, .channelManager: return "wrench.and.screwdriver.fill"
        case .viewer: return nil
        }
    }
    
    /// 닉네임 색상 (치지직 웹 기준)
    public var nicknameColorHex: UInt? {
        switch self {
        case .streamer: return 0x00FFA3    // 치지직 그린
        case .manager: return 0x5C9DFF     // 파란색
        case .channelManager: return 0x5C9DFF
        case .viewer: return nil
        }
    }
    
    /// 역할 표시 텍스트
    public var displayLabel: String? {
        switch self {
        case .streamer: return "스트리머"
        case .manager, .channelManager: return "매니저"
        case .viewer: return nil
        }
    }
}
```

##### 1-B. 다중 뱃지 지원 + 칭호 파싱

```swift
// ChatModels.swift — ChatBadge 확장
public struct ChatBadge: Sendable, Codable, Hashable {
    public let imageURL: URL?
    public let badgeId: String?      // 뱃지 식별용 (구독/활동 등 구분)
    public let altText: String?      // 이미지 로드 실패 시 대체 텍스트
    
    public init(imageURL: URL? = nil, badgeId: String? = nil, altText: String? = nil) {
        self.imageURL = imageURL
        self.badgeId = badgeId
        self.altText = altText
    }
}
```

```swift
// ChatMessageItem.swift — UI 모델 확장
public struct ChatMessageItem: Identifiable, Sendable, Equatable, Hashable {
    // 기존 필드...
    public let badgeImageURL: URL?
    
    // 새 필드
    public let userRole: UserRole           // 역할 (스트리머/매니저/일반)
    public let badges: [ChatBadge]          // 다중 뱃지
    public let titleName: String?           // 칭호 이름
    public let titleColor: String?          // 칭호 색상 (hex)
    
    public init(from message: ChatMessage, isNotice: Bool = false) {
        // 기존 매핑...
        self.userRole = UserRole(from: message.profile?.userRoleCode)
        self.badges = []  // parseSingleMessage에서 다중 뱃지 전달 시 활용
        self.titleName = message.profile?.title?.name
        self.titleColor = message.profile?.title?.color
    }
}
```

##### 1-C. ChatMessageParser 프로필 파싱 보강

```swift
// ChatMessageParser.swift — parseProfile 개선
private func parseProfile(_ value: AnyCodable?) -> ParsedProfile {
    // ... 기존 nickname, profileImageUrl 파싱 ...
    
    // 다중 뱃지 파싱 (badge dict의 모든 키-값 추출)
    if let badgeDict = profileDict["badge"]?.dictValue {
        for (key, val) in badgeDict {
            if let url = val.stringValue {
                result.badges.append(ChatBadge(
                    imageURL: URL(string: url),
                    badgeId: key,
                    altText: badgeIdToAltText(key)
                ))
            }
        }
    }
    
    // 칭호 파싱
    if let titleDict = profileDict["title"]?.dictValue {
        result.title = ChatTitle(
            name: titleDict["name"]?.stringValue ?? "",
            color: titleDict["color"]?.stringValue
        )
    }
    
    // 활동 뱃지 파싱 (activityBadges 배열)
    if let activityBadges = profileDict["activityBadges"]?.arrayValue {
        for badge in activityBadges {
            if let dict = badge.dictValue,
               let url = dict["imageUrl"]?.stringValue {
                result.badges.append(ChatBadge(
                    imageURL: URL(string: url),
                    badgeId: dict["badgeId"]?.stringValue,
                    altText: dict["title"]?.stringValue
                ))
            }
        }
    }
    
    return result
}
```

#### Phase 2: UI 렌더링 개선

##### 2-A. ChatMessageRow 뱃지/역할 영역 재설계

**목표 레이아웃** (치지직 웹 채팅 참조):

```
[시간] [역할아이콘] [뱃지1] [뱃지2] [칭호] 닉네임: 메시지 내용
```

```swift
// ChatMessageRow.swift — normalMessageView 개선안
private var normalMessageView: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
        // 1. 타임스탬프
        if showTS {
            Text(message.formattedTime)
                .font(DesignTokens.Typography.custom(
                    size: max(messageFontSize - 3, 9), 
                    weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.75))
                .padding(.trailing, 6)
        }
        
        // 2. 역할 아이콘 (스트리머/매니저)
        if let iconName = message.userRole.iconName {
            Image(systemName: iconName)
                .font(.system(size: messageFontSize - 2, weight: .bold))
                .foregroundStyle(roleColor)
                .padding(.trailing, 3)
        }
        
        // 3. 뱃지 이미지 (다중 지원)
        if showBadge {
            ForEach(Array(message.badges.prefix(3).enumerated()), id: \.offset) { _, badge in
                if let url = badge.imageURL {
                    CachedAsyncImage(url: url) {
                        // 로드 실패 시 대체 텍스트
                        if let alt = badge.altText {
                            Text(alt)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(DesignTokens.Colors.textTertiary)
                                .frame(width: 16, height: 16)
                                .background(DesignTokens.Colors.surfaceElevated, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.trailing, 2)
                }
            }
            // 기존 단일 뱃지 fallback
            if message.badges.isEmpty, let badgeURL = message.badgeImageURL {
                CachedAsyncImage(url: badgeURL) { EmptyView() }
                    .frame(width: 16, height: 16)
                    .padding(.trailing, 4)
            }
        }
        
        // 4. 칭호 (타이틀)
        if let titleName = message.titleName, !titleName.isEmpty {
            Text(titleName)
                .font(.system(size: max(messageFontSize - 3, 9), weight: .semibold))
                .foregroundStyle(titleColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(titleColor.opacity(0.12), in: Capsule())
                .padding(.trailing, 4)
        }
        
        // 5. 닉네임 (역할별 색상 적용) + 메시지
        (Text(message.nickname)
            .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .semibold))
            .foregroundStyle(nicknameDisplayColor)
        + Text(": ")
            .font(DesignTokens.Typography.custom(size: messageFontSize, weight: .regular))
            .foregroundStyle(DesignTokens.Colors.textTertiary.opacity(0.6))
        + Text(message.content)
            .font(DesignTokens.Typography.custom(size: messageFontSize))
            .foregroundStyle(DesignTokens.Colors.textPrimary.opacity(0.88)))
            .lineSpacing(spacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 역할 기반 닉네임 색상 (스트리머=치지직그린, 매니저=파란색, 일반=해시 기반)
private var nicknameDisplayColor: Color {
    switch message.userRole {
    case .streamer: return DesignTokens.Colors.chzzkGreen
    case .manager, .channelManager: return Color(hex: 0x5C9DFF)
    case .viewer: return nicknameColor  // 기존 djb2 해시 기반
    }
}

/// 역할 아이콘 색상
private var roleColor: Color {
    switch message.userRole {
    case .streamer: return DesignTokens.Colors.chzzkGreen
    case .manager, .channelManager: return Color(hex: 0x5C9DFF)
    case .viewer: return DesignTokens.Colors.textTertiary
    }
}

/// 칭호 색상 (hex 문자열 → Color 변환)
private var titleColor: Color {
    if let hex = message.titleColor, let value = UInt(hex.replacingOccurrences(of: "#", with: ""), radix: 16) {
        return Color(hex: value)
    }
    return DesignTokens.Colors.textSecondary
}
```

##### 2-B. 뱃지/역할 비교 (현재 vs 개선 후)

**현재 CView_v2 채팅:**
```
10:30:45 [뱃지이미지] 닉네임: 안녕하세요
10:30:46 닉네임2: ㅋㅋㅋ
10:30:47 [뱃지이미지] 닉네임3: 반갑습니다
```

**개선 후 (치지직 웹 스타일):**
```
10:30:45 🎙️ [구독뱃지] [활동뱃지] 「VIP」 스트리머닉: 안녕하세요    ← 스트리머 (녹색)
10:30:46 닉네임2: ㅋㅋㅋ                                          ← 일반 유저
10:30:47 🔧 [뱃지] 매니저닉: 반갑습니다                             ← 매니저 (파란색)
10:30:48 [구독3개월] 「열혈팬」 구독자닉: 와!                        ← 구독자 (칭호 포함)
```

#### Phase 3: 추가 개선사항

##### 3-A. 구독 뱃지 개월별 시각적 차등

| 구독 기간 | 뱃지 스타일 | 색상 |
|-----------|-----------|------|
| 1개월 미만 | 일반 구독 아이콘 | 치지직 그린 |
| 1~3개월 | 은색 테두리 | `#C0C0C0` |
| 3~6개월 | 금색 테두리 | `#FFD700` |
| 6~12개월 | 다이아몬드 테두리 | `#B9F2FF` |
| 12개월+ | 크라운 + 빛남 효과 | `#FFD700` + glow |

##### 3-B. 스트리머/매니저 메시지 강조 옵션

```swift
// ChatRenderConfig에 추가할 옵션
let highlightStreamer: Bool      // 스트리머 메시지 배경 강조
let highlightManager: Bool       // 매니저 메시지 배경 강조
let showRoleBadge: Bool          // 역할 아이콘 표시
let showTitle: Bool              // 칭호 표시
```

- 스트리머 메시지: 연한 녹색 배경 (`chzzkGreen.opacity(0.06)`)
- 매니저 메시지: 연한 파란색 배경 (`accentBlue.opacity(0.06)`)
- 설정에서 토글 가능

##### 3-C. 프로필 팝오버 개선 (ChatUserProfileSheet)

현재 프로필 팝오버에 뱃지/역할/칭호 정보 반영:

```
┌──────────────────────────────────┐
│  [프로필 이미지]                  │
│  닉네임                          │
│  🎙️ 스트리머  |  🔧 매니저       │  ← 역할 표시 추가
│  ──────────────────────          │
│  뱃지: [뱃지1] [뱃지2] [뱃지3]    │  ← 뱃지 목록 추가
│  칭호: 「열혈팬」                 │  ← 칭호 표시 추가
│  구독: 6개월                     │  ← 구독 정보 추가
│  ──────────────────────          │
│  🔇 뮤트  | 🚫 차단  | 🔗 프로필  │
└──────────────────────────────────┘
```

---

## 4. 구현 우선순위 및 로드맵

### Phase 1: 핵심 뱃지/역할 시스템 (예상 작업량: 중) ✅ 완료

| 순서 | 작업 | 수정 파일 | 상태 |
|------|------|----------|------|
| 1 | `UserRole` enum 추가 | `ChatModels.swift` | ✅ |
| 2 | `ChatBadge`에 `badgeId`, `altText` 추가 | `ChatModels.swift` | ✅ |
| 3 | `ChatMessageItem`에 `userRole`, `titleName`, `titleColor` 추가 | `ChatMessageItem.swift` | ✅ |
| 4 | `parseProfile()` 칭호 파싱 + 다중 뱃지 지원 | `ChatMessageParser.swift` | ✅ |
| 5 | `ChatMessageRow` 뱃지/역할/칭호 렌더링 개선 | `ChatMessageRow.swift` | ✅ |
| 6 | 닉네임 색상에 역할 반영 | `ChatMessageRow.swift` | ✅ |

### Phase 2: 멀티채팅 UX 개선 (예상 작업량: 중~대) ✅ 완료

| 순서 | 작업 | 수정 파일 | 상태 |
|------|------|----------|------|
| 7 | 세션 최대 수 제한 + 피드백 | `MultiChatSessionManager.swift` | ✅ |
| 8 | 세션 복원 (앱 재시작 시) | `MultiChatSessionManager.swift`, `SettingsStore.swift` | ✅ |
| 9 | 채널 추가 피드백 개선 (비방송/중복) | `MultiChatView.swift`, `FollowingView+MultiChat.swift` | ✅ |
| 10 | 채널 탭 드래그 순서 변경 | `FollowingView+MultiChat.swift` | ✅ |
| 11 | 전체 재연결 버튼 | `MultiChatSessionManager.swift`, UI | ✅ |

### Phase 3: 고급 기능 (예상 작업량: 대) ✅ 완료

| 순서 | 작업 | 수정 파일 | 상태 |
|------|------|----------|------|
| 12 | 그리드 모드 (다중 채팅 동시 표시) | `MultiChatView.swift` (새 레이아웃) | ✅ |
| 13 | 채팅 통합 뷰 | `MergedChatView.swift`, `ChatChannelPickerView.swift` | ✅ |
| 14 | 스트리머/매니저 메시지 배경 강조 옵션 | `ChatRenderConfig`, `ChatMessageRow.swift`, `ChatSettingsQualityView.swift` | ✅ |
| 15 | 프로필 팝오버 뱃지/역할 표시 | `ChatUserProfileSheet` | ✅ |
| 16 | 구독 뱃지 개월별 차등 스타일 | `ChatMessageRow.swift` | ✅ |

---

## 부록: 파일 수정맵

```
Sources/
├── CViewCore/
│   └── Models/
│       ├── ChatModels.swift          ← UserRole enum, ChatBadge 확장, ChatTitle 파싱 지원
│       └── ChatMessageItem.swift     ← userRole, badges, titleName, titleColor 필드 추가
├── CViewChat/
│   └── ChatMessageParser.swift       ← parseProfile() 칭호/다중뱃지 파싱 보강
├── CViewApp/
│   ├── Views/
│   │   ├── ChatMessageRow.swift      ← 뱃지/역할/칭호 렌더링 전면 개편
│   │   ├── MultiChatView.swift       ← 세션 제한, UX 피드백
│   │   └── FollowingView+MultiChat.swift ← 탭 드래그, UX 피드백
│   ├── ViewModels/
│   │   └── ChatViewModel.swift       ← ChatMessageItem 생성 시 새 필드 매핑
│   └── Services/
│       └── MultiChatSessionManager.swift ← 세션 제한, 복원, 전체 재연결
└── CViewPersistence/
    └── SettingsStore.swift           ← 멀티채팅 세션 목록 저장/복원
```

---

> **참고**: 이 문서의 코드 스니펫은 개선 방향을 보여주기 위한 의사 코드이며, 실제 구현 시 기존 코드 패턴(Actor isolation, @Observable, Sendable 등)과 정합성을 확인해야 합니다.

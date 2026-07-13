# FontGrid (08FOSE) — 기능 사양서

macOS에 설치된 폰트를 그리드로 훑어보고, 미리보기·즐겨찾기·메모·태그·세부 정보 확인을 빠르게 할 수 있는 macOS 네이티브 앱 (SwiftUI + AppKit, macOS 13+).

이 문서는 **현행 구현(v0.4.4) 기준 동작 사양**이다. 색·간격 등 디자인 토큰의 실제 값은 `Theme.swift`를 단일 출처로 한다.

---

## 1. 데이터 모델

### FontFamily (`FontLibrary.swift`)
- 소스: `NSFontManager.shared.availableFontFamilies`
- 제외: 이름이 `.`로 시작하는 시스템 폰트
- 필드:
  - `name`: 표시 이름 (CJK 디코딩 적용)
  - `memberFontNames: [String]`: PostScript 이름, weight 오름차순 정렬
  - `weightCount: Int`: 멤버 수 (`memberFontNames.count`)
  - `script: ScriptCategory`: 주력(primary) 스크립트 버킷 — `korean / japanese / chinese / latin / symbol / other`
- 정렬: `localizedCaseInsensitiveCompare` 오름차순
- **주력 스크립트 분류(coverage 우선순위)**: 대표 글자 커버로 판정하되 순서가 핵심 —
  한글(가)→korean / 가나(あ·ア)→japanese / 한자(一)→chinese / 비라틴 고유문자(아랍·태국·인도계 등)→other / 라틴(A)→latin / 키릴·그리스 단독→other / 아무 문자체계도 없음→symbol.
  한글 폰트가 가나·한자를 품어도 한글 우선이라 korean으로, 라틴 끼고 있는 태국/아랍은 other로 감.
- 통계 `FontLibraryStats`: `total` + 카테고리별 `counts`

### CJK family 이름 디코딩 (중요·비자명)
NSFontManager는 한글 등 비-ASCII family 이름을 `/B9CC/B144/C124/CCB4` 같은 슬래시 구분 16진수 유니코드 스칼라로 반환함. 첫 글자가 `/`이면 split → hex → `Unicode.Scalar` → `Character`로 복원해야 "만년설체"가 보인다. 디코딩 실패 시 원본 유지.

### Member layout
`NSFontManager.availableMembers(ofFontFamily:)`가 반환하는 배열의 row 구조:
`[postScriptName: String, faceName: String, weight: NSNumber, traits: NSNumber]`

### PinsStore
- `UserDefaults` 키: `FontGrid.pins` (구버전의 `FontGrid.favorites`는 앱 시작 시 1회 마이그레이션)
- family 이름을 추가 순서대로 보관 → **가나다순(`sorted`)** 과 **최근 추가순(`byRecency`)** 둘 다 제공
- 토글 시 즉시 영구화

### MemoStore (`MemoStore.swift`)
- `UserDefaults` 키: `FontGrid.memos`
- 저장 형식: `[String: String]` (family 이름 → 메모 텍스트), 빈 문자열이면 키 삭제
- **태그 파싱**: 메모 안에서 `#`로 시작하는 토큰을 추출 (`#` 다음부터 **공백·쉼표·줄바꿈 직전까지**, 소문자 정규화, 빈 토큰 무시)
  - `tags(for:)`: 폰트별 태그 집합
  - `tagCounts`: 전체 태그 + 사용 폰트 수, **빈도 내림차순**(동률 시 가나다)

### FontMetadata (`FontMetadata.swift`)
상세 뷰 정보 섹션용. 첫 멤버의 폰트 파일 sfnt 테이블 + CoreText name 테이블에서 추출하여 표시 순서대로 `entries`(label/value 또는 features) 구성:
- **Format**: 파일 확장자 + `CFF`/`CFF2` 테이블 유무 → `OTF / TTF / TTC / dfont`
- **File size**: 파일 바이트 (`ByteCountFormatter`)
- **Glyphs**: `CTFontGetGlyphCount` (천 단위 콤마)
- **UPM**: `CTFontGetUnitsPerEm`
- **Weight**: OS/2 `usWeightClass` → `400 · Regular` 형식 (**단일 weight 패밀리에서만 표시**)
- **Width**: OS/2 `usWidthClass` → `Condensed/Normal/Expanded` 등
- **Version**: name 테이블 (`Version ` 접두 제거)
- **Features**: GSUB/GPOS FeatureList 태그 합집합 (liga, smcp, ss01…)
- **Foundry**: name 테이블 manufacturer
- **Scripts**: 폰트가 의미 있게 덮는 스크립트 상위 3개 (기술 용어, 임계값 적용, 고유 스크립트 우선). 상세에서 Features와 같은 파란 이탤릭 표기
- **Copyright**: name 테이블 copyright

---

## 2. 화면 구성

3분할 + 중앙 하단 고정 입력바:

```
┌─────────┬─────────────────────────┬─────────┐
│         │                         │ 즐겨찾기  │
│  좌측    │      폰트 그리드          │─────────│
│ 사이드바  │   (상세 뷰는 오버레이)     │  태그    │
│         │                         │─────────│
│         ├─────────────────────────┤ 버전     │
│ (검색/   │   프리뷰 텍스트 입력바      │ 푸터     │
│ 필터/    └─────────────────────────┘         │
│ 레이아웃/ │                         │         │
│ 외형)    │                         │         │
└─────────┴─────────────────────────┴─────────┘
```

- 좌/우 사이드바: **드래그로 폭 조절** (기본 좌 240·우 256, 최소 240, 최대 440pt), 폭은 **영구 저장되어 재시작 시 복원**
- 기본 윈도우 크기: 1280×860 (최소 880×640). 윈도우 프레임(크기·위치)은 **SwiftUI `WindowGroup`이 자동 저장·복원**(별도 autosave name 지정 금지 — 이중 autosave가 충돌해 작은 창이 화면 상단에 붙는 버그가 있었음)
- 윈도우 스타일: `.titleBar` + `.fullSizeContentView` (시스템 타이틀바 위로 콘텐츠 확장)
- **라이트/다크 모드 전환 지원** (기본 다크)
- 선택 가능한 배경 "Wallpaper" 오버레이 (모드별 개별 기억)
- 중앙 상단: 좌측 `08FOSE`, 우측 **현재 필터 상태 라벨** — 기본 `NNN fonts`, 필터 시 `NNN Pinned/Memoed/Muted`·스크립트명, 2개 이상이면 가운뎃점으로 결합하며 약어(PIN·MEM·MUT, KR·JP·LTN·ETC), 태그 활성 시 `Tag : XXX`. 좌측 패널 접힘 시 신호등과 안 겹치게 들여쓰기

### 세션 상태 복원 (재시작 시)
앱을 껐다 켜면 마지막 상태를 재현한다 — 윈도우 크기·위치, 좌/우 패널 폭, 좌측 패널의 모든 선택(검색어·Weights·Pinned/Memo only·Script 버킷·Tag·Columns·Font Size), 그리고 **중앙 그리드의 스크롤 위치**. 스크롤은 픽셀 Y로 저장하되 위 항목들이 동일하게 복원되어 레이아웃이 결정적이므로 같은 행에 안착한다(`NSScrollView` introspect, 콘텐츠 높이가 자랄 때까지 재시도). 저장된 폰트 수가 줄어 목표 Y에 못 미치면 가능한 최대 위치로 클램프.

---

## 3. 기능

### 3.1 검색 (좌측 사이드바 상단)
- family 이름 **또는 메모 내용** 부분 일치, 대소문자 무시 (`localizedCaseInsensitiveContains`)
- clear 버튼 (X)은 텍스트 있을 때만 노출

### 3.2 필터 (좌측 "Filters")
- **Weights**: 라벨 `1 / 2+ / 4+ / 6+`, 구간 `1` / `2–3` / `4–5` / `6+` (`.exactly(1)` / `.range(2,3)` / `.range(4,5)` / `.atLeast(6)`), 서로 배타적. All 버튼 없음 — **아무 칩도 선택 안 됨 = All**. 단일 선택(다른 칩 누르면 교체), 선택된 칩 재클릭 시 해제(All). 현재 칩에 없는 옛 저장값은 로드 시 All로 정규화
- **Collections**: `Pinned` / `Memo` (보유 family만) + `Show/Hide muted` 토글과 `Muted`(muted만 보기) — 항목이 없어도 비활성하지 않고, 누르면 빈 결과("Nothing found")
- **Script 버킷**: Korean / Japanese / Latin / Other (주력 스크립트 기준, 다중 선택 시 합집합). **Chinese·Symbol은 분류상 Other로 통합**(전용 버튼 없음)
- **Tag**: 우측 태그 캡슐로 선택 (단일 토글)
- 검색·모든 필터·태그는 **AND**로 결합 (단 `Muted`(only)는 Show/Hide보다 우선)

### 3.2a Muted (원하지 않는 폰트)
- 상세 뷰의 **Mute** 버튼으로 토글, `FontGrid.muted`에 영구 저장
- muted 폰트는 그리드 셀·상세(타이틀/헤더 배경/weight 샘플)가 **딤** 처리(클릭은 유지)
- Collections의 `Show/Hide muted`로 그리드 노출 제어, `Muted`로 muted만 보기
- Export/Import에 muted 포함

### 3.3 레이아웃 (좌측 "Layout")
- **Columns**: 1 ~ N 슬라이더
  - N은 윈도우 폭에서 자동 계산: `floor((usableWidth + spacing) / (minCellWidth + spacing))`
  - 최소 셀폭: 120pt, 그리드 패딩: 16pt, 셀 간격: 6pt
  - 리사이즈 시 N 재계산, 현재 값이 넘으면 자동 축소
- **Font Size**: 기준 28pt에 오프셋 `-8 ~ +20` 적용 (= 셀 프리뷰 20~48pt). 상세 weight 행은 기준 40pt + 동일 오프셋

### 3.4 외형 (좌측 "Appearance")
- **Wallpaper**: `0`(없음) + 4종. 다크/라이트 모드별로 선택을 따로 기억
  - 각 월페이퍼는 모드별로 블렌드 모드·불투명도가 개별 지정됨(`WallpaperOverlay`).
  - **라이트 모드 4번**은 다른 월페이퍼와 달리 단일 블렌드가 아니라 **여러 레이어를 겹쳐 합성**한다(현재 `multiply 0.6` + `soft light 0.6`). `lightLayerOverrides`에 등록된 월페이퍼만 이 멀티-레이어 경로를 타고, 나머지는 기존 단일 블렌드 한 겹으로 동작.
- **Theme**: Dark / Light 전환

### 3.5 프리뷰 텍스트
- `@AppStorage("previewText")`로 영구 저장
- 기본값: `The quick brown fox jumps over lazy dog`
- 빈 값 폴백: `The quick brown fox jumps over lazy dog.` (마침표 포함)
- 입력바는 중앙 영역 하단 고정, **앱 시작 시 자동 포커스**

### 3.6 폰트 셀
- 좌상단: family 이름 (악센트 색)
- 우상단:
  - 평소: weight 수 뱃지 (`%02d`, 예: `08`)
  - 호버 또는 즐겨찾기됨: 즐겨찾기 **점(dot)** 토글 (채워짐=즐겨찾기)
  - 메모 있으면: 별도 **메모 점**(블루) 표시
- 본문: 프리뷰 텍스트를 해당 폰트로 한 줄, ellipsis (Core Text 직접 렌더 — 폴백 글리프 클리핑 방지)
- 테두리 색: 메모 있음(블루) > 즐겨찾기(악센트) > 호버 > 기본
- **호버 시 weight 자동 순환**: 멤버 ≥ 2개면 400ms 간격으로 다음 weight, 호버 해제 시 첫 weight 복귀 (프리뷰 라벨만 리렌더)
- 클릭 → 상세 뷰

### 3.7 상세 뷰 (오버레이)
- 진입: 셀/즐겨찾기 행 클릭. 닫기: X 또는 **ESC**
- **← / → 로 이전·다음 폰트 연속 탐색** (상세 유지). 순회 대상은 연 출처 기준 — 그리드에서 열면 현재 필터·정렬된 그리드, 즐겨찾기에서 열면 즐겨찾기 목록(현재 정렬). 양 끝 clamp, 전환 시 메모 접고 정보 펼침 초기화. 텍스트 입력 중(프리뷰 바·메모 입력)에는 좌우키를 가로채지 않음(커서 이동), 상세가 열릴 때 입력 포커스는 해제
- 상세가 열린 동안(전체화면 제외) 중앙 상단 바는 `08FOSE·통계` 대신 **이전/다음 폰트명**(좌/다음 우)을 표기 — 비클릭, 좌우키 이동과 동일한 목록 기준
- 셀↔상세는 `matchedGeometryEffect` 전환
- **상단 헤더 (전체 폭, 높이 고정)**: family 이름(~23pt bold) + "N weight(s)" + 액션 3종
  - 이름이 길면 **축소하지 않고 tail 말줄임(…)**, 우측 닫기 버튼과 **16px 간격** 유지
  - 헤더 영역은 세로 압축 불가(`fixedSize(vertical:)`) — 메모가 자라도 헤더가 눌리지 않음
  - 한글 지원 폰트는 이름 오른쪽에 커스텀 **KR 배지**(squircle 실선 + 대문자 KR, 타이틀의 ~72% 높이, 중앙보다 살짝 위)
  - **Pin** 토글 / **Copy name**(1.5초 "Copied") / **Show in Finder**
- **정보 섹션** (1장 FontMetadata, 반응형):
  - 카드 폭 **≥ 640**: 중앙(weight 목록) 영역의 **우측 1/4**에 단일 컬럼으로 세로 나열
  - 카드 폭 **< 640**: 헤더 아래에 **여러 컬럼 그리드**(박스·구분선 없음), **2행까지** 노출 후 악센트색 **Read more/Read less**로 펼침. 마지막 줄에 한 항목만 남으면 전체 폭 사용. 정보+샘플 목록은 하나의 스크롤
  - Features 태그는 노트 블루 + 이탤릭, 항목 라벨은 소형 대문자
- **weight 목록**: 각 행 = face 이름 + PostScript(모노) + 큰 샘플
  - face 이름은 `NSFont(name:size:).fontDescriptor.object(forKey: .face)`, 실패 시 PS 이름 폴백
  - 샘플 텍스트는 전역 프리뷰 텍스트를 따르되, 해당 family에 **커스텀 specimen**이 설정돼 있으면 그것으로 대체(악센트 색)
- **메모 영역** (하단, 꺾쇠로 접힘/펼침 토글, 즉시 영구화):
  - **접힘**: 메모를 **한 줄 + tail 말줄임**으로 압축, specimen 숨김 → 중앙 weight 목록 공간 회복
  - **펼침**: 메모 편집기가 **내용(줄 수)에 따라 위로 성장** + 아래에 **specimen 박스**(고정 68pt, 메모와 20px 간격)
    - 빈 메모 = "Add a note…" 한 줄 높이만. 타이핑으로 줄이 늘거나 카드 폭을 좁혀 래핑이 늘면 높이 재계산
    - 상한 = 메모 윗변이 **헤더 아래 구분선**에 닿는 지점(`카드높이 − 헤더 − 구분선 − specimen − 여백`). 상한 초과 시 그제야 메모 **내부 스크롤**, specimen은 바닥 고정
    - 성장 중에는 세로 스크롤바를 숨겨 줄 추가 시 깜빡임 방지(콘텐츠가 상한을 실제로 넘을 때만 표시)
  - **커스텀 specimen**: family별로 저장, 설정 시 그 family의 모든 weight 샘플을 대체
- **Mute 버튼**: 헤더 액션줄(Pin/Copy/Show in Finder 옆)에서 muted 토글 (§3.2a)

### 3.7a Glyphs 뷰어 (상세, weight 목록 아래)
- weight 샘플 아래에 좌우 24px 여백의 구분선 → **"Glyphs"** 타이틀 + 우측 weight 풀다운(기본 Regular; 단일 weight면 메뉴 없이 이름만)
- 폰트의 **전체 글리프(GID 0..N)** 를 샘플 텍스트 크기로 전체폭 격자 배열(컬럼은 폭 측정 후 `.flexible` 균등 분할)
- 성능: `LazyVGrid` 고정 셀 + `Canvas` 직접 드로잉으로 가상화(보이는 셀만), 5만 글리프 CJK도 부드럽게
- 렌더: **매핑되는 글리프는 문자를 텍스트(CTLine)로 그려 컬러 폰트의 실제 색 이모지까지 표시**, 매핑 없으면 GID 외곽선
- 셀 박스: 복사 가능 = 연한 채움, 불가 = inner 테두리선만(글자 0.8 투명). 호버 시 진해짐
- 클릭: 매핑 문자를 클립보드 복사(`COPIED`), 불가 시 악센트 `FAILED`. 호버 툴팁 = 그 문자
- 역매핑(glyph→문자): BMP는 전 폰트 배치, **astral(이모지)은 글리프 8000개 미만 폰트만**(폰트별 1회 빌드·캐시, ~10–25ms). 단일 코드포인트만 — ZWJ·다중코드포인트 이모지·리거처는 매핑/복사 불가
- ←/→ 폰트 이동 시 상세 스크롤 최상단 리셋(`.id(family.id)`)

### 3.8 즐겨찾기 + 태그 (우측 패널)
- **PINNED**: 헤더에 개수 + **A–Z / Recent** 정렬 토글
  - 각 행: family 이름(작게) + 샘플 텍스트 + 메모 점 + 즐겨찾기 점
  - 샘플 weight는 결정적으로 선택: **Regular 페이스 → 없으면 OS/2 400 → 500 → 그래도 없으면 패밀리 기본**(`FontFamily.previewFontName`)
  - 행 클릭 → 상세 뷰 점프, 비어 있을 때 안내 문구
- **TAGS** (메모 태그 있을 때만 표시): 캡슐 버튼 = `태그 개수`, **빈도순**, `#` 제거
  - 단일 토글로 중앙 그리드 필터 (기존 필터와 AND), 활성 시 악센트 강조 (같은 캡슐 재클릭으로 해제)
  - 헤더의 꺾쇠(배경 없음, 호버 시 진해짐)로 **즐겨찾기 목록 위까지 확장/축소**
- **버전 푸터**: 패널 최하단 고정 36pt, 좌측 정렬 `© pa_st - v{버전}`

### 3.9 Settings (전체 화면 모달)
- 진입: 좌측 패널 하단 **Settings(기어)** 버튼 또는 **⌘,**. 닫기: 우상단 X 또는 **ESC**
- 전체 윈도우 블러 위에 콘텐츠를 중앙 패널 컬럼 폭(최대 480pt)으로 표시. 아래의 테마/Wallpaper 단축키는 미리보기 위해 살아 있음
- **Data**
  - Pins / Memos / Specimens 각각 **Clear All**(확인 다이얼로그, 개수 표시, 비어 있으면 비활성)
  - **Export**: Pins·Memos·Specimens·Muted를 JSON으로 저장 (`ExportData`, family 이름 키 기반이라 다른 Mac에서도 호환). **UI 상태(창·패널·필터·스크롤 등)는 포함하지 않음**
  - **Import**: JSON에서 Pins·Memos·Specimens·Muted **병합** (새 내보내기는 `pins` 키, 리네임 이전 백업의 `favorites` 키도 읽기 지원)
- **About / Shortcuts / Licenses**: 정보·단축키 안내·라이선스
- **Reset everything**(확인 다이얼로그): 콘텐츠(즐겨찾기·메모·specimen)와 프리뷰 텍스트 초기화 + `removePersistentDomain`으로 앱 UserDefaults 도메인 전체 삭제(필터·테마·Wallpaper·창 프레임·패널 폭·스크롤 등 모든 영속 키 포함) + 윈도우를 **1280×860 중앙**으로 즉시 복귀(`resetWindowSize`)
  - 주의: 패널 폭은 영속 값만 지워지고 화면상 폭은 재시작 후 반영될 수 있음. `resetWindowSize`는 화면이 1280×860보다 작아도 크기를 클램프하지 않음(개선 여지)

---

## 4. 인터랙션 규칙

- 셀/상세 weight 행/즐겨찾기 행의 이름·샘플은 **한 줄, ellipsis**
- 셀↔상세 전환은 부드러운 전환 (matched geometry)
- 셀 호버, 검색 포커스, 입력바 포커스, 활성 필터/태그는 시각적으로 명확히 구분
- 메모 있는 셀/즐겨찾기 행 호버 시 메모 일부(≤16자)를 네이티브 툴팁으로 표시

### 4.1 단축키 (전역, RootView 로컬 키 모니터)
텍스트 입력 중에는 글자/이동이 우선이라 발동하지 않음(아래 ESC 제외). `⌘/⌥/⌃` 조합은 시스템에 양보.

- **0–4**: Wallpaper (`0` 없음, `1–4` Wallpaper01–04)
- **t**: 다크 ↔ 라이트 토글
- **w**: Weights 필터 순환 (`All → 1 → 3+ → 5+ → All`)
- **p / m**: Pinned only / Memo only 토글
- **k / j / l / o**: Script 버킷 토글 (Korean / Japanese / Latin / Other) — Chinese·Symbol은 Other로 통합
- **u**: muted 표시/숨김 토글 (Show ↔ Hide)
- **i**: muted만 보기 토글
- **[ / ]**: 좌측 / 우측 패널 접기·펴기 (세션 한정)
- 한국어(두벌식) 입력 상태에서도 위 글자 단축키는 같은 물리 키의 라틴 글자로 매핑되어 동작
- **⌘ ,**: Settings 모달 토글 (입력 중에도 동작)
- **⌘ + ↑ / ↓**: Font Size 증가 / 감소
- **⌘ + → / ←**: Columns 증가 / 감소 (→ 증가)
- **← / →** (상세 열림, 입력 비포커스): 이전/다음 폰트
- **ESC 캐스케이드** (한 번에 한 단계): ① 입력 포커스 아웃 → ② Settings 닫기 → ③ 상세 닫기 → ④ 전체화면 해제 → ⑤ 무동작
  - 입력 중에도 ESC는 포커스 아웃을 위해 동작 (유일한 예외)
  - Settings 내 Clear All 확인 다이얼로그가 열려 있으면 ESC는 다이얼로그만 닫고 Settings는 유지

---

## 5. 비기능 요구

### 5.1 윈도우
- `.titleBar` + `.fullSizeContentView` 스타일. 신호등/타이틀바 영역 처리는 AppKit 보조
- 내부 UI는 **둥근 디자인** (카드/뱃지/캡슐/버튼 등). 라운딩 값은 `Theme`에 토큰화

### 5.2 테마
- **다크(기본) + 라이트** 모두 지원. 색은 appearance에 따라 적응(`Theme.adaptive`)
- 디자인 토큰은 `Theme.swift` 한 곳에 정의 (색·간격·radius·타입 크기)
- 주요 색 (참고):
  - 악센트: 다크 `#D9A633`(골드) / 라이트 `#FF4D00`(오렌지) — 활성/강조/family 이름
  - 메모·태그·노트 블루: `Theme.memoAccent`
  - 뱃지: `#54616F` — weight 카운트
  - 배경/표면/보더 계열은 모드별 적응

### 5.3 플랫폼
- macOS 13+ (`.macOS(.v13)`), Swift 5.9+
- SwiftUI 중심, AppKit/CoreText는 윈도우 크롬·NSFontManager·sfnt/name 테이블·Core Text 렌더에 한정

### 5.4 영속화 키 (UserDefaults / AppStorage)
**콘텐츠 데이터**
- `FontGrid.pins`, `FontGrid.memos`, `FontGrid.samples` (specimen), `FontGrid.muted`

**캐시**
- `FontGrid.scriptCache.v1`: psName → 스크립트 분류 결과. 시작 시 폰트별 sfnt 판독을 재실행하지 않기 위한 캐시 — 분류 규칙을 바꾸면 키 버전을 올릴 것

**환경/외형**
- `previewText`, `pinsByRecent`, `isLightMode`
- `selectedWallpaperDark`, `selectedWallpaperLight` (구 `selectedWallpaper`는 마이그레이션용)

**세션 UI 상태 (재시작 시 복원)**
- 좌측 패널 선택: `searchQuery`, `weightFilter`(문자열 인코딩 `all`/`exactly:N`/`atLeast:N`), `pinnedOnly`, `memoOnly`, `mutedFilter`(`shown`/`hidden`), `mutedOnly`, `scriptFilter`(rawValue 배열), `activeTag`, `columnCount`, `previewSizeOffset`
- 레이아웃: `leftPanelWidth`, `rightPanelWidth`
- 중앙 그리드 스크롤: `centerGridScrollY`
- 윈도우 프레임: SwiftUI `WindowGroup` 자동 저장(키 `NSWindow Frame SwiftUI.ModifiedContent…` — AppKit이 자동 관리)

`activeTag`를 포함한 위 세션 UI 상태는 모두 영속(과거 비영속에서 변경됨). **Reset everything**은 `removePersistentDomain`으로 이 모든 키를 한 번에 삭제한다.

---

## 6. 파일 구성 (참고)

```
Sources/FontGrid/
├─ FontGridApp.swift        앱 진입 / 윈도우(프레임 autosave·신호등 보정)
├─ RootView.swift           3분할 + 리사이즈 핸들(폭 영속) + Wallpaper 오버레이 + 전역 키 모니터
├─ AppViewModel.swift       검색/필터/태그/레이아웃/테마 상태 + 영속화 + resetToDefaults
├─ Theme.swift              디자인 토큰 + appVersion
├─ FontLibrary.swift        FontFamily 로딩/스크립트 판정/CJK 디코딩
├─ PinsStore.swift          핀 영속화
├─ MemoStore.swift          메모 + 태그 파싱
├─ SampleStore.swift        커스텀 specimen 영속화
├─ MutedStore.swift         muted(원치 않는 폰트) 영속화
├─ FontMetadata.swift       상세 정보 sfnt/name 추출
├─ FlowLayout.swift         줄바꿈 래핑 레이아웃 (태그/Features)
├─ FontCell.swift           셀 + 호버 weight 순환 + Core Text 프리뷰
├─ WrappingPreviewLabel.swift  상세 weight 행 래핑 프리뷰
├─ FontDetailView.swift     상세 오버레이 (정보/weight/메모/specimen/glyphs)
├─ MemoEditor.swift         메모/specimen 입력(NSTextView, 내용 높이 보고)
├─ SettingsView.swift       Settings 모달 + Export/Import + Reset
├─ PanelSection.swift       패널 섹션·구분선·리사이즈 디바이더
├─ NativeTooltip.swift      네이티브 툴팁
└─ Panels/{Left,Center,Right}Panel.swift   (CenterPanel: 그리드 + 스크롤 위치 영속)
```

---

## 7. 참고 코드 스니펫 (보존 가치 있는 비자명 로직)

### CJK family 이름 디코딩
```swift
private func decodeFontFamilyName(_ name: String) -> String {
    guard name.hasPrefix("/") else { return name }
    let parts = name.dropFirst().components(separatedBy: "/")
    let chars = parts.compactMap { hex -> Character? in
        guard let value = UInt32(hex, radix: 16),
              let scalar = Unicode.Scalar(value) else { return nil }
        return Character(scalar)
    }
    guard chars.count == parts.count else { return name }
    return String(chars)
}
```

### 메모 태그 파싱
```swift
static func parseTags(_ note: String) -> Set<String> {
    var tags = Set<String>()
    let chars = Array(note)
    var i = 0
    while i < chars.count {
        guard chars[i] == "#" else { i += 1; continue }
        var token = ""; var j = i + 1
        while j < chars.count {
            let c = chars[j]
            if c == "," || c.isWhitespace { break }
            token.append(c); j += 1
        }
        let t = token.lowercased()
        if !t.isEmpty { tags.insert(t) }
        i = j
    }
    return tags
}
```

### Show in Finder
```swift
let descriptor = CTFontDescriptorCreateWithNameAndSize(psName as CFString, 0)
guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else { return }
NSWorkspace.shared.activateFileViewerSelecting([url])
```

### maxColumns 계산
```swift
let usable = max(0, width - gridPadding * 2)
let n = Int(floor((usable + gridSpacing) / (minCellWidth + gridSpacing)))
return max(1, n)
```

### sfnt 테이블에서 OpenType feature 태그 (GSUB/GPOS 공통)
```swift
// FeatureList offset은 헤더 바이트 6, 각 FeatureRecord = 4바이트 태그 + 2바이트 오프셋
guard let flOff = u16(b, 6), let count = u16(b, flOff) else { return [] }
for i in 0..<count {
    let rec = flOff + 2 + i * 6
    let tag = String(bytes: b[rec..<rec+4], encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
    // …수집
}
```

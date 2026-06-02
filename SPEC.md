# FontGrid (08FOSE) — 기능 사양서

macOS에 설치된 폰트를 그리드로 훑어보고, 미리보기·즐겨찾기·메모·태그·세부 정보 확인을 빠르게 할 수 있는 macOS 네이티브 앱 (SwiftUI + AppKit, macOS 13+).

이 문서는 **현행 구현(v0.2.0) 기준 동작 사양**이다. 색·간격 등 디자인 토큰의 실제 값은 `Theme.swift`를 단일 출처로 한다.

---

## 1. 데이터 모델

### FontFamily (`FontLibrary.swift`)
- 소스: `NSFontManager.shared.availableFontFamilies`
- 제외: 이름이 `.`로 시작하는 시스템 폰트
- 필드:
  - `name`: 표시 이름 (CJK 디코딩 적용)
  - `memberFontNames: [String]`: PostScript 이름, weight 오름차순 정렬
  - `weightCount: Int`: 멤버 수 (`memberFontNames.count`)
  - `supportsKorean: Bool`: 한글 음절 `가`(U+AC00) 커버 여부
  - `supportsLatin: Bool`: 라틴 `A`(U+0041) 커버 여부
  - `isSymbolFont: Bool`: 어떤 실제 문자 체계도 커버하지 않음 → 딩벳/심볼/이모지
  - `isNonKoreanText: Bool` (파생): `!supportsKorean && !isSymbolFont` (= "English" 버킷)
- 정렬: `localizedCaseInsensitiveCompare` 오름차순
- 스크립트 판정: 35개 대표 문자(라틴/그리스/키릴/아랍/히브리/인도계/CJK/한글 등) 중 하나라도 `coveredCharacterSet`에 있으면 텍스트 폰트, 하나도 없으면 심볼 폰트

### CJK family 이름 디코딩 (중요·비자명)
NSFontManager는 한글 등 비-ASCII family 이름을 `/B9CC/B144/C124/CCB4` 같은 슬래시 구분 16진수 유니코드 스칼라로 반환함. 첫 글자가 `/`이면 split → hex → `Unicode.Scalar` → `Character`로 복원해야 "만년설체"가 보인다. 디코딩 실패 시 원본 유지.

### Member layout
`NSFontManager.availableMembers(ofFontFamily:)`가 반환하는 배열의 row 구조:
`[postScriptName: String, faceName: String, weight: NSNumber, traits: NSNumber]`

### FavoritesStore
- `UserDefaults` 키: `FontGrid.favorites`
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

- 좌/우 사이드바: **드래그로 폭 조절** (기본 240, 최소 240, 최대 440pt)
- 기본 윈도우 크기: 1280×860
- 윈도우 스타일: `.titleBar` + `.fullSizeContentView` (시스템 타이틀바 위로 콘텐츠 확장)
- **라이트/다크 모드 전환 지원** (기본 다크)
- 선택 가능한 배경 "Wallpaper" 오버레이 (모드별 개별 기억)

---

## 3. 기능

### 3.1 검색 (좌측 사이드바 상단)
- family 이름 **또는 메모 내용** 부분 일치, 대소문자 무시 (`localizedCaseInsensitiveContains`)
- clear 버튼 (X)은 텍스트 있을 때만 노출

### 3.2 필터 (좌측 "Filters")
- **Weights**: `All / 1 / 3+ / 5+` — `.all` / `.exactly(1)` / `.atLeast(3)` / `.atLeast(5)`
- **Favorites only / Memo only**: 즐겨찾기/메모 보유 family만
- **Korean / English**: 한글 폰트 / 비한글 텍스트 폰트
- **Tag**: 우측 태그 캡슐로 선택 (단일 토글)
- 검색·모든 필터·태그는 **AND**로 결합

### 3.3 레이아웃 (좌측 "Layout")
- **Columns**: 1 ~ N 슬라이더
  - N은 윈도우 폭에서 자동 계산: `floor((usableWidth + spacing) / (minCellWidth + spacing))`
  - 최소 셀폭: 120pt, 그리드 패딩: 16pt, 셀 간격: 6pt
  - 리사이즈 시 N 재계산, 현재 값이 넘으면 자동 축소
- **Font Size**: 기준 28pt에 오프셋 `-8 ~ +20` 적용 (= 셀 프리뷰 20~48pt). 상세 weight 행은 기준 40pt + 동일 오프셋

### 3.4 외형 (좌측 "Appearance")
- **Wallpaper**: `0`(없음) + 4종. 다크/라이트 모드별로 선택을 따로 기억
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
- **상단 헤더 (전체 폭)**: family 이름(~23pt bold) + "N weight(s)" + 액션 3종
  - **Favorite** 토글 / **Copy name**(1.5초 "Copied") / **Show in Finder**
- **정보 섹션** (1장 FontMetadata, 반응형):
  - 카드 폭 **≥ 640**: 중앙(weight 목록) 영역의 **우측 1/4**에 단일 컬럼으로 세로 나열
  - 카드 폭 **< 640**: 헤더 아래에 **여러 컬럼 그리드**(박스·구분선 없음), **2행까지** 노출 후 악센트색 **Read more/Read less**로 펼침. 마지막 줄에 한 항목만 남으면 전체 폭 사용. 정보+샘플 목록은 하나의 스크롤
  - Features 태그는 노트 블루 + 이탤릭, 항목 라벨은 소형 대문자
- **weight 목록**: 각 행 = face 이름 + PostScript(모노) + 큰 샘플
  - face 이름은 `NSFont(name:size:).fontDescriptor.object(forKey: .face)`, 실패 시 PS 이름 폴백
- **메모 영역**: 하단에 접힘(한 줄)/펼침(본문 가득) 토글, 즉시 영구화

### 3.8 즐겨찾기 + 태그 (우측 패널)
- **FAVORITES**: 헤더에 개수 + **A–Z / Recent** 정렬 토글
  - 각 행: family 이름(작게) + 샘플 텍스트(그 폰트로) + 메모 점 + 즐겨찾기 점
  - 행 클릭 → 상세 뷰 점프, 비어 있을 때 안내 문구
- **TAGS** (메모 태그 있을 때만 표시): 캡슐 버튼 = `태그 개수`, **빈도순**, `#` 제거
  - 단일 토글로 중앙 그리드 필터 (기존 필터와 AND), 활성 시 악센트 강조 (같은 캡슐 재클릭으로 해제)
  - 헤더의 꺾쇠(배경 없음, 호버 시 진해짐)로 **즐겨찾기 목록 위까지 확장/축소**
- **버전 푸터**: 패널 최하단 고정 36pt, 좌측 정렬 `© pa_st - v{버전}`

---

## 4. 인터랙션 규칙

- 셀/상세 weight 행/즐겨찾기 행의 이름·샘플은 **한 줄, ellipsis**
- ESC: 상세 메모가 펼쳐져 있으면 메모 접기, 아니면 상세 닫기
- 셀↔상세 전환은 부드러운 전환 (matched geometry)
- 셀 호버, 검색 포커스, 입력바 포커스, 활성 필터/태그는 시각적으로 명확히 구분
- 메모 있는 셀/즐겨찾기 행 호버 시 메모 일부(≤16자)를 네이티브 툴팁으로 표시

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
- `FontGrid.favorites`, `FontGrid.memos`
- `previewText`, `favoritesByRecent`, `isLightMode`
- `selectedWallpaperDark`, `selectedWallpaperLight` (구 `selectedWallpaper`는 마이그레이션용)
- (태그 활성 상태 `activeTag`는 비영속 — 세션 한정)

---

## 6. 파일 구성 (참고)

```
Sources/FontGrid/
├─ FontGridApp.swift        앱 진입 / 윈도우
├─ RootView.swift           3분할 + 리사이즈 핸들 + Wallpaper 오버레이
├─ AppViewModel.swift       검색/필터/태그/레이아웃/테마 상태
├─ Theme.swift              디자인 토큰 + appVersion
├─ FontLibrary.swift        FontFamily 로딩/스크립트 판정/CJK 디코딩
├─ FavoritesStore.swift     즐겨찾기 영속화
├─ MemoStore.swift          메모 + 태그 파싱
├─ FontMetadata.swift       상세 정보 sfnt/name 추출
├─ FlowLayout.swift         줄바꿈 래핑 레이아웃 (태그/Features)
├─ FontCell.swift           셀 + 호버 weight 순환 + Core Text 프리뷰
├─ FontDetailView.swift     상세 오버레이 (정보/weight/메모)
├─ MemoEditor.swift         메모 입력
├─ NativeTooltip.swift      네이티브 툴팁
└─ Panels/{Left,Center,Right}Panel.swift
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

# FontGrid (08FOSE) — 기능 사양서

macOS에 설치된 폰트를 그리드로 훑어보고, 미리보기·즐겨찾기·세부 정보 확인을 빠르게 할 수 있는 macOS 네이티브 앱 (SwiftUI + AppKit, macOS 13+).

이 문서는 **리빌드용 사양 정의**이며 현재 구현의 구조/파일은 다루지 않는다. 외형은 풀-커스텀 사각형 디자인으로 전면 재설계 예정.

---

## 1. 데이터 모델

### FontFamily
- 소스: `NSFontManager.shared.availableFontFamilies`
- 제외: 이름이 `.`로 시작하는 시스템 폰트
- 필드:
  - `name`: 표시 이름 (CJK 디코딩 적용)
  - `memberFontNames: [String]`: PostScript 이름, weight 오름차순 정렬
  - `weightCount: Int`: 멤버 수
- 정렬: `localizedCaseInsensitiveCompare` 오름차순

### CJK family 이름 디코딩 (중요·비자명)
NSFontManager는 한글 등 비-ASCII family 이름을 `/B9CC/B144/C124/CCB4` 같은 슬래시 구분 16진수 유니코드 스칼라로 반환함. 첫 글자가 `/`이면 split → hex → `Unicode.Scalar` → `Character`로 복원해야 "만년설체"가 보인다. 디코딩 실패 시 원본 유지.

### Member layout
`NSFontManager.availableMembers(ofFontFamily:)`가 반환하는 배열의 row 구조:
`[postScriptName: String, faceName: String, weight: NSNumber, traits: NSNumber]`

### FavoritesStore
- `UserDefaults` 키: `FontGrid.favorites`
- 저장 형식: `[String]` (family 이름)
- 토글 시 즉시 영구화

---

## 2. 화면 구성

3분할 + 하단 고정 입력바:

```
┌─────────┬─────────────────────────┬─────────┐
│         │                         │         │
│  좌측    │      폰트 그리드          │  우측    │
│ 사이드바  │   (상세 뷰는 오버레이)     │ 즐겨찾기  │
│         │                         │         │
│         ├─────────────────────────┤         │
│         │   프리뷰 텍스트 입력바      │         │
└─────────┴─────────────────────────┴─────────┘
```

- 좌측/우측 사이드바: 폭 ~180–240pt
- 기본 윈도우 크기: 1280×860
- 다크모드 강제

---

## 3. 기능

### 3.1 검색 (좌측 사이드바)
- family 이름 부분 일치, 대소문자 무시 (`localizedCaseInsensitiveContains`)
- clear 버튼 (X) 노출은 텍스트 있을 때만

### 3.2 필터
- **Min Weights**: `All / 2+ / 3+ / 5+` — 멤버 수 ≥ 값
- **Favorites only**: 즐겨찾기 family만 (우측 사이드바 토글)
- 검색·필터는 **AND**로 결합

### 3.3 레이아웃
- **Columns**: 1 ~ N
  - N은 윈도우 폭에서 자동 계산: `floor((usableWidth + spacing) / (minCellWidth + spacing))`
  - 최소 셀폭: 120pt, 그리드 패딩: 16pt, 셀 간격: 6pt
  - 윈도우 리사이즈 시 N 재계산, 현재 값이 넘으면 자동 축소
- **Font Size**: 14 ~ 56pt (셀 프리뷰 텍스트 크기)

### 3.4 프리뷰 텍스트
- `@AppStorage("previewText")`로 영구 저장
- 기본값: `The quick brown fox jumps over lazy dog`
- 빈 값일 때 폴백: `The quick brown fox jumps over lazy dog.` (마침표 포함)
- 입력바는 중앙 영역 하단 고정
- **앱 시작 시 입력바 자동 포커스**

### 3.5 폰트 셀
- 좌상단: family 이름
- 우상단:
  - 평소: weight 수 뱃지 (`%02d` 포맷, 예: `08`)
  - 호버 또는 즐겨찾기됨: 별 토글 버튼
- 본문: 프리뷰 텍스트를 해당 폰트로 한 줄, ellipsis
- 셀 높이: `max(90, fontSize + 62)`
- **호버 시 weight 자동 순환**: 멤버 ≥ 2개면 400ms 간격으로 다음 weight, 호버 해제 시 첫 weight로 복귀
- 클릭 → 상세 뷰

### 3.6 상세 뷰
- 진입: 셀 클릭
- 닫기: X 버튼 또는 **ESC**
- 상단 헤더:
  - family 이름 (대형, ~23pt bold)
  - "N weight(s)" 표기
  - 액션 3종:
    - **Favorite**: 토글
    - **Copy name**: family 이름을 `NSPasteboard.general`에 복사, 1.5초간 "Copied" 피드백
    - **Show in Finder**: 첫 멤버의 폰트 파일 위치를 Finder에서 표시
      - 구현: `CTFontDescriptorCreateWithNameAndSize(psName, 0)` → `CTFontDescriptorCopyAttribute(_, kCTFontURLAttribute)` → `NSWorkspace.shared.activateFileViewerSelecting([url])`
- 본문 (스크롤): 모든 weight를 리스트로
  - 각 행: face 이름 + PostScript 이름(모노) + 큰 샘플(40pt)
  - face 이름은 `NSFont(name:size:).fontDescriptor.object(forKey: .face)`로 추출, 실패 시 PS 이름 폴백

### 3.7 즐겨찾기 (우측 패널)
- 가나다순 (localized) 정렬
- 각 행: family 이름(작게) + 샘플 텍스트(그 폰트로) + 별(해제 가능)
- 행 클릭 → 해당 family 상세 뷰로 점프
- 비어 있을 때 안내 문구

---

## 4. 인터랙션 규칙

- 모든 표시 텍스트(셀/상세 행/즐겨찾기 행)는 **한 줄, ellipsis**
- ESC: 상세 뷰가 열려 있으면 닫기
- 셀↔상세 전환은 부드러운 전환 (matched geometry 등)
- 셀 호버, 검색 포커스, 입력바 포커스 등은 시각적으로 명확히 구분

---

## 5. 비기능 요구

### 5.1 윈도우
- **외곽 라운딩 없음 (사각형)** — 시스템 NSWindow는 강제 라운딩이므로 `.borderless` 스타일 마스크 사용
  - 신호등 버튼, 드래그 영역, 리사이즈, 그림자, 풀스크린은 직접 처리
- **모든 내부 UI 요소도 라운딩 없음** (버튼·인풋·카드·뱃지 등)

### 5.2 테마
- 다크모드 전제 (라이트모드는 비대상)
- 디자인 토큰은 한 곳에 정의 (색·간격·border)
- 현행 색상 참고값 (재정의 권장):
  - 악센트: `rgb(217, 166, 51)` 계열 옐로우 — 활성/강조/family 이름
  - 뱃지: `#54616F` — weight 카운트
  - 배경: `NSColor.windowBackgroundColor`

### 5.3 플랫폼
- macOS 13+ (`.macOS(.v13)`)
- Swift 5.9+
- SwiftUI 중심, AppKit은 윈도우 크롬·NSFontManager·CoreText에 한정

---

## 6. 향후 결정 사항 (리빌드 시점)

- 풀-커스텀 borderless 윈도우 구현
- 디자인 토큰 재정의 (사각형 전제, radius=0)
- ViewModel 도입 (필터/검색/선택을 한 모델로)
- 폴더 구조 분리 (App / Theme / Models / ViewModels / Views/{Chrome,Sidebar,Grid,Detail,Favorites,Input})

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

# 閱讀偏好與主題化設計（Markdown 預覽 + 程式碼檢視）

- 日期：2026-06-05
- 狀態：草案，待實作
- 範圍：macOS App（`apps/macos`）的檔案內容檢視

## 問題

目前查看文件內容時，樣式全寫死：

- **Markdown 預覽**（`MarkdownPreviewHTML.swift`）：內嵌 CSS 把字體、12px 程式碼字級、間距、配色（`Canvas`/`CanvasText`）全寫死。
- **程式碼檢視**（`CodeTextView.swift`）：固定 12px 等寬字、固定 8px 內距，語法色直接對應系統色。

整個 App 沒有任何設定／持久化機制（無 `UserDefaults`、`AppStorage`、Settings 畫面）。

## 目標

讓兩個檢視畫面共用一套「閱讀偏好」：可切換**配色主題**、調整**字級**與**行距**，並持久化。透過**內容區工具列**（快速調整）與 **Settings 視窗（Cmd+,）**（完整設定）兩個介面操作，兩者綁同一份狀態即時同步。

## 非目標（YAGNI）

- 使用者自訂主題／調色盤編輯器。
- 為 Markdown 程式碼區塊導入語法高亮（highlight.js）。
- 命名主題的自動淺/深雙版本（保留升級路徑，本次不做）。

## 架構決策

採「**語意調色盤作為單一事實來源**」：在 `ArchSightKit` 以純值型別定義主題，同時產出 Markdown 的 CSS 變數與程式碼檢視的 `NSColor`。`.system` 為特例，沿用動態系統色以維持自動淺/深。核心模型不相依 AppKit；hex→color 轉換放到各自的 adapter。

## 元件設計

### 1. 資料模型（`ArchSightKit`，純值、可測試）

```
ReadingPreferences (Equatable, Sendable, Codable)
├─ theme: ReadingThemeID        // .system | .github | .solarized | .highContrast
├─ fontScale: Double            // 0.85 / 1.0 / 1.15 / 1.3 / 1.5（步進，clamp）
└─ lineSpacing: LineSpacing     // .compact | .normal | .relaxed

ReadingThemeID: enum（system / github / solarized / highContrast）

ReadingTheme (純值)
├─ id: ReadingThemeID
├─ appearance: .light | .dark | .system
└─ palette: ReadingPalette

ReadingPalette
├─ background / foreground / secondaryText / border
├─ blockquote / codeBackground
└─ syntax: keyword / string / comment / number / function / type / operator
```

- 顏色以 hex 字串表示；`.system` 主題回傳「動態」標記，讓兩邊各走系統色。
- `ReadingTheme.catalog`：內建 4 主題 — System、GitHub、Solarized、High Contrast。
- `fontScale`：五級 `[0.85, 1.0, 1.15, 1.3, 1.5]`，預設 `1.0`，increase/decrease 在邊界 clamp。
- `LineSpacing`：compact / normal / relaxed。

此層**無 UI、無 AppKit 相依**，純單元測試。

### 2a. Markdown CSS adapter（改 `MarkdownPreviewHTML`）

- 新簽名 `render(_ markdown: String, preferences: ReadingPreferences)`；保留 `render(_:)` 以預設偏好轉呼，維持現有測試與呼叫點相容。
- `document(...)` 改用 CSS 變數，不再寫死數值：

```css
:root {
  --bg: <palette.background 或 Canvas>;
  --fg: <palette.foreground 或 CanvasText>;
  --code-bg / --border / --blockquote: ...;
  --font-scale: <prefs.fontScale>;
  --line-height: <lineSpacing 對應值>;
}
body { font-size: calc(1rem * var(--font-scale)); line-height: var(--line-height);
       color: var(--fg); background: var(--bg); }
```

- `.system` 主題時 `--bg/--fg` 仍輸出 `Canvas`/`CanvasText`。
- Markdown 程式碼區塊維持現狀（不上 token 色）。

### 2b. Code view adapter（改 `CodeTextView`）

- 新增 `ReadingThemeAppKit`（App 層）：吃 `ReadingTheme` 產 `NSColor`，`hex→NSColor`；`.system` 回傳現有動態色（`.labelColor`、`.systemPink`…）。
- `codeFont` 改由 `fontScale` 計算（`12 * scale`），不再 `static let`。
- `lineSpacing` → `NSParagraphStyle.lineHeightMultiple`，套到 attributed string。
- 背景／前景／token 色改吃 theme；`textContainerInset` 隨 `lineSpacing` 微調（compact 6 / normal 8 / relaxed 12）。

### 3. 持久化 Store（App 層，`@Observable`）

```
@Observable final class ReadingPreferencesStore
├─ var preferences: ReadingPreferences { didSet { persist() } }
├─ init(defaults: UserDefaults = .standard)      // 測試可注入
├─ load() / persist()    // Codable → JSON → UserDefaults 單一鍵 "reading.preferences"
└─ increaseFont() / decreaseFont() / setTheme(_) / setLineSpacing(_)
```

- 注入 `UserDefaults`（測試用 `UserDefaults(suiteName:)` 隔離）→ 可測 load/persist/clamp。
- 以 `.environment(store)` 注入，`ContentView`、工具列、Settings 共用同一份。

### 4a. 內容區工具列（`ContentView` 內容頁上方）

- 主題下拉（Picker，列 `ReadingTheme.catalog`）。
- `A-` / `A+`（呼叫 store increase/decrease，邊界 disable）。
- 行距 Picker（compact / normal / relaxed）。
- Markdown 與程式碼檢視共用此列；切檔不重置。

### 4b. Settings 視窗（Cmd+,）

- App 加 `Settings { ReadingSettingsView() }` scene。
- 綁同一 `ReadingPreferencesStore`，用 `Form`：主題、字級 stepper、行距、即時範例預覽。
- 兩介面綁同一 store → 改哪邊都同步。

### WKWebView 背景處理

- 命名主題（非 System）：讓 CSS `--bg` 實際畫出主題底色，`MarkdownPreviewView` 視主題切換 `drawsBackground`。
- System 主題：維持透明（`drawsBackground = false`）貼齊 SwiftUI 背景。

## 資料流

```
UserDefaults ⇄ ReadingPreferencesStore (@Observable)
                     │ .environment
        ┌────────────┼─────────────┐
     工具列        Settings 視窗   ContentView
        │            │              │
        └─ 改 preferences ─────────►├─ MarkdownPreviewView(content, preferences)
                                    │     → MarkdownPreviewHTML.render(content, preferences)
                                    └─ CodeTextView(content, preferences)
                                          → ReadingThemeAppKit → NSColor/font/paragraphStyle
```

## 分階段交付（TDD）

### Phase 1 — 核心模型（純 Kit，先寫測試）
- `ReadingPreferences` / `ReadingThemeID` / `ReadingTheme` / `ReadingPalette` / `catalog` / `fontScale` clamp / `LineSpacing`。
- `MarkdownPreviewHTML.render(_:preferences:)` 產出正確 CSS 變數。
- 測試：catalog 完整性、`.system` 走系統色、scale clamp、CSS 變數注入、舊 `render(_)` 相容。

### Phase 2 — 持久化 + Code view adapter
- `ReadingPreferencesStore`（注入 UserDefaults）load/persist/clamp 測試。
- `ReadingThemeAppKit` hex→NSColor、`.system` 回退測試。
- `CodeTextView` 套用 font / lineSpacing / color。

### Phase 3 — UI 接線
- 工具列 + Settings 視窗，綁 store，切檔不重置、兩介面同步。
- `MarkdownPreviewView` 改吃 preferences 重繪；WKWebView 背景切換。

每階段跑 `swift test` 維持綠燈再進下一階段。Phase 1、2 為邏輯主力（可測試）；Phase 3 偏 SwiftUI 接線，以手動驗證 + 既有 `AppStateTests` 風格為主。

## 測試策略

- **單元（Kit）**：模型、catalog、clamp、CSS 變數輸出、Markdown 相容性。
- **持久化**：注入隔離 `UserDefaults`，驗 load/persist/round-trip/clamp。
- **Adapter**：hex→NSColor 正確性、`.system` 回退。
- **手動驗證**：工具列與 Settings 同步、切檔保留設定、命名主題底色、淺/深外觀。

## 風險與緩解

- **hex→NSColor 解析錯誤** → 集中於單一 adapter 並單元測試各主題色。
- **WKWebView 背景閃爍** → 僅在主題真正改變時切 `drawsBackground`；偏好未變則 `MarkdownPreviewView` 既有的 `lastHTML` 快取避免重載。
- **既有測試破壞** → 保留 `render(_:)` 舊簽名相容層。

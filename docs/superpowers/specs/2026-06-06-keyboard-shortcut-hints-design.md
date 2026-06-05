# 快捷鍵提示（Cheat Sheet + Tooltip）Design

**狀態：** 已通過 brainstorming，待寫實作計畫。
**日期：** 2026-06-06
**前置依賴：** Plan B（快捷鍵）已完成並合併（`WorkspaceCommands.swift`、`@FocusedValue` 路由、各 `keyboardShortcut` 綁定皆已存在）。

---

## 目標

讓使用者更容易發現與記住已實作的快捷鍵，提供兩種提示：

1. **一覽表浮層（cheat sheet）** — 按 `Cmd+/`（或 Help 選單的「Keyboard Shortcuts」）叫出，分類列出所有快捷鍵，`Esc` 或點背景關閉。
2. **工具列 tooltip 加快捷鍵** — 在現有滑鼠懸停 tooltip 末端補上對應快捷鍵符號（例如「Open Folder ⌘O」）。

選單列本身（macOS `Commands`）已自動顯示快捷鍵，不在本次新增範圍。

---

## 架構決策：顯示用單一目錄（取向 A）

快捷鍵綁定目前散在 `WorkspaceCommands.swift`（各 `keyboardShortcut`）與 `ContentView`（`Cmd+W`）。為避免「一覽表 / tooltip / 實際綁定」三份清單漂移，新增一份**顯示用單一目錄** `ShortcutCatalog` 作為一覽表與 tooltip 的共同來源；實際 `keyboardShortcut` 綁定維持原處不動，並以單元測試守住目錄與預期集合一致。

**為何不做「完全單一來源」（取向 B，目錄同時生成綁定）：** SwiftUI 的 `Commands` 分散在不同 `CommandGroup` placement（app 級 vs 視窗級；Go / View / Help 不同區），從扁平目錄生成綁定會讓選單結構複雜化、改動面與風險大幅上升，對這個規模的 app CP 值低。取向 A 以小改動換取「一覽表與 tooltip 永遠一致」，漂移風險以測試緩解。

---

## 元件

### 1. `ArchSightKit/ShortcutCatalog.swift`（純值、可測）

```
public enum ShortcutCategory: String, CaseIterable, Sendable {
    case navigation   // Navigation
    case view         // View
    case tabs         // Tabs
    case help         // Help
}

public struct KeyChord: Equatable, Sendable {
    public let key: String        // 顯示用主鍵，例如 "P"、"["、"\\"、"1–9"
    public let command: Bool
    public let shift: Bool
    public let option: Bool
    public let control: Bool
    // 修飾鍵順序固定 ⌃⌥⇧⌘（macOS 慣例），組出例如 "⌘⇧[".
    public var display: String { ... }
}

public struct ShortcutHint: Equatable, Sendable, Identifiable {
    public let id: String         // 穩定 id，例如 "quickOpen"
    public let category: ShortcutCategory
    public let label: String      // 人類可讀，例如 "Quick Open"
    public let chord: KeyChord
}

public enum ShortcutCatalog {
    public static let all: [ShortcutHint] = [ ... ]
    public static func hint(_ id: String) -> ShortcutHint?   // tooltip 查詢
    public static func grouped() -> [(ShortcutCategory, [ShortcutHint])]  // 一覽表用
}
```

**目錄涵蓋（對齊 Plan B 實作）：**

| Category | Label | Chord |
|---|---|---|
| Navigation | New Window | ⌘N |
| Navigation | Open Folder | ⌘O |
| Navigation | Quick Open | ⌘P |
| Navigation | Find in File | ⌘F |
| Navigation | Back | ⌘[ |
| Navigation | Forward | ⌘] |
| View | Toggle Sidebar | ⌘B |
| View | Show Explorer | ⌘⇧E |
| View | Show Search | ⌘⇧F |
| View | Split Editor | ⌘\ |
| View | Increase Text Size | ⌘= |
| View | Decrease Text Size | ⌘- |
| Tabs | Go to Tab 1–9 | ⌘1–9 |
| Tabs | Previous Tab | ⌘⇧[ |
| Tabs | Next Tab | ⌘⇧] |
| Tabs | Close Tab / Window | ⌘W |
| Help | Keyboard Shortcuts | ⌘/ |

> `Cmd+N`（New Window）為 WindowGroup 預設綁定（非本專案 `keyboardShortcut` 顯式定義），**列入**目錄以利發現；一致性測試對它只驗顯示字串，不驗綁定來源。

### 2. `ArchSightApp/ShortcutCheatSheet.swift`（覆蓋式一覽表）

- 樣式比照現有 `QuickOpenPanel`（`.regularMaterial`、圓角、陰影、置中偏上）。
- 依 `ShortcutCatalog.grouped()` 分組渲染；每列左標籤、右 `chord.display`（等寬字體、`.secondary`）。
- `.onKeyPress(.escape) { onClose() }`；背景半透明遮罩 `.onTapGesture` 關閉。
- 自包含，輸入為 `onClose: () -> Void`。

### 3. `WorkspaceCommands.swift`（修改）

- `WorkspaceCommandActions` 新增 `var showShortcuts: () -> Void = {}`。
- 新增 `CommandGroup(after: .help)`（保留系統預設 Help 項，於其後追加）：
  - `Button("Keyboard Shortcuts") { actions?.showShortcuts() }.keyboardShortcut("/", modifiers: .command).disabled(actions == nil)`。

### 4. `ContentView.swift`（修改）

- 新增 `@State private var isShortcutsPresented = false`。
- 新增 `.overlay { if isShortcutsPresented { ... ShortcutCheatSheet(onClose:) } }`（與 Quick Open overlay 並列）。
- `focusedValue` 的 `WorkspaceCommandActions` 補 `showShortcuts: { isShortcutsPresented = true }`。
- 工具列 `.help()` tooltip 從目錄補快捷鍵，至少：Back（⌘[）、Forward（⌘]）、Open Folder（⌘O）、Split（⌘\）。做法：`.help("Back \(ShortcutCatalog.hint("back")?.chord.display ?? "")")` 或小 helper。

---

## 資料流

```
Cmd+/ 或 Help 選單
   → actions.showShortcuts()
   → ContentView.isShortcutsPresented = true
   → overlay 顯示 ShortcutCheatSheet
   → 讀 ShortcutCatalog.grouped() 分組渲染
   → Esc / 點背景 → isShortcutsPresented = false

工具列 tooltip
   → .help(label + ShortcutCatalog.hint(id).chord.display)
```

兩條路徑共用同一份 `ShortcutCatalog.all`。

## 錯誤處理

- 目錄為靜態常數，無 I/O、無失敗路徑。
- tooltip 查詢未命中時回退為原始說明字串（`?? ""`），不崩潰。

## 測試（Kit）

`Tests/ArchSightKitTests/ShortcutCatalogTests.swift`：
- `KeyChord.display` 修飾鍵順序與符號：`⌘P`、`⌘⇧[`、`⌘\`、`⌘=` 等。
- `ShortcutCatalog.all` 非空、每個 `ShortcutCategory` 至少一項、`id` 無重複、`(modifiers+key)` 綁定無重複（擋雙重綁定）。
- `hint(_:)` 命中與未命中行為。
- `grouped()` 涵蓋所有 category 且順序穩定。

App target（`ShortcutCheatSheet`、ContentView overlay、tooltip）以 `swift build` + 手動驗證把關（無單元測試慣例）。

## 手動驗證

1. `Cmd+/` 叫出一覽表；`Esc` 與點背景皆可關閉。
2. Help 選單有「Keyboard Shortcuts ⌘/」可點。
3. 一覽表分類正確、每項快捷鍵符號與實際綁定一致。
4. 工具列懸停 Back/Forward/Open Folder/Split → tooltip 顯示對應快捷鍵。
5. 在 Quick Open / Search 輸入框內，`/` 不會誤觸一覽表（`Cmd+/` 才會）。

---

## 非目標（YAGNI）

- 不做快捷鍵自訂 / 重新綁定。
- 不做選單列快捷鍵顯示（macOS 已自動）。
- 不把實際 `keyboardShortcut` 綁定改為由目錄生成（取向 B，明確排除）。

# Create the Markdown version of the Project Initiation Document
md_content = """# ArchSight 專案啟始與架構設計書 (Project Initiation Document)

## 1. 專案核心願景與哲學 (Vision & Philosophy)

**ArchSight** 是一款專為高級工程師設計的 macOS 原生輕量級原始碼觀測工具。其核心目標是徹底解決現代基於 Electron 的巨型 IDE（如 Cursor、VS Code）在「純程式碼審查、追蹤與多服務對照」場景下的資源暴食、啟動遲滯與不必要的 CPU 索引負載。

> ### 🛠️ 核心哲學：抽取而非發明 (Extraction over Invention)
> 不重複造輪子。前端利用 macOS 最輕量的原生核心進行渲染，底層極速檢索與語法分析直接管道化驅動生態系中最成熟的二進位效能怪獸（`ripgrep` & `Tree-sitter`），實現極致精簡與省電。

* **不要編輯、不要診斷：** 移除所有 Auto-complete, Code Actions 與重型 Linter，定位為純粹的「唯讀觀測艙」。
* **記憶體指標開銷：** 靜態運作時記憶體佔用保持在 $M \le 50\text{MB}$，避免大型專案索引導致的 Mac 風扇轟鳴。
* **按需喚醒 (Lazy-Loading)：** 對 Language Server Protocol (LSP) 採取完全克制的懶載入代理策略。

---

## 2. 技術選型與依賴組合 (Tech Stack)

| 模組單元 | 建議技術 | 選型理由與優勢 |
| :--- | :--- | :--- |
| **前端 UI & 渲染層** | SwiftUI / AppKit (Native) | 保證 30MB 級別的記憶體佔用、120Hz 滿幀滾動及系統級磨砂玻璃特效。 |
| **後端核心 (Core)** | Bun / Go (Compiled Single Binary) | 負責檔案系統快照、LSP JSON-RPC 通訊代理，編譯為單一二進位檔。 |
| **語法分析引擎** | Tree-sitter (C / C-Bridge) | 擺脫重型 TextMate 規則包，秒級抽離 AST 並生成高對比度語法高亮。 |
| **全文檢索通道** | ripgrep (`rg` 靜態二進位檔) | 直接內嵌於 App Bundle 中，全域搜尋效能的無冕之王。 |
| **進程間通訊 (IPC)** | Unix Domain Socket | 前端與核心二進位檔之間採用極低延遲、無額外網路開銷的本地 socket。 |

---

## 3. 系統架構與流程設計 (Architecture)

ArchSight 採用 **進程隔離 (Out-of-Process)** 架構，區分為負責視覺與互動的 Native 殼層，以及負責重型 IO 與協定處理的 Core 核心。

### 3.1 多專案扁平快照 (Workspace Snapshot)
不寫入任何硬碟快取與資料庫。當目錄被拖入時，Core 透過非阻塞的系統調用快速掃描並在記憶體中建立一個樹狀的映射節點（Tree Node）。支援將多個 Microservices 資料夾或獨立模組在一側側邊欄中 **扁平化合併（Flattened Collections）**，不干擾各自的實體路徑。

### 3.2 克制化懶載入 LSP Proxy 流程
為了確保極致的省電與輕量，LSP 的生命週期管理如下：

1. **預設休眠：** 專案載入時，完全不喚醒任何 LSP 進程。
2. **按需觸發：** 當使用者雙擊打開檔案，且對特定 Symbol 執行 `Cmd + Click`（跳轉定義）或尋找引用時，Core 檢查該語言的 LSP 狀態。
3. **精簡註冊：** 若未啟動，Core 於背景拉起該語言的 Language Server（例如 `gopls`、`tsserver`），並在 Initialize Request 中宣告 **關閉所有 `completionProvider`、`codeActionProvider` 與 `publishDiagnostics`**。只保留：
   * `textDocument/definition`
   * `textDocument/references`
4. **超時清理：** 當分頁關閉或專案處於閒置狀態（無任何 LSP 請求）超過 5 分鐘，核心立即發送 `SIGKILL` 清理該進程，釋放所有記憶體。

---

## 4. 初始專案目錄結構 (Project Workspace Blueprint)

此專案結構採用一體化單一倉庫管理（Monorepo 邏輯），將 Swift 前端與核心後端清晰抽離：

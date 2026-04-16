# O.Paperclip

**macOS iPhone / iPad 虛擬定位工具**，可透過 USB 或 Wi-Fi 對實體 iOS 裝置送出模擬座標，支援定點、A-B 路線、多點路線、固定路線匯入、搖桿控制，以及 KML 圖層輔助。

**使用前請先確認：你的 iPhone / iPad 已開啟開發者模式。**  
**如果這個專案對你有幫助，歡迎透過 Ko-fi 支持持續開發：https://ko-fi.com/agocia**

<p align="right">
  <a href="README.CH.md"><img alt="繁體中文" src="https://img.shields.io/badge/繁體中文-active-2d3748?style=flat-square"></a>
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-gray?style=flat-square"></a>
</p>

> ### 專案性質聲明
>
> O.Paperclip 為個人維護的開源專案，不是商業產品，也沒有專職團隊。本專案會持續跟著 macOS、iOS 與 `pymobiledevice3` 的變化調整，但仍請將它視為「持續演進中的實用工具」，而不是對所有環境都保證一致行為的封閉式產品。
>
> - 本專案主要針對 macOS 上的 iPhone / iPad 虛擬定位需求設計。
> - 連線穩定度會受到 iOS 版本、USB / Wi-Fi 環境、Developer Mode 與裝置信任狀態影響。
> - 若遇到問題，建議附上版本、裝置型號、連線方式與錯誤訊息回報 issue。
> - 本專案不承諾永久維護，也不對使用本工具所造成的任何損失負責。

## 功能亮點

### 模擬模式

| 模式 | 說明 |
| --- | --- |
| **定點** | 把裝置位置固定在單一座標 |
| **A-B** | 選擇起點與終點，自動規劃路線後移動 |
| **多點** | 依序經過多個自訂路徑點 |
| **搖桿** | 以方向鍵或 WASD 即時推動目前位置 |
| **固定路線匯入** | 從右側「匯入與收藏」套用已匯入的 GPX 固定路線 |

### 路線與地圖輔助

- 草稿黃線與活動藍線都會明確標出起點 / 終點。
- 閉圈路線會以單一「起點／終點」標記顯示，避免重疊。
- 尚未開始時顯示單趟預估時間；開始後即時顯示剩餘時間。
- 支援收藏點位、A-B 路線、多點路線與閉圈路線。
- 套用收藏時會自動切到相容模式，不需要手動切換。
- 支援匯入 GPX 固定路線與 KML PurePoint 圖層。

### 連線體驗

- 支援 **USB** 與 **Wi-Fi tunnel** 兩種連線方式。
- USB 拔除會主動偵測掉線，立即停止模擬並自動重連。
- 既有 tunnel 中斷或送點失敗時也會走自動重連流程。
- 可在已連線狀態下直接切換 USB / Wi-Fi。

## 系統需求

| 項目 | 需求 |
| --- | --- |
| macOS | macOS 14 Sonoma 以上 |
| iPhone / iPad | iOS 16 以上 |
| 裝置設定 | 需開啟 Developer Mode，且已信任此 Mac |
| 連線方式 | USB 或與 Mac 同網段的 Wi-Fi |
| 其他 | 無需自行安裝 Python、Homebrew 或 `pymobiledevice3` |

## 安裝

### 下載安裝

1. 前往 [Releases](../../releases) 下載最新版本。
2. 開啟 `.dmg` 後，將 `O.Paperclip.app` 拖到 `Applications`。
3. 第一次啟動時若被 Gatekeeper 擋下，請在 Finder 中右鍵 App，選擇「開啟」。

### 從原始碼建置

```bash
git clone https://github.com/agocia/O.paperclip.git
cd O.paperclip
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Release build
```

## 使用前準備

### 1. 開啟 iPhone / iPad 的開發者模式

`設定` → `隱私權與安全性` → `開發者模式` → 開啟後重新開機。

### 2. 先完成一次 USB 信任配對

首次透過 USB 連線時，iPhone / iPad 會詢問是否信任這台 Mac。請點選「信任」並輸入裝置密碼。

### 3. 若要使用 Wi-Fi，先用 USB 連成功一次

Wi-Fi tunnel 依賴先前的信任配對，因此第一次仍需先走 USB。

## 快速開始

### 1. 連線裝置

**USB：**

1. 插上 iPhone / iPad。
2. 開啟 O.Paperclip。
3. 確認側欄「連線模式」為 `USB`。
4. 點選「開始連線」。
5. 若跳出管理員密碼提示，輸入 macOS 管理員密碼以建立 tunnel。

**Wi-Fi：**

1. 確認裝置與 Mac 在同一個網路。
2. 將連線模式切到 `Wi-Fi`。
3. 點選「開始連線」。

連線成功後，側欄會顯示裝置名稱與狀態。若 USB 被拔除或 tunnel 中斷，App 會主動偵測掉線、停止模擬、顯示提示，並自動嘗試重連。

### 2. 選擇操作模式

模式選擇器目前提供四種模式：

- `A-B`
- `定點`
- `多點`
- `搖桿`

`固定路線` 已不再出現在模式選擇器中；請從右側「匯入與收藏」欄位匯入或套用。

### 3. 設定位置與開始模擬

**A-B：**

1. 在地圖上設定起點 A。
2. 確認 A 點。
3. 在地圖上設定終點 B。
4. 確認 B 點並選擇路線。
5. 點「開始移動」。

**定點：**

1. 在地圖上選定位置。
2. 點「釘選此位置」。

**多點：**

1. 依序在地圖上新增多個點位。
2. 點「開始移動」。

**搖桿：**

1. 啟用後以方向鍵或 `WASD` 推動位置。
2. 可持續調整方向，不必重新選點。

### 4. 停止或清除

- `停止`：停止目前模擬。
- `清除路線` / `清除定位點`：清掉草稿或目前定位內容。

## 匯入與收藏

右側「匯入與收藏」欄位可處理以下內容：

- 收藏目前點位
- 收藏 A-B 路線
- 收藏多點路線
- 收藏閉圈路線
- 匯入 GPX 固定路線
- 匯入 KML PurePoint 圖層

### 收藏套用規則

套用收藏時會自動切到正確模式：

- 收藏點位 → `定點`
- 收藏 A-B 路線 → `A-B`
- 收藏多點路線 → `多點`
- 收藏固定路線來源 → `多點`
- 收藏閉圈 → `多點`，並自動開啟閉圈

## PurePoint 圖層

KML PurePoint 圖層可用來在地圖上顯示自訂分類標記：

1. 點選「匯入 KML」。
2. 選擇 `.kml` 檔。
3. 匯入後可依分類篩選顯示。

## 常見問題

### 點「開始連線」後一直轉圈

請先確認：

- iPhone / iPad 已解鎖
- 已信任這台 Mac
- 已開啟開發者模式
- 若使用 Wi-Fi，兩端位於同一個網段

### 為什麼會跳管理員密碼

建立 tunnel 需要暫時的系統權限，這是正常行為。

### USB 拔掉後為什麼會停止移動

這是預期行為。App 會主動檢查 USB 裝置是否仍在線上；一旦確認掉線，就會停止模擬、顯示「已偵測裝置掉線，模擬已停止，正在嘗試重新連線。」並開始自動重連。

### 已經用 USB 連上了，可以直接切 Wi-Fi 嗎

可以。切換為 `Wi-Fi` 後，App 會先中斷目前 USB 連線，再重建 Wi-Fi tunnel。

### 停止後 GPS 沒恢復正常

請再執行一次清除定位，或重新啟動 iPhone 的定位服務。

## 診斷與維護

- Runtime logs 現在統一寫入 `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/`。
- 長時間運行會套用有上限的 log rotation，涵蓋 lifecycle、incident、model bootstrap 與 privileged tunnel log。
- 舊版遺留的 `O.Paperclip`、`O-Paperclip` Application Support 根目錄會在啟動時做一次性遷移，只清掉可再生的 log / tunnel artifact，保留使用者資料。
- DMG 建置產物改為輸出到 `build/dmg/artifacts/`，不再落在 repo root。
- 詳細維護流程請參考 [docs/maintenance.md](docs/maintenance.md)。

## 開發與測試

### 本機建置

```bash
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Debug build
```

### 測試

```bash
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip test
```

Shared scheme 補充：

- 共享的 `O.Paperclip` scheme 只會執行 `O.PaperclipTests`。Xcode 樣板產生的 UI 測試不再放在共享 test action 內。
- XCTest 啟動 host app 時，O.Paperclip 會改走最小化 placeholder scene 與 in-memory model container，避免邏輯測試依賴完整地圖 UI 的啟動流程。

## 專案結構

```text
O.Paperclip/
├── O.Paperclip/
│   ├── Core/
│   ├── Services/
│   ├── UI/
│   └── ContentView.swift
├── O.PaperclipTests/
├── bundled/
└── O.Paperclip.xcodeproj
```

## 免責聲明

本工具僅供開發測試、隱私保護與其他正當用途使用。請勿將其用於作弊、詐欺或任何違反平台條款與當地法律的行為。你需自行承擔使用方式與結果。

## 授權

MIT License，請參考 [LICENSE](LICENSE)。

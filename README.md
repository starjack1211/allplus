# All+ 單字本

原生 iPhone／iPad App，iOS 16 以上。使用 SwiftUI、Apple Vision、Core Image、Firebase Authentication 與 Firestore。

## 目前狀態

已建立原生 App 原始碼與雲端編譯流程，尚未在此 Windows 電腦完成 Xcode 編譯或 iPhone 實測。這個資料夾不是 IPA；要先讓 GitHub Actions 的測試與編譯通過，才能取得交給 iLoader 的檔案。

使用者提供的雜誌照片只作版面參考，沒有放入 App，也不會預載照片中的單字。

## 操作

1. 在「單元」按 ＋ 建立單元。
2. 進入單元，選「拍照／選照片辨識」。支援多頁文件掃描及一次選取最多十張照片。
3. 選「雜誌左右兩欄」或「單欄／已裁切」。照片先校正頁面、去陰影，再做繁體中文與英文辨識。
4. 查看去陰影預覽、辨識文字與待存清單。點項目校對英文、中文、詞性與分類；刪除誤抓內容，再按「存入單元」。
5. 單元內單字、片語分頁，右上角 ＋ 可手動新增；點既有項目可修改，左滑刪除，右滑收藏。
6. 單元首頁點「編輯」拖曳排序。單元內「⋯」可改名或刪除單元。
7. 「測驗」可複選單元，選英選中、中選英、拼字或翻卡；可限定單字、片語、收藏或錯題。選擇題最多四個不重複答案，題庫不足會減少選項。發音需主動點擊，不會自動播放。
8. 中文括號說明可在「我的」切換省略，原始意思仍保存。

## 辨識方式與限制

- 文件掃描器提供自動取景與透視校正；相簿照片也嘗試偵測明確的頁面邊界。
- 先將圖片轉為灰階，再以局部模糊估算紙張亮度，用「原圖亮度 ÷ 局部紙張亮度」補償漸層陰影，避免整張直接加亮而抹掉文字。輸入最長邊上限 3600，逐張處理以控制記憶體。
- 使用去陰影版優先辨識，並在同位置的原圖辨識信心明顯較高時回退。中英碎片按行合併，左右欄分別處理。
- 以 Vocabulary、參考字彙、Language Spotlight 的結構提取；略過例句、練習題、句型和長篇說明。詞性保留原文，片語沒有明示詞性時標記為 `phr.`，可手動修正。
- 深色反光、手指遮擋、嚴重失焦、頁面彎曲或跨欄文字仍可能出錯；去陰影不能還原看不見的文字。尚無實機辨識率測量，不能宣稱特定準確率。
- 此版採手機端 OCR 與版面規則，不會把照片傳至 AI 或 Firebase，也不需辨識 API 金鑰。

## Google 登入與雲端備份

已放入使用者提供的 Firebase iOS 設定檔，Bundle ID 為 `com.study.allplus`。每次產生專案後，`scripts/configure.py` 會自動寫入 Google 登入回呼網址。

在 Firebase 控制台完成：

1. Authentication → 登入方式 → Google → 啟用。
2. Firestore Database → 建立資料庫。若沒有現有資料庫，可選正式模式，再部署本資料夾的 `firestore.rules`。若專案已經有其他 App 的規則，請將本規則的 `/users/{userId}/backups/{backupId}` 區塊合併進原有規則，避免覆蓋其他 App 的設定。也要移除會讓此路徑公開的廣泛允許規則。
3. 規則只允許已登入使用者讀寫自己的備份，不需要 Firebase Storage。

平時資料會自動存入手機，Google 登入後可手動「備份目前資料至雲端」。在另一支手機登入同一 Google 帳號後，點「從雲端取回」合併新增項目。備份會取代該帳號的上一次雲端快照，操作前會提示。這不是即時多裝置同步；取回時已有項目以本機版本為準，不會用雲端覆蓋本機修改。單次雲端 JSON 上限約 850 KB，超過時可匯出 JSON 備份。

## 沒有 Mac：用 GitHub 產生 IPA

1. 將本資料夾內的所有內容放到一個專用的私人 GitHub 儲存庫根目錄。`.github/workflows/build-ipa.yml` 必須一起上傳。
2. 儲存庫 → Actions → **Build AllPlus IPA** → **Run workflow**。推送到 main 也會自動執行。
3. 流程會使用 GitHub 的 macOS 主機，安裝 XcodeGen、產生 Xcode 專案、配置 Google 回呼、執行測試，再編譯 iPhone 版本。
4. 全部成功後，下載 **AllPlus-iLoader** 成果壓縮檔，解壓取得 `AllPlus-unsigned.ipa`。
5. iPhone 連接電腦，開啟 iLoader，登入你的 Apple 帳號，選 Import IPA 匯入上述檔案，讓 iLoader 簽署並安裝。簽署有效期限由你的 Apple 帳號與 iLoader 決定。

若 Google 登入顯示 Bundle ID 或回呼不符，請先確認側載簽署後的 Bundle ID 是否仍與 Firebase 註冊的 `com.study.allplus` 相同。若簽署工具更改了 ID，需要在 Firebase 註冊相符的 iOS App、下載設定檔並重新編譯。

GitHub 私人儲存庫的 macOS 執行時間可能計入帳號用量，依你的方案為準。雲端工作流程沒有加入任何 Apple 帳號或憑證；Apple 登入由你在 iLoader 進行。

## 有 Mac 時

```sh
brew install xcodegen
xcodegen generate
python3 scripts/configure.py
open AllPlus.xcodeproj
```

在 Xcode 選 AllPlus scheme、iPhone 模擬器或實體裝置。真機直裝需設定自己的 Apple 開發團隊。雲端流程使用未簽署打包，由 iLoader 簽署。

## 驗證

本機可執行 `python scripts/check_project.py` 檢查 Firebase 設定、OAuth 回呼、資源與工作流程。本機已做 Swift 語法樹檢查，但這不等於 Xcode 型別檢查或編譯通過。

`AllPlusTests` 包含詞條解析、跨行中文、片語／句型邊界、參考字彙去重、括號省略、拼字正規化、選擇題唯一性、資料編碼往返，以及合成陰影影像測試。這些測試須在 GitHub macOS 工作流程執行後才有實際結果。

第一輪實機驗收應涵蓋：相機權限、兩欄／單欄照片、陰影預覽、中文與詞性校對、重新開啟保留資料、排序、各測驗模式、Google 登入、雲端備份與第二支手機取回。

## 官方資料

- [iLoader](https://github.com/nab138/iloader)
- [Firebase Apple 專案設定](https://firebase.google.com/docs/ios/setup)
- [Firebase Google 登入](https://firebase.google.com/docs/auth/ios/google-signin)
- [Apple Vision 文字辨識](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [Core Image Divide Blend](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/divideblendmode%28%29)
- [GitHub macOS 執行環境](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)

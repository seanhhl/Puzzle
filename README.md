# Light Sokoban (光影推箱子)

基於 **Godot 4.7.2 stable** 開發的網格回合制解謎遊戲，融合經典推箱子（Sokoban）與光影擴散、黑暗失能機制的益智遊戲。

---

## 一、開發環境與版本

- **遊戲引擎**：Godot Engine `4.7.2 stable`
- **專案模式**：2D (Grid-based, Canvas Items)
- **程式語言**：GDScript
- **主要設定**：
  - 網格單位尺寸（Tile Size）：`64 x 64 px`
  - 主啟動場景：`res://scenes/game/game_board.tscn`

---

## 二、專案開發核心準則

本專案在開發與擴充時需恪守以下原則：

> **實作與職責分離準則**：
> 1. **UI 編輯器優先（可讀性與合理性高）**：若新增功能或物品時，使用遊戲引擎內的 **UI 編輯器**（例如獨立場景 `.tscn` 結構、Sprite/ColorRect 外觀、Z-Index、Inspector 匯出屬性 `@export`、UI 容器排版等）明顯能提升專案可讀性與實作合理性，**必須直接告知開發者並在編輯器中操作**。
> 2. **腳本優先（資料與運算效率高）**：關卡地圖資料管理、碰撞演算法、光照泛洪運算、狀態連鎖收斂與歷史復原等核心系統，**一律使用 GDScript 腳本達成目的**。

---

## 三、目錄結構與資料架構

```text
res://
├── data/
│   ├── levels/                  # 獨立關卡檔案目錄（支援 .ldtk / .json，依檔名排序）
│   │   ├── level_01.json
│   │   ├── level_02.json
│   │   ├── level_03.json
│   │   └── level_04.json        # 連通箱子展示關
│   └── levels.txt               # [備用/相容] 純文字關卡檔
├── scenes/
│   ├── game/
│   │   └── game_board.tscn      # 遊戲主場景（相機、畫布容器、UI層）
│   └── objects/                 # 獨立物件模板（在 Godot 編輯器 UI 檢視與調整）
│       ├── player.tscn          # 玩家
│       ├── crate.tscn           # 箱子（支援剛體連通視覺）
│       ├── light_ball.tscn      # 光球
│       ├── wall.tscn            # 牆壁
│       ├── door.tscn            # 機關門
│       ├── button.tscn          # 地板按鈕
│       └── target.tscn          # 目標點
├── scripts/
│   ├── core/                    # 核心運算與系統管理
│   │   ├── ldtk_loader.gd       # 獨立關卡檔案掃描與 LDtk JSON 解析器
│   │   ├── level_loader.gd      # [相容] 解析 levels.txt
│   │   ├── light_system.gd      # 光線 BFS 漫延演算法
│   │   └── grid_manager.gd      # 網格物件註冊、廣義剛體推擠、Any-Lit 同步、Undo、勝負判定
│   ├── objects/                 # 物件行為與屬性
│   │   ├── grid_object.gd       # 所有網格物件基類
│   │   ├── player.gd
│   │   ├── crate.gd
│   │   ├── light_ball.gd
│   │   ├── wall.gd
│   │   ├── door.gd
│   │   ├── button.gd
│   │   └── target.gd
│   └── game/                    # 場景控制與繪製
│       ├── game_board.gd        # 輸入監聽、相機置中、UI更新
│       └── ground_view.gd       # 地面網格與光照動態繪製 (_draw)
├── prototype.txt                # 原始 PuzzleScript 原型設計檔
├── rule.txt                     # 核心規則說明文字檔
└── project.godot                # Godot 專案配置檔
```

---

## 四、核心機制與實現方案

### 1. 座標與分層體系 (Grid & Z-Index)
- **座標體系**：
  - 邏輯座標均採用整數網格向量 `Vector2i(x, y)`。
  - **正中央錨點制（Center Origin）**：物件根節點的世界座標對齊於格子正中心 `Vector2(grid_pos * 64) + Vector2(32, 32)`。所有 `.tscn` 視覺節點均以 `(0, 0)` 為中心對稱展開，完美相容 Godot 原生 `Sprite2D`（預設 centered=true）、旋轉（Rotation）、彈跳縮放（Squash & Stretch）與粒子特效。
- 物件分層（Z-Index）：
  - `Z = 0`：地面網格（`GroundView`，繪製暗地與光地）
  - `Z = 1`：目標點（`Target`）
  - `Z = 2`：按鈕（`GameButton`）
  - `Z = 5`：靜態牆壁（`Wall`）
  - `Z = 6`：機關門（`Door`）
  - `Z = 8`：箱子（`Crate`）
  - `Z = 9`：光球（`LightBall`）
  - `Z = 10`：玩家（`Player`）

### 2. 光照漫延演算法 (`LightSystem`)
- **漫延起點**：場上所有光球（`LightBall`）所在的格子。
- **擴散規則 (BFS)**：
  - 光線向四鄰格子連通漫延。
  - **邊界照亮規則**：光線能照亮阻擋物（牆壁、箱子）所在的格子，但**無法穿透**繼續延伸。
  - **門為透光物件**：門無論處於開啟或關閉狀態，皆**不會阻擋光線傳播**。
  - 空格、目標點、按鈕、玩家、門皆不會阻擋光線傳播。

### 3. 阻擋屬性與黑暗失能機制 (Blocking & Darkness)
- **阻擋屬性（最高宣告 `is_blocking`）**：
  - 由基類 `GridObject` 統一宣告 `@export var base_blocking: bool` 與動態 getter `is_blocking: bool`。
  - **牆壁（Wall）與關閉的門（Door）**：預設為 `true`（不可推動的阻擋障礙）。
  - **其他物件（Player, Crate, LightBall, Button, Target）**：預設為 `false`。
  - **黑暗失能**：若物件未被光照（`is_lit == false`），其 `is_blocking` 一律動態回傳 `false`（失去碰撞體積，可直接被穿透）。
- **黑暗中的物件行為**：
  - **玩家**：無法接受輸入與移動。
  - **箱子/牆壁/門**：失去阻擋與碰撞體積，玩家或其他被推動的物體可**直接穿透**該格。
  - **按鈕**：不參與門的開關邏輯計算。

### 4. 門與按鈕連鎖更新 (Door & Button Logic)
- 門具有 `color_id` 與預設狀態 `default_is_open`（預設為 false 關閉）。
- 按鈕具有 `color_id`。由受光的實體（玩家、受光箱子、光球）踩踏觸發。
- **開關邏輯**：
  - 若關卡中該顏色**沒有任何按鈕**：門維持預設狀態。
  - 若關卡中有該顏色的按鈕：檢驗**所有當前處於光線下的同色按鈕**；若皆被按下，門狀態反轉為開啟；若有任何一個受光按鈕未被按下，門維持預設關閉。
- **解耦與單次確定性計算**：
  - 由於門透光，開門或關門不會改變場景的光照傳播區域，徹底避免了「開門 -> 照亮新區域 -> 狀態改變 -> 關門 -> 黑暗」的循環依賴悖論。系統每一步只需單次線性更新即可確定所有狀態。

### 5. 連續推擠機制 (Multi-push) 與剛體連通箱 (Connected Crates)
- **連通箱子剛體叢集（CrateCluster）**：
  - 箱子可透過 LDtk 的 `connected_crates` 欄位拉線彼此相連，歸入同一剛體叢集。
  - **Any-Lit 光照同步**：連通群組中只要有任何一個箱子被光照亮，整組剛體所有箱子全部視為整體受光（皆為實體且可被推動）。
- **廣義剛體 Multi-push**：
  - 玩家推動連通群組中的任一箱子時，整組剛體所有成員沿推擠方向同步平移。
  - 若剛體的任一部件受到牆壁、關閉門或不可推動障礙阻擋，整組剛體皆無法移動。
  - 剛體前方若有其他獨立箱子、其他箱子叢集或光球，會自動形成連鎖推擠。
  - **暗處箱子**：失去實體碰撞，不加入推擠鏈，直接穿透過去。

### 6. 步步復原機制 (Undo System)
- 每次玩家成功移動前，`GridManager` 會將 `player`、`crates`、`light_balls` 的位置壓入 `history` 堆疊。
- 按下 `Z` 鍵即可彈出上一步歷史，並自動重新收斂光照與機關狀態。

---

## 五、關卡擴充指南（LDtk 與獨立檔案量產）

關卡檔案獨立存放在 `res://data/levels/` 目錄中（支援單獨 `.ldtk` 專案檔或 `.json` 關卡檔），載入器會自動依檔名進行自然排序（`level_01`, `level_02`...）。

### 1. LDtk 實體與欄位規範 (LDtk API)

| Entity Identifier | 建議尺寸 | 欄位 (Field) | 欄位型態 | 說明 |
| :--- | :---: | :--- | :--- | :--- |
| **`Player`** | 64x64 | 無 | - | 玩家起始位置（每關限 1 個） |
| **`Wall`** | 64x64 | 無 | - | 牆壁（阻擋移動與光線） |
| **`Crate`** | 64x64 | **`connected_crates`** | `Array<EntityRef>` | **箱子連通連線**：在 LDtk 選中箱子拉線至相鄰箱子，載入時自動組合為同一剛體 |
| **`LightBall`** | 64x64 | 無 | - | 光球（光源，可連推） |
| **`Door`** | 64x64 | **`color_id`**<br>**`default_is_open`** | `String`<br>`Boolean` | 機關門顏色識別碼（預設 `"red"`）與初始狀態 |
| **`Button`** | 64x64 | **`color_id`** | `String` | 地板按鈕顏色識別碼（預設 `"red"`） |
| **`Target`** | 64x64 | 無 | - | 獲勝目標點（推入受光的箱子即過關） |

### 2. 關卡名稱與描述
在 LDtk 點選 Level 設定屬性時，可在 Level 加上自訂欄位 **`level_name`**（String），例如 `"連動剛體｜相連的箱子會一同平移！"`，遊戲頂部標題將自動顯示該名稱。

---

## 六、新物件擴充指南

當專案需要新增全新物件（例如不同顏色的門鎖、傳送門、鏡子等）時，請遵守職責分工：

1. **在 Godot 編輯器 UI 中**：
   - 建立獨立場景 `res://scenes/objects/<new_object>.tscn`。
   - 設置根節點（繼承自 `Node2D`）、視覺節點（`Sprite2D` 或 `ColorRect`）、Z-Index 圖層。
   - 透過 Inspector 檢視與調整外觀顏色與 `@export` 變數。
2. **在腳本中**：
   - 建立 `res://scripts/objects/<new_object>.gd` 繼承 `GridObject`。
   - 在 `GridManager` 中註冊新的字元代碼、碰撞行為與光線阻擋判定。

---

## 七、遊戲操作鍵位

| 按鍵 | 功能 |
| :--- | :--- |
| **W / A / S / D** 或 **方向鍵** | 移動玩家 / 推動箱子與光球 |
| **Z** | 復原上一步 (Undo) |
| **R** | 重新開始當前關卡 (Restart) |
| **N** | 跳至下一關 (Next Level) |
| **P** | 返回上一關 (Previous Level) |


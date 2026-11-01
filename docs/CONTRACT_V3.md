# CONTRACT v1.3（v1.2 迭代：新立柱/卡牌、随机框、两阶段准备、局外行囊）

> 先读本文件；`docs/CONTRACT_V2.md` 的布局/场景/接口仍是基础，本文件只写本轮增量。
> 所有 `.gd` 用 Tab 缩进、UTF-8 无 BOM。不要越界改别人文件；接口变更先消息 `lead`。
> 新一轮目标：按 `基础策划案 (1).docx` 补齐核心玩法（黑/白立柱、分裂/质量/缩小卡、轨迹指示、⑥闭合），
> P1 立柱改为**错落**布局；每局底部框内容**随机**；进入房间先「上面购买道具 + 下面查看牌组」两步，
> 之后正式游玩不能再买；一局结束后部分弹珠/卡牌进入**局外行囊**（跨局公共变量），可在外面查看并勾选带入下一局。

## 1. 文件所有权

| 所有者 | 文件 |
|---|---|
| **Lead** | `project.godot`、`scripts/core/fate_config.gd`、`scripts/autoload/game_state.gd`、`docs/**`、集成/QA/构建 |
| **gameplay-dev** | `scenes/game.tscn`、`scenes/corridor.tscn`、`scripts/gameplay/**`、`scripts/corridor/**` |
| **ui-dev** | `scenes/ui/**`（hud/prep/result/meta_panel）、`scripts/ui/**`、`scenes/main_menu.tscn`、`assets/art/**`、`tools/gen_art.py` |
| **build-engineer** | `export_presets.cfg`、`build/**`、`tools/build_apk.ps1` |

## 2. 新增 GameState API（v1.2，Lead 已实现）

```gdscript
# 随机框内容（每局 prepare_level 随机生成，6 个）
GameState.slot_configs          # Array[{"mult":float,"bonus":""/"coin2"/"ball1"}]
GameState.get_slot_config(i) -> Dictionary
GameState.get_pocket_mult(i) -> float
GameState.get_pocket_bonus(i) -> String   # ""/"coin2"/"ball1"
GameState.apply_pocket_bonus(i) -> String  # 入框后调用：加金币 / 再射一球

# 弹珠槽新增 card 字段
GameState.take_next_ball() -> {"index","advanced","card"}   # card 为 "" 或卡牌 id
GameState.set_ball_card(index, card_id) -> bool   # 拖卡到灯：绑定卡牌，灯变红
GameState.get_ball_card(index) -> String
GameState.get_pending_items() / consume_pending_item(id)

# 底部特殊效果
GameState.grant_extra_ball()   # 再射一球

# 局外行囊（跨局公共变量，持久化在存档）
GameState.meta_balls_normal, meta_balls_advanced, meta_cards: Array[String]
GameState.selected_balls_normal, selected_balls_advanced, selected_cards
GameState.get_meta_card_stacks() -> Array[{"id","count"}]
GameState.toggle_selected_card(id) -> bool
GameState.select_meta_balls(advanced: bool, delta: int)
GameState.get_selected_ball_total() -> int
GameState.carry_over(victory) -> {"balls_normal","balls_advanced","cards"}  # finish_run/fail_room 已自动调用
# 结算 summary 里新增 summary["carried"]
```

- 带入下一局：`start_new_run()` 自动把勾选的弹珠加进弹珠库、卡牌放 `run_loadout_cards`（每关准备时出现在待用道具里，用掉后本局移除）。局外勾选上限：弹珠 3、卡牌 2（`FateConfig.META_MAX_SELECT_*`）。
- `prepare_level` 会在每关开头重新生成随机框、并刷新待用道具。

## 3. 立柱与效果（gameplay-dev）

- 5 种立柱，权重见 `FateConfig.PEG_WEIGHTS=[55,30,15,5,10]`（普通/黄/绿/黑/白），42 根，第 3 关无普通柱。
- **错落布局**：6 列 × 7 行，奇数行整体横移 `PEG_ROW_OFFSET_RATIO=0.5` 个列距（每层错开），加 ±3px 抖动；参考 P1 照片（顺时针转90°看）的错落排布。
- 效果：
  - 黄：每撞一次该球基础分 +1（`get_yellow_bonus`）。
  - 绿：相邻（横/竖/斜）绿柱之间生成**实际碰撞线段**（StaticBody2D + SegmentShape2D），弹珠撞线会被再次反弹；同时画辉光连线。
  - 黑：每撞一次该球最终得分 -1（用 `award_ball_score` 前把 base 减去 `black_hits*FateConfig.BLACK_PENALTY`，最低 0），撞时暗色闪光+「-1」。
  - 白：每撞一次，按 `0.20 + 0.10*(该柱本关已撞次数)` 概率 +1 金币；成功飘「+1金币」+ coin 音效；同一根柱的计数跨球累计、每关重置。
  - 装备改造柱（反射器/粘性器拖上去）：反射器反弹增强；粘性器把球黏住 `STICK_SECONDS≈0.9s` 后释放（球速度清零、显示粘滞效果）；质量卡球免疫粘性并可撞落被黏住的球。
- ⑥ 运动改变区：球进入台面（x<1216）后**关闭轨道缺口**（启用 GATE_RECT 处的 StaticBody2D），本次发射结束/下一球发射时再打开，防止球反弹回轨道。
- 发射指示：按住弹簧蓄力时，在 ⑥ 位置画**虚线轨迹预判**（沿轨道上行 + 出导流口后的抛物线/落点），松手消失；建议用 `_draw` 画点列。

## 4. 卡牌效果（gameplay-dev / game ball）

`take_next_ball().card` 为 ""/"powercard"/"splitcard"/"masscard"/"shrinkcard"：
- powercard：该球初速 ×1.3（0.9~1.0 蓄力也能到左路）。
- splitcard：撞到**第一根柱子**后分裂成 3 颗球（原球 + 2 颗带 ±40° 扩散、速度 ×0.8），每颗独立结算；只分裂一次。
- masscard：`physics_material.bounce≈0.28`、免疫粘性、撞到被黏住的球会把它撞落。
- shrinkcard：半径 ×0.8、发射速度 ×1.2。
- 有卡牌的球给红色光环/拖尾（与 buffed 一致），HUD 灯图标变红（ui-dev 负责显示卡名/红色）。

## 5. 两阶段进入 & UI（gameplay-dev + ui-dev）

房间流程：`PREP`（准备阶段）→ `PLAY`（正式游玩）→ 结算/回走廊。

- **gameplay-dev**：`_ready` 后建台面，phase=PREP：`hud.visible=false`；运行时 `load("res://scenes/ui/prep.tscn")` 实例化到 CanvasLayer(30)，调用 `prep.open_prep(GameState.level, offers)`，连接 `start_pressed`；收到后释放 prep、`hud.visible=true`、`hud.set_phase(1)`、phase=PLAY、解锁弹簧、`Audio.play_bgm("battle")`。PLAY 阶段**不再有商店**（HUD 的 shop 购买入口隐藏，`set_phase(1)` 已处理）。
- **ui-dev**：`scenes/ui/prep.tscn` + `scripts/ui/prep.gd`
  ```gdscript
  signal start_pressed
  func open_prep(level: int, offers: Array[String]) -> void
  ```
  布局：上半屏 = 商店（3 件货品卡：图标/名称/描述/价格/购买 → `GameState.buy_item`，显示金币、命运事件、关卡法则）；下半屏 = 「查看牌组」（当前 `GameState.get_pending_items()` 卡牌/装备、弹珠库 normal/advanced 数量、本关 5~6 颗弹珠槽概览与已绑卡牌）；右上 ❌/底部「开始试炼」→ emit `start_pressed`。风格沿用深靛+鎏金面板。
- **HUD（ui-dev）**：⑦ 道具区新增 3 张卡图标（splitcard/masscard/shrinkcard，需 gen_art 生成 `assets/art/icons/*.png`）；③ 弹珠灯显示 card 名字（小字或角标，红色）；其余保持 v1.1。`open_shop` 可保留但 PLAY 阶段不显示商店卡。
- **局外行囊（ui-dev）**：`scenes/ui/meta_panel.tscn` + `scripts/ui/meta_panel.gd`
  ```gdscript
  func open_panel() -> void
  signal closed
  ```
  全屏半透明面板：标题「行囊（局外）」；显示 `meta_balls_normal/advanced`、`get_meta_card_stacks()` 卡牌列表（图标+名称+数量）；点击卡牌 `toggle_selected_card`（选中金框，上限 2）；普通/进阶弹珠各一排 +/- 按钮 `select_meta_balls`（总数上限 3）；底部「确认带入下一局」→ closed。走廊里的「行囊」按钮由 gameplay 加：点击 load meta_panel 到 CanvasLayer、`open_panel()`，closed 后刷新走廊信息。
- **结算（ui-dev）**：`result.tscn` 的 `show_result(victory, summary)` 增加一行「带出局外」：`summary["carried"]` 的弹珠数与卡牌图标。
- **走廊（gameplay-dev）**：顶部信息加「行囊 N」小字 + 「行囊」按钮（打开 meta panel）；已通过/当前/封印逻辑不变。
- 新美术（ui-dev, gen_art.py 追加）：`icons/splitcard.png`、`icons/masscard.png`、`icons/shrinkcard.png`、`peg_black.png`、`peg_white.png`（48×48，透明底；gameplay 可加载、缺失则 _draw 降级）。`bg_corridor.png`/`door.png` 已有。

## 6. 音效

沿用：黑柱用 `crack`、白柱金币用 `coin`、分裂用 `crack`/`guardian`、黏住用 `guardian`、轨迹预判无音效、入框奖励 `coin`/`launch`。

## 7. 测试

```powershell
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --script 'res://scripts/gameplay/_syntax_check.gd'
```
- 整工程 import/导出由 Lead 统一做；不要起两个 Godot 实例。
- 完成或阻塞立即 `send_message` 给 `lead`。

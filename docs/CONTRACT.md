# 团队协作契约（文件所有权 / 接口 / 测试命令）

> 项目根目录：`G:\GoDot\？！珠珠！？`，Godot 4.6.3：`D:\Godot_v4.6.3-stable_win64.exe`
> 所有中文文本请使用 UTF-8（无 BOM）。所有 `.gd` 文件使用 Tab 缩进（Godot 约定），不要混用空格。

## 1. 文件所有权（不要越界写别人的文件）

| 所有者 | 文件/目录 |
|---|---|
| **Lead** | `project.godot`、`scripts/autoload/game_state.gd`、`scripts/core/fate_config.gd`、`docs/**`、`icon.svg`、最终集成与测试 |
| **gameplay-dev** | `scripts/gameplay/**`、`scenes/game.tscn`、`scripts/gameplay/**/*.gd`（含 ball/peg/slot/launcher/guardian/board/game 流程） |
| **ui-dev** | `scenes/main_menu.tscn`、`scenes/ui/**`、`scripts/ui/**`、`assets/art/**`、`assets/fonts/**`、`assets/ui/**`、`themes/**`、`tools/gen_art.py` |
| **audio-dev** | `scripts/autoload/audio.gd`、`assets/audio/**`、`tools/gen_audio.py` |
| **build-engineer** | `export_presets.cfg`、`build/**`、`tools/build_apk.ps1`、`G:\GoDot\_toolchain\**` 等工具链 |

Lead 会写 `project.godot` 并在其中注册 Autoload：`GameState`（`scripts/autoload/game_state.gd`）、`Audio`（`scripts/autoload/audio.gd`）。ui-dev 不得修改 autoload 注册；如需新增 Autoload 发消息给 Lead。

## 2. 启动流程 / 场景

`project.godot` 主场景：`res://scenes/main_menu.tscn`（ui-dev 提供）。

- 主菜单「开始试炼」→ `get_tree().change_scene_to_file("res://scenes/game.tscn")`
- 游戏场景 `res://scenes/game.tscn`（gameplay-dev 提供）负责：商店 → 发射 → 过关 → 下一关 → 结算 → 回标题。

## 3. GameState 公共 API（Lead 实现，直接调用）

```gdscript
# 只读状态
GameState.coins: int
GameState.level: int            # 1..3
GameState.level_score: int
GameState.total_score: int
GameState.balls_left: int
GameState.balls_total: int
GameState.library_balls: int
GameState.fate_event: Dictionary   # {"id","name","desc","bonus_ball"?,...}
GameState.best_score: int
GameState.total_shards: int
GameState.run_items: Dictionary    # item_id -> true

# 信号
coins_changed(value: int)
score_changed(level_score: int, total_score: int)
balls_changed(balls_left: int, balls_total: int)
level_started(level: int, target: int, fate_event: Dictionary)
level_cleared(level: int, level_score: int)
run_finished(victory: bool, total_score: int, shards: int, best: int)

# 流程
GameState.start_new_run()
GameState.prepare_level(lv: int)        # 重置本关数据 + 抽命运事件 + 应用事件效果，发 level_started
GameState.consume_ball() -> bool         # 消耗一枚：返回 false 表示没有弹珠了
GameState.consume_advanced_ball() -> bool # true 表示这发是进阶弹珠(基础分10)，否则普通(基础分5)
GameState.award_ball_score(base: int, yellow_hits: int, slot_mult: float) -> int
    # 内部计算 floor((base + yellow_hits*get_yellow_bonus()) * slot_mult * get_score_multiplier())
    # 累加 level_score/total_score，发 score_changed，返回本次得分
GameState.finish_level(victory: bool)   # 过关时 +5 金币、剩余球入库，发 level_cleared
GameState.finish_run(victory: bool) -> Dictionary
    # 计算碎片、更新最高分、存档、发 run_finished；返回 {"shards":int,"is_new_best":bool,"best":int}
GameState.has_item(id: String) -> bool
GameState.buy_item(id: String) -> bool  # 扣金币+登记道具；金币不足返回 false
GameState.get_target() -> int
GameState.get_score_multiplier() -> float
GameState.get_ball_base(advanced: bool) -> int
GameState.get_yellow_bonus() -> int
GameState.is_normal_pegs_removed() -> bool
GameState.reset_to_title()
```

`GameState.buy_item` 内部已处理金币与道具登记，ui-dev 商店直接调用即可；`gameplay-dev` 在游戏逻辑里读取 `has_item` 应用效果。

## 4. Audio 公共 API（audio-dev 实现，全部容错）

```gdscript
Audio.play_bgm(track: StringName)   # "menu" | "battle" | "shop" | "victory" | "defeat"
Audio.stop_bgm(fade := 0.6)
Audio.play_sfx(name: StringName, volume_offset_db := 0.0, pitch := 1.0)
    # "launch" "peg" "peg_yellow" "peg_green" "slot" "void" "coin" "buy" "click" "guardian" "crack" "win" "lose"
```
调用前无需判断资源是否存在，缺失时静默。

## 5. 场景接口（ui-dev 交付，gameplay-dev 实例化）

### 5.1 HUD — `res://scenes/ui/hud.tscn`（根节点 Control，`mouse_filter = MOUSE_FILTER_IGNORE`）
脚本 `res://scripts/ui/hud.gd`：
```gdscript
func refresh() -> void                       # 从 GameState 拉取全部数据显示
func set_phase_hint(text: String) -> void    # 顶部中央提示（如“按住蓄力，松手发射”）
func show_fate_event(event: Dictionary) -> void  # 命运事件横幅（可自动淡出）
func popup_score(value: int, world_pos: Vector2) -> void  # 飘分（world_pos 为屏幕坐标）
```
HUD 自带：目标分数/当前分数、金币、剩余弹珠灯（5 盏灯，每用一颗自左向右熄灭）、命运碎片、关卡名、返回按钮（发信号 `exit_pressed`）。
HUD 信号：`signal exit_pressed`。

### 5.2 商店 — `res://scenes/ui/shop.tscn`（根节点 Control，全屏，半透明遮罩）
脚本 `res://scripts/ui/shop.gd`：
```gdscript
func open_shop(level: int, offers: Array[String]) -> void  # offers 为道具 id 数组
signal shop_closed   # “启程”按钮
```
商店内部显示 3 件货品（名称/描述/价格/图标，从 `FateConfig.ITEMS` 读取），点击购买调用 `GameState.buy_item(id)`，金币不足置灰；购买后按钮变为「已购」。
`shop.gd` 还需提供静态辅助：`static func roll_offers() -> Array[String]`（从 `FateConfig.ITEMS` 随机 3 个，可由 gameplay 调用或内部调用）。

### 5.3 结算 — `res://scenes/ui/result.tscn`（根节点 Control，全屏）
脚本 `res://scripts/ui/result.gd`：
```gdscript
func show_result(victory: bool, summary: Dictionary) -> void
    # summary: {"total_score":int,"shards":int,"is_new_best":bool,"best":int,"level":int}
signal retry_pressed
signal menu_pressed
```

### 5.4 主菜单 — `res://scenes/main_menu.tscn`
按钮「开始试炼」→ `change_scene_to_file("res://scenes/game.tscn")`；显示 `GameState.best_score` / `GameState.total_shards`；播放 `Audio.play_bgm("menu")`。

## 6. 美术资源（ui-dev 产出，gameplay-dev 使用；缺失时 gameplay 必须有降级绘制）

`assets/art/`：
- `bg_menu.png` 1280×720 菜单背景
- `bg_board.png` 1280×720 弹珠台背景（可留空/半透明，玩法层绘制在它之上）
- `peg_normal.png` / `peg_yellow.png` / `peg_green.png` 48×48
- `ball_normal.png` / `ball_advanced.png` 48×48
- `guardian.png` 128×128
- `particle_dot.png` 16×16
- `icons/coin.png`、`icons/shard.png`、`icons/reflector.png`、`icons/sticky.png`、`icons/powercard.png`、`icons/gold_eye.png`、`icons/advanced_ball.png`（64×64）

字体：`assets/fonts/FateBody.ttf`（正文，复制 `C:\Windows\Fonts\simhei.ttf`）、`assets/fonts/FateTitle.ttf`（标题，复制 `C:\Windows\Fonts\simkai.ttf`）。
UI 主题：`assets/ui/fate_theme.tres`（ui-dev 建，Gameplay 不依赖）。

## 7. 音频资源（audio-dev 产出）

`assets/audio/bgm/bgm_menu.ogg`、`bgm_battle.ogg`、`bgm_shop.ogg`、`bgm_victory.ogg`、`bgm_defeat.ogg`（OGG Vorbis，44.1kHz，立体声，循环）。
若 OGG 编码器不可用，允许退化为 `.wav` 并在 Audio 中改路径 —— 但必须同步修改 `audio.gd` 与路径，并告知 Lead。
`assets/audio/sfx/sfx_*.wav` 单声道 44.1kHz，短音效，命名见 Audio.SFX_PATHS。

## 8. 坐标约定（玩法层，横屏 1280×720）

- 顶部 HUD 占 0–88px。
- 弹珠台内边界：左 48，右 1232，上 96，下（入槽线）616。
- 立柱区：`Rect2(300, 140, 820, 348)`，6 列 × 7 行。
- 槽位区：`Rect2(112, 616, 1056, 84)`，6 槽按权重分宽，倍率见 `FateConfig.SLOT_MULTIPLIERS`。
- 发射区：左下 `FateConfig.LAUNCH_POS = (96, 596)`，球以 -54° 向上发射，力度 620–1180 px/s。
- 守命者：y=566，在 x∈[260,1030] 往返巡逻，半径 30，撞球反弹。
- 球半径 14，重力 980×1.15，弹性 0.62。

## 9. 测试命令（串行使用，避免多个 Godot 同时写 `.godot` 缓存）

```powershell
# 单脚本语法检查（安全，可单独使用）
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --check-only --script 'res://scripts/gameplay/ball.gd'
# 全工程导入（Lead 统一执行）
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --import
# 无头跑 60 帧看报错（Lead 统一执行）
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --quit-after 60
```
如遇 `Failed to open .godot/...` 锁冲突，等 3 秒重试或先执行 `--import`。

## 10. 沟通

- 每个模块完成（或遇到接口问题）立即 `send_message` 给 `lead`，附：已完成文件清单、public 方法签名、测试方式、已知问题。
- 接口以本文档为准；需要变更接口先告知 Lead，由 Lead 更新本文档并广播。

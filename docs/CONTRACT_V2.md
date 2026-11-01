# CONTRACT v1.1（P1 布局 + 右侧弹簧弹珠 + 2D 走廊）— 只读契约，先读它再动手

> 项目根：`G:\GoDot\？！珠珠！？`；Godot：`D:\Godot_v4.6.3-stable_win64.exe`（4.6.3）。
> 上一版 `docs/CONTRACT.md` 仅作历史参考，**本文件优先**。
> 所有 `.gd` 用 Tab 缩进、UTF-8 无 BOM。不要修改别人负责的文件；接口变更先消息 `lead`。

## 0. 本轮目标（用户新需求）

1. 开始游戏后先进入 **2D 走廊**：虚拟摇杆控制角色左右移动，**每个房间 = 一个关卡**（3 间）。
2. 弹珠机改为 **千禧年街机弹珠机风格**：**右侧弹簧发射**，弹珠沿右侧轨道上行，顶部导流后从中间滚落。
3. 核心玩法 UI 严格按 **P1 布局（见 FateConfig 坐标）**：
   - ① 目标分数/当前分 ② 金币 ③ 可用弹珠（5 盏灯，拖动增益卡到灯上 → 该球图标变红）
   - ④ 右侧弹簧发射轨道 ⑤ 中央立柱阵 ⑥ ❌ 关闭道具选择界面
   - ⑦ 道具区（商店货品 + 已购装备/增益卡，长按拖动使用：装备→立柱，增益卡→弹珠灯）
   - ⑧ 弹珠库（剩余弹珠；三颗普通珠合成进阶珠；拖一颗到③的弹珠图标上完成替换）
4. 重新导出可安装 APK。

## 1. 文件所有权

| 所有者 | 文件 |
|---|---|
| **Lead** | `project.godot`、`scripts/core/fate_config.gd`、`scripts/autoload/game_state.gd`、`docs/**`、最终集成/QA/构建协调 |
| **gameplay-dev** | `scenes/game.tscn`、`scenes/corridor.tscn`、`scripts/gameplay/**`、`scripts/corridor/**` |
| **ui-dev** | `scenes/ui/**`、`scenes/main_menu.tscn`、`scripts/ui/**`、`assets/art/**`、`assets/fonts/**`、`assets/ui/**`、`tools/gen_art.py` |
| **audio-dev** | `scripts/autoload/audio.gd`、`assets/audio/**`（本轮基本不动，复用已有 BGM/SFX） |
| **build-engineer** | `export_presets.cfg`、`build/**`、`tools/build_apk.ps1` |

旧文件处理：`game.tscn` 由 gameplay-dev 重写（最小根节点 + game.gd 代码构建）；`hud/shop/result` 由 ui-dev 重写为 P1 版本（shop 合并进 HUD 的 ⑦ 区，不再单独全屏商店）；`scripts/gameplay/*_fallback.gd` 可删除或保留不用。

## 2. 场景与流程

```
main_menu → corridor.tscn（2D 走廊，摇杆移动，3 个房间门）
  → 走到当前房间门 → 触发：GameState.prepare_level(level) → change_scene game.tscn
game.tscn（P1 布局：⑦商店/道具 + ⑧弹珠库 + ⑤立柱阵 + ④弹簧 + ⑥❌）
  SHOP（❌ 关闭前可购买/拖拽道具）→ PLAY（5 颗弹珠，右侧弹簧发射，中央滚落，槽位结算）
  → 达标 → GameState.complete_room() → 非最后一间：回 corridor.tscn；最后一间：胜利结算面板（可回标题/再来一局）
  → 5 颗用完未达标 → GameState.fail_room() → 失败结算面板（「重试本关」= prepare_level(GameState.level) + 重载 game；「返回标题」）
```

- 主菜单「开始试炼」：`GameState.start_new_run()` → `change_scene_to_file("res://scenes/corridor.tscn")`。
- 走廊里 `GameState.level` = 当前应挑战的房间号（1..3）；房间 i<level 显示已通过，i>level 显示封印。

## 3. GameState 公共 API v1.1（Lead 已实现，直接调用）

```gdscript
# 状态（只读）
GameState.coins, level, level_score, total_score
GameState.balls_left, balls_total
GameState.ball_slots          # Array，每项 {"type":0普通/1进阶,"buffed":bool}
GameState.library_normal, library_advanced
GameState.pending_items       # 已购待使用道具 id（⑦区展示）
GameState.run_items           # 被动遗物 id -> true
GameState.fate_event, best_score, total_shards, run_active

# 信号
coins_changed(v)  score_changed(level_score, total)  balls_changed(left,total)
level_started(level, target, fate_event)  level_cleared(level, level_score)
library_changed(normal, advanced)  items_changed  run_finished(...)

# 流程
GameState.start_new_run()
GameState.prepare_level(lv)              # 进房间时调用：重置槽位/抽命运事件/清 pending
GameState.take_next_ball() -> Dictionary # {} 或 {"index","advanced","buffed"}，内部 balls_left-1
GameState.award_ball_score(base, yellow_hits, slot_mult, buffed) -> int
GameState.complete_room() -> Dictionary  # {"last":bool,"cleared":int,"next":int?, "summary":{...}?}
GameState.fail_room() -> Dictionary      # {"victory":false,"total_score":int,"shards":int,"best":int,"level":int}
GameState.finish_run(victory) -> Dictionary
GameState.get_target(), get_score_multiplier(), get_ball_base(advanced),
get_yellow_bonus(), is_normal_pegs_removed(), get_level_name(), get_level_buff_text()
GameState.get_ball_slot(i) -> Dictionary
# 商店/道具
GameState.buy_item(id) -> bool, can_buy_item(id) -> bool
GameState.get_pending_items() -> Array[String]
GameState.consume_pending_item(id) -> bool
GameState.buff_ball_slot(index) -> bool          # 增益卡生效，图标变红
GameState.replace_ball_slot(index, advanced) -> bool  # 弹珠库拖珠替换
GameState.merge_library_balls() -> bool          # 3 普通 → 1 进阶
```

## 4. P1 布局坐标（全部来自 `scripts/core/fate_config.gd`，不要硬编码）

| 区域 | 常量 | Rect |
|---|---|---|
| ① 目标分/当前分 | `HUD_CELL_SCORE` | (8,8,368,88) |
| ② 金币 | `HUD_CELL_COIN` | (392,8,392,88) |
| ③ 弹珠灯 | `HUD_CELL_BALL` | (800,8,472,88) |
| ⑦ 道具区 | `ITEM_AREA` | (8,112,624,344) |
| ⑧ 弹珠库 | `LIBRARY_AREA` | (8,464,624,248) |
| ⑥ ❌ | `CLOSE_RECT` | (1216,112,56,64) |
| ⑤ 立柱阵 | `PEG_AREA` | (664,176,528,384)，6×7 |
| ④ 发射轨道 | `RAIL_LEFT/RAIL_RIGHT/RAIL_TOP/RAIL_BOTTOM` | x 1216..1272，y 140..704；弹簧 `LAUNCH_POS=(1244,676)`；顶部导流斜面 `DEFLECTOR_A..B=(1216,140)-(1272,196)` |
| 槽位 | `SLOT_RECT` | (656,616,544,88)，6 格 `SLOT_MULTIPLIERS=[3,1.5,1,0,1,1.5]`（自左向右），虚空=索引3 |

物理：球半径 12、gravity_scale 1.0、bounce 0.62；发射速度 `LAUNCH_POWER_MIN..MAX = 1120..1600`（向上）；舞台左墙 x=640、顶 y=112、轨道左右墙 x=1216/1272。

## 5. HUD（ui-dev 交付 `scenes/ui/hud.tscn` + `scripts/ui/hud.gd`）

根 Control 全屏，`mouse_filter=IGNORE`，只有面板/按钮/可拖拽图标 STOP。

```gdscript
signal shop_closed            # ❌ 被点击
signal exit_pressed           # 返回标题
signal equip_requested(item_id: String, screen_pos: Vector2)  # 装备拖到台面/立柱区域

func set_game(game: Node) -> void      # gameplay 在实例化后调用，供拖拽落点判定（可选）
func refresh() -> void                 # 从 GameState 刷新三格/弹珠灯/⑦/⑧
func set_phase(phase: int) -> void     # 0=SHOP 1=PLAY 2=RESULT；SHOP 显示 ❌ 与商店货品
func open_shop(level: int, offers: Array[String]) -> void   # ⑦ 区展示 3 件货品
func set_phase_hint(text: String) -> void
func show_fate_event(event: Dictionary) -> void
func popup_score(value: int, world_pos: Vector2) -> void
func flash_error(text: String) -> void   # 金币不足/操作无效的提示
```

拖拽规则（在 HUD 内实现，触摸长按 0.25s 起拖，显示半透明拖影）：
- **装备类**（`FateConfig.ITEMS[id].kind=="equipment"`）拖到台面（screen_pos.x>640）：发 `equip_requested`，由 gameplay 判定落点立柱并应用；成功后 gameplay 调 `GameState.consume_pending_item(id)` + `hud.refresh()`。
- **增益卡**（kind=="card"）拖到 ③ 的弹珠灯上：`GameState.buff_ball_slot(lamp_index)` → 该灯图标变红；成功后 `consume_pending_item`。
- **弹珠库的球**（⑧区拖出一颗）拖到 ③ 的弹珠灯：`GameState.replace_ball_slot(lamp_index, advanced)`；无论普通/进阶，③上图标始终画普通弹珠（进阶球可在角上点一个小金点，但图标底色保持普通）。
- ⑧ 区：长按弹珠可选中（最多 3 颗普通珠，选中高亮），出现「合成」按钮 → `GameState.merge_library_balls()`。
- ⑦ 区商店：显示 `offers` 三件货品的卡片（图标/名称/价格/描述），点击购买 `GameState.buy_item(id)`，金币不足置灰 + `flash_error`；购买后按钮变「已购/已获得」。已购待使用道具以图标形式排在同一区域（带数量角标）。
- ③ 灯：数量 = `GameState.balls_total`，按 `ball_slots[i]` 显示：未用=亮、已用=灭、buffed=红色、进阶=金色描边（图标仍普通弹珠）。灯与槽位索引一一对应。

## 6. gameplay（gameplay-dev 交付）

### 6.1 `scenes/game.tscn` + `scripts/gameplay/game.gd`
- 根 Node2D；`_ready`：建 Camera2D、fx、`board`（含台面/立柱/槽位/轨道/守命者）、`launcher`（右侧弹簧）、HUD（运行时 `load("res://scenes/ui/hud.tscn")`，缺失时才用兜底）；`Audio.play_bgm("battle")`；`phase=SHOP`：`hud.open_shop(GameState.level, offers)` + `hud.show_fate_event(GameState.fate_event)`；❌ → `phase=PLAY`，`hud.set_phase(1)`。
- 发射：玩家按住右下弹簧（LAUNCH_POS 附近，半径约 90）蓄力（CHARGE_TIME 蓄满，显示力度条），松手 `GameState.take_next_ball()` → 生成 ball（advanced/buffed 取自返回值），初速向上 `lerp(POWER_MIN,POWER_MAX,t)`，球沿轨道上升、撞击顶部导流斜面后向左进入立柱阵。球在场时不能再发射。
- 入槽：`GameState.award_ball_score(base, yellow_hits, slot_mult, buffed)`，HUD 飘分 + 音效/粒子；销毁球；`balls_left==0` 或 `level_score>=target` 时判定（达标立即过关）。
- 过关：`var r := GameState.complete_room()`；`r.last==true` → 胜利结算面板；否则 `change_scene_to_file("res://scenes/corridor.tscn")`。
- 失败：`GameState.fail_room()` → 失败结算面板（重试本关 / 返回标题）。
- 装备落点：`func _on_equip_requested(item_id, screen_pos)`：屏幕→世界坐标（camera 或无 camera 时直接用），`board.equip_at(world_pos, item_id)` 成功则 `GameState.consume_pending_item` + `hud.refresh()` + 音效。
- 右侧弹簧、弹珠台背景、轨道等全部程序化绘制（`_draw`），美术资源缺失可降级。

### 6.2 `scripts/gameplay/board.gd`
- `setup(fx)`（add_child 前）、`build(level)`、`clear_board()`。
- 台面：左墙 x=640（y 112..704）、顶部 y=112（x 640..1216）、右侧轨道墙 x=1216（y 250..704）+ x=1272（y 196..704）+ 顶部导流斜面段；轨道顶部与台面之间的缺口 y≈140..250 让球进入台面。
- 立柱：6×7 = 42（`PEG_AREA`，±5px 抖动，权重 55/30/15，第 3 关无普通柱），黄色每撞 +1 基础分，绿色额外回弹 + 邻接连线辉光。
- 槽位：6 个 Area2D（`SLOT_RECT` 按权重分宽），metadata 倍率/索引；球进入 → `slot_hit` 信号。
- 守命者：机器人/命运之眼，在 y=556、x∈[700,1150] 往返，撞球弹开。
- `func equip_at(world_pos: Vector2, item_id: String) -> bool`：找最近立柱（半径 40 内）应用装备：reflector→该柱反弹增强（视觉金色描边）；sticky→该柱黏滞（视觉幽绿描边）；球撞到这些柱时相应弹跳/减速。返回是否成功。
- 绘制：台面背景（可用 `assets/art/bg_board.png`，存在则贴、缺失则渐变+星尘）、轨道、弹簧、立柱、槽位、绿色连线、导流斜面。

### 6.3 `scripts/gameplay/ball.gd`
- RigidBody2D，r=12，CCD，contact_monitor；`advanced`、`buffed`、`yellow_hits`、`settled`；拖尾；撞柱信号；出界（y>760 / 超时 14s）判虚空（0 分）。撞黄柱 +1、绿柱额外回弹；被装备改造的柱按效果处理。
- 球在轨道内时（x>1216）不受立柱影响；到达台面后正常物理。

### 6.4 `scenes/corridor.tscn` + `scripts/corridor/corridor.gd`
- 2D 横版走廊：`FateConfig.CORRIDOR_LENGTH=4200`，地面 `CORRIDOR_FLOOR_Y=566`；Camera2D 跟随玩家。
- 玩家：小角色（程序化绘制，命运琉璃光点 + 斗篷剪影均可），受 **虚拟摇杆**（左下 `JOYSTICK_CENTER`/`RADIUS`，触摸拖动，桌面 A/D/←→ 也可）控制左右移动，`CORRIDOR_PLAYER_SPEED=430`，限制在 0..CORRIDOR_LENGTH。
- 3 个房间门在 `CORRIDOR_DOOR_X`（1100/2300/3500）：当前房间门发光、显示「第X间 · 关卡名」，已通过门变暗/开门，未解锁门封印（锁链/暗色）。玩家走到当前门范围（|x-door_x|<90）显示「进入试炼」按钮；点击 → `GameState.prepare_level(GameState.level)` + `change_scene_to_file("res://scenes/game.tscn")`。
- 顶部信息：房间进度（第X/3间）、金币、命运碎片、操作提示；背景 `assets/art/bg_corridor.png`（2560×720，存在则平铺/滚动，缺失则渐变走廊+柱子绘制）。
- BGM：`Audio.play_bgm("menu")`；进门 `Audio.play_sfx("click")`。

## 7. UI 资源（ui-dev 追加）

- `assets/art/bg_corridor.png` 2560×720（横版走廊背景，可无缝左右平铺；命运神殿长廊、拱门、地砖、幽光）
- `assets/art/door.png` 200×320（门洞，透明底；可被 tint 成已开/封印）
- 复用现有 `assets/art/icons/*.png` 作为道具图标；③ 灯可用 `ball_normal.png` 缩放绘制。
- 主题仍用 `FateUI.build_theme()`（`scripts/ui/ui_theme.gd`），深靛+鎏金+幽绿+紫。

## 8. 音频

沿用已交付资源：`Audio.play_bgm("menu"/"battle"/"shop"/"victory"/"defeat")`、`Audio.play_sfx("launch"/"peg"/"peg_yellow"/"peg_green"/"slot"/"void"/"coin"/"buy"/"click"/"guardian"/"crack"/"win"/"lose")`。走廊用 `menu`，房间战斗用 `battle`。

## 9. 测试

```powershell
# 真实环境编译检查（Autoload 已注册，--check-only 会误报 GameState，不要用）
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --script 'res://scripts/gameplay/_syntax_check.gd'
# 场景启动（Lead 统一跑）
& 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' --quit-after 120
```
- 不要同时跑两个 Godot 实例；整工程 import/导出由 Lead 统一做。
- 交付前各自检查：脚本编译无错、场景可实例化、触摸/鼠标事件路径可用。

## 10. 沟通

完成或阻塞立即 `send_message` 给 `lead`：文件清单、接口实现情况、自测结果、已知问题。需要改接口先问 Lead。

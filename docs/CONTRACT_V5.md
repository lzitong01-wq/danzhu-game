# CONTRACT v1.5（v1.4 迭代：10 关 / 命核碎片 / 角色动画 / 存档续关 / 启动页 / 教程大厅）

> 先读本文件；`docs/CONTRACT_V4.md` 为基础。所有 `.gd` Tab 缩进、UTF-8 无 BOM。
> 本轮用户 7 条需求：
> 1. 主角换成 P1「持星辉法球的流浪占星师」形象，并且行走/待机要有流畅动画，不是生硬位移；
> 2. 按《基础策划案 (2).docx》修改游戏内容；3. 修 BUG：最右端立柱与发射边界太紧 → 卡球；
> 4. 给游戏增添「腾讯感」（启动页/健康忠告/平台化主菜单）；5. 修 BUG：手机玩完一关退出重开会重来/退回上一关（要能续关）；
> 6. 初始界面单开「新手教程」，循序渐进教核心关卡各区域名词；7. 绿色连线不要随机乱连，要有可玩性。

## 1. 所有权（v1.4 起 main_menu/splash/tutorial_hall 归 frontend-dev）

| 所有者 | 文件 |
|---|---|
| Lead | `project.godot`、`scripts/core/fate_config.gd`、`scripts/autoload/game_state.gd`、`docs/**`、集成/QA/构建 |
| gameplay-dev | `scenes/game.tscn`、`scenes/corridor.tscn`、`scripts/gameplay/**`、`scripts/corridor/**` |
| ui-dev | `scenes/ui/hud|prep|meta_panel|result|tutorial.tscn`、`scripts/ui/{hud,prep,meta_panel,result,tutorial}.gd`、`assets/art/**`（除新增 splash/menu/hall 插画）、`tools/gen_art.py` |
| frontend-dev（新） | `scenes/splash.tscn`、`scenes/tutorial_hall.tscn`、`scenes/main_menu.tscn`、`scripts/ui/splash.gd`、`scripts/ui/tutorial_hall.gd`、`scripts/ui/main_menu.gd`、`assets/art/splash_*`、`assets/art/menu_*`、`assets/art/hall_*`、`tools/gen_art_front.py` |
| audio-dev | `assets/audio/**`、`scripts/autoload/audio.gd`、`tools/gen_audio.py`（本轮可不改） |
| build-engineer | `export_presets.cfg`、`build/**`、`tools/build_apk.ps1` |

## 2. Lead 已完成（v1.4 数据层）

- `FateConfig`：10 关 `LEVEL_NAMES/TARGETS/LEVEL_BUFFS`（buff 字典含 base_bonus/bounce_bonus/chaos_chance/white_bonus/green_limit/green_weight_bonus/price7_weight_bonus/gravity_bonus/break_threshold/break_seconds/score_mult/remove_normal/remove_negative）、三种琉璃珠 `BALL_BASE_SCORES=[5,10,20]`、合成概率常量、道具权重表（12 件，含新装备：歧路回廊帖/归命拾珠囊/命运纺锤钉/穿命透障凿、命运的赠与/奖赏）、刷新费用、`PEG_AREA=(648,168,528,424)` 与 `PEG_RIGHT_GAP=40`（修复右端卡球）、绿色连线规则（仅横/竖、每柱≤2 条）、走廊 10 门/NPC 偏移/关卡文案、启动页健康忠告文案、角色动画 sprite 路径与帧数、腾讯式文案。
- `GameState`：
  ```gdscript
  # 三种弹珠
  GameState.ball_slots[i] = {"type":0/1/2,"card":""}
  GameState.take_next_ball() -> {"index","type","advanced","card"}
  GameState.get_ball_base(type) -> int   # 已含关卡 base_bonus
  GameState.library_normal/advanced/high
  GameState.synthesize_core() -> {"ok","type"}   # 3普通→1进阶 60%，失败返还3普通，每关一次
  GameState.synthesize_source() -> {"ok","type"} # 3进阶→1高阶 40%，失败返还2进阶，每关一次
  GameState.synth_used: bool
  GameState.replace_ball_slot_type(index, type) -> bool
  # 商店
  GameState.roll_shop_offers() -> Array[String]   # 权重制（守命低语 buff 已生效）
  GameState.get_refresh_cost() -> int; GameState.refresh_shop_offers() -> Array
  GameState.buy_item(id)  # instant 类会自动加弹珠；名称/描述见 FateConfig.ITEMS
  # 关卡 buff
  GameState.get_level_buff() -> Dictionary
  GameState.get_target(), get_score_multiplier(), get_yellow_bonus(),
  get_bounce_bonus(), get_chaos_chance(), white_coin_amount(), get_green_limit(),
  get_green_weight_bonus(), get_gravity_mult(), get_break_threshold(), get_break_seconds(),
  is_normal_pegs_removed(), is_negative_pegs_removed()
  GameState.level_coins_gained:int   # 本关收集的命核碎片（万流归宗触发条件）
  GameState.get_story_line() -> String
  # 存档/续关（注意：save_game 已包含进行中的一局）
  GameState.has_resumable_run() -> bool
  GameState.resume_run()
  GameState.abandon_run()
  GameState.save_game()   # 需要在暂停/关闭/关卡切换/购买后调用
  ```
- 用户提供的角色原图已放到 `assets/art/ref_astrologer.png`（1254×1254 透明背景），供 ui-dev 参考与菜单立绘使用。

## 3. gameplay-dev（task-11）

1. **右端卡球修复（最高优先）**：立柱中心 x ≤ `RAIL_LEFT - PEG_RIGHT_GAP`；`PEG_AREA` 已改；验证最右列与轨道墙间距 ≥40px、球能正常下落；卡球救援逻辑保留。
2. **绿线可玩性**：只允许 `GREEN_LINK_ALLOWED_OFFSETS`（横/竖）相邻连线，每颗绿柱最多 2 条；生成时先选“连线组”（如 2~3 组，每组 2~4 颗成行/成列），其余绿柱不连线；保证不会出现杂乱蛛网状。
3. **10 关**：`MAX_LEVEL=10`；走廊 10 扇门/NPC；每关目标/buff 从 GameState 读取。实现所有关卡 buff 效果：
   - 命运微光（base_bonus 已由 `get_ball_base` 处理）；回廊之风（球物理反弹速度 +10%）；因果回响（撞柱后 30% 概率随机改变方向）；命核共鸣（白柱命中额外 +1 命核碎片，使用 `white_coin_amount()` 已含）；裂隙侵蚀（球撞绿柱/绿线累计 3 次自毁；绿柱权重 +20）；守命低语（商店权重由 `roll_shop_offers` 处理，prep UI 负责）；命运重压（球 gravity_scale ×1.15）；万流归宗（`level_coins_gained >= threshold` 时 10 秒破命状态：本关弹珠不可摧毁 + 得分翻倍）；倒戈止逆（`get_score_multiplier()` 已处理）；命源再现（删除普通与黑色立柱，只留黄/白/绿）。
4. **三种弹珠**：按 `take_next_ball().type` 设置 base/外观（命源珠金色+更大光环）；分裂副球继承类型；结算 `GameState.award_ball_score(GameState.get_ball_base(type), ...)`。
5. **合成**：⑧ 区合成按钮（ui-dev）会调 `synthesize_core/source`；gameplay 不用改，但需保证 UI 未就绪时兜底可用。
6. **走廊**：10 门/NPC；NPC 与玩家同形象（用 ui-dev 的 sprite，缩放/变色区分）；玩家在 NPC 附近**停留 1 秒** → 屏幕下方弹出该关文案（`GameState.get_story_line()`，淡入停留 3.5s 再淡出）；只有当前关 NPC 可用。走廊长度/门坐标用 FateConfig。
7. **主角动画**：`scripts/corridor/player.gd` 改 Sprite2D 动画：walk（6 帧，`PLAYER_WALK_SPRITE`，移动时播放，随速度调整 fps 8~12）、idle（4 帧，`PLAYER_IDLE_SPRITE`，静止呼吸），`flip_h` 控制朝向；平滑移动用 acceleration/friction（不是瞬移），并加轻微上下浮动/落地灰尘粒子让动作不僵硬。
8. **续关/存档**：game.tscn / corridor / prep 在以下时机调 `GameState.save_game()`：房间进入（prepare 已保存）、购买后（GameState 已保存）、关卡完成（complete_room 已保存）、`NOTIFICATION_WM_CLOSE_REQUEST` / `NOTIFICATION_APPLICATION_PAUSED`、`_notification` 退到后台；返回标题不结束本局（保留 run_active）。主菜单/走廊按 `has_resumable_run()` 显示续关。
9. 过关结算：level 10 通关 → 胜利；失败 result 传 `summary`（含 `story` 失败文案）由 ui 显示。

## 4. ui-dev（task-12）

1. **角色精灵图（最高优先）**：按 `assets/art/ref_astrologer.png` 的像素流浪占星师形象，生成
   - `assets/art/player_walk.png`：6 帧横向 sprite sheet，每帧 64×80（透明底），走路循环（腿交替、斗篷摆动、手中星辉法球上下浮动、身体 bob）；
   - `assets/art/player_idle.png`：4 帧 64×80，待机呼吸/法球微光脉动；
   - 颜色/气质参考原图（灰棕斗篷、琉璃碎片饰边、淡蓝紫发光法球、棕色靴子），保持像素风；NEAREST。
2. **商店/道具适配《策划案(2)》**：prep 商店用 `GameState.roll_shop_offers()`；新增「刷新（消耗 N 命核碎片）」按钮 → `GameState.refresh_shop_offers()`，费用随刷新次数 +1 并显示；币种名称统一「命核碎片」；道具名称/描述/价格读 `FateConfig.ITEMS`（12 件，含 4 件新装备与 2 件 instant）。
3. **⑧ 弹珠库合成**：显示三种琉璃珠数量；按钮「合成命核（3普通 60%）」「合成命源（3进阶 40%）」→ `GameState.synthesize_core/source()`，用 toast 显示成功/失败（失败返还文案），`synth_used` 后按钮置灰；合成结果图标/数量刷新。
4. **HUD ③ 弹珠灯**：支持 type 0/1/2 外观（普通/进阶/命源），卡牌名红色；⑦ 待使用道具详情用新名称与描述。
5. **结算面板**：失败时显示 `summary.story`（策划案 11 条失败固定文案）与「重试本关/返回标题」；胜利显示 10 关通关文本；「带出局外」保留。
6. **行囊面板**：显示三种琉璃珠（含命源）与卡牌。
7. 保留 v1.3 像素风、双倍注对话框、卡牌详情、游戏内拖动引导。

## 5. frontend-dev（task-13，新）

1. **启动页 `scenes/splash.tscn`**（腾讯感，但不使用任何真实商标）：
   - 黑底 → 像素「琉璃回廊工作室 / 命运互动」 logo 以平行四边形色块+金色描边淡入（参考平台发行 logo 排版）；
   - 下方进度条加载动画 + `FateConfig.LOADING_TIPS` 轮播小提示；
   - 首次启动显示一页「健康游戏忠告」（`HEALTH_TIPS` 4 条）+ `AGE_TIP` 适龄提示 + 底部小字（版号/隐私/用户协议占位），点「开始」进入主菜单；之后启动直接进主菜单（可跳过忠告，用 SaveData 或 GameState.tutorial_seen? 用本地 flag）。
   - `Audio.play_bgm("menu")` 或静音均可；按钮音效 click。
2. **主菜单重做**（`scenes/main_menu.tscn` + `scripts/ui/main_menu.gd`）：
   - 标题 `FateConfig.GAME_TITLE`「！？珠珠？！」，像素/平台风排版；
   - 按钮：`继续试炼`（`GameState.has_resumable_run()` 时显示，显示「第X间 · 关卡名」）、`开始新试炼`、`新手教程`、`设置`（音量/震动占位弹窗）；
   - 右上角平台风小按钮（音效/客服/隐私占位），底部健康忠告入口、适龄提示、版本号 v1.4.0；
   - 腾讯式版式：主按钮大圆角/斜角高亮、左侧公告栏（滚动文案「命运回廊赛季开启」等）、右下「进入游戏」大按钮。
3. **新手教程大厅 `scenes/tutorial_hall.tscn` + `scripts/ui/tutorial_hall.gd`**（需求 6）：
   - 从主菜单「新手教程」进入；用 FateConfig 的 P1 区域矩形画出示意图（①-⑧ 区域用像素框+编号），**循序渐进**分页：
     1 目标分① / 2 命核碎片② / 3 弹珠灯③ / 4 弹簧发射④+轨迹 / 5 立柱阵⑤（5 种立柱说明）/ 6 运动改变区⑥（发射后闭合）/ 7 道具区⑦（长按拖动）/ 8 弹珠库⑧（合成/替换）/ 9 走廊与行囊 / 10 开始试炼；
   - 每页高亮对应区域（其余变暗），显示区域名词+一句说明；底部「上一页/下一页/跳过教程」，最后一页「进入试炼」→ `change_scene_to_file("res://scenes/corridor.tscn")`（`GameState.start_new_run()`）。
   - 像素风，可复用 `scripts/ui/ui_theme.gd`（只读调用 `FateUI`）。
4. 启动页/主菜单/教程大厅新增插画（`assets/art/splash_*.png`、`menu_*.png`、`hall_*.png`）用 `tools/gen_art_front.py` 生成（像素风、低分辨率 NEAREST 放大、路径自定但稳定）。
5. 所有入口：主菜单「开始新试炼」→ `GameState.start_new_run()` + `change_scene_to_file("res://scenes/corridor.tscn")`；「继续试炼」→ `GameState.resume_run()` + corridor。
6. 完成后 Lead 会把 `project.godot` 主场景改为 `res://scenes/splash.tscn`（你先保证 splash 能跳 main_menu）。

## 6. 验收

- 各脚本 `--check-only` / `_syntax_check.gd` failed=0。
- Lead 窗口截图：启动页/健康忠告、主菜单（含继续）、教程大厅分页、走廊 NPC 文案、角色行走动画帧、10 关 PREP（刷新/合成）、右端卡球修复、结算失败文案；APK 重建 + badging/apksigner。

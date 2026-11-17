# CONTRACT v1.6（v1.5 迭代：去腾讯化/简洁独游菜单/走廊NPC黑屏白字/角色行囊面板/等级/图标）

> 本轮用户 9 条：
> 1. 去掉腾讯味，回到之前独游简洁风格；2. 走廊碰到同形象 NPC → 黑屏白字文案，NPC 淡出消失；
> 3. 走廊左上角回主菜单按钮，右上角行囊改弹珠图标；4. 点图标 → 左半主角立绘、右半行囊物品，右框顶目录（角色信息/弹珠/卡牌）；
> 5. 角色可升级（暂无等级效果）；6. 主菜单五项：「继续未尽之命运」「起新途之命运」「设置」「关于我们」「退出」；
> 7. 菜单背景虚化星空 + 右侧无脸主角；8. 三种弹珠图标按描述；9. 游戏图标：主体命核琉璃珠 + 右侧露出主角侧脸一点。

## 1. 所有权

| 所有者 | 文件 |
|---|---|
| Lead | `project.godot`、`scripts/core/fate_config.gd`、`scripts/autoload/game_state.gd`、`docs/**`、集成/QA/构建、`icon.png` |
| frontend-dev | `scenes/main_menu.tscn`、`scripts/ui/main_menu.gd`、`scenes/splash.tscn`/`splash.gd`（可留作极简备用）、`assets/art/menu_*`、`assets/art/splash_*`、`tools/gen_art_front.py` |
| ui-dev | `scenes/ui/character_panel.tscn` + `scripts/ui/character_panel.gd`（新，替代 meta_panel 的使用）、`assets/art/ball_normal|ball_advanced|ball_source.png`、`assets/art/app_icon.png`、`tools/gen_art.py`、其余 ui 文件 |
| gameplay-dev | `scenes/corridor.tscn`、`scripts/corridor/**`（NPC 黑屏白字/按钮/面板入口）、`scripts/gameplay/**`（等级经验提示可选） |
| audio-dev | 不动（沿用 8bit） |

## 2. Lead 已完成（数据层 v1.5）

- `FateConfig` 新增：`EXP_PER_ROOM_CLEAR=40`、`EXP_BASE_REQUIRED=100`、`EXP_GROWTH=60`、主菜单文案 `MENU_CONTINUE/MENU_NEW/MENU_SETTINGS/MENU_ABOUT/MENU_QUIT`、`ABOUT_TEXT`、`PANEL_TABS=["角色信息","弹珠","卡牌"]`。
- `GameState` 新增：
  ```gdscript
  GameState.character_level:int / character_exp:int
  GameState.exp_needed() -> int
  GameState.add_character_exp(n)          # 过关自动 +40（complete_room 已调用）
  GameState.character_changed(level, exp, needed)  # 信号
  GameState.npc_seen_levels:Array
  GameState.is_npc_seen(level) -> bool
  GameState.mark_npc_seen(level)          # 会 save
  ```
  存档已含等级/经验/npc_seen；新开一局清空 npc_seen（等级跨局保留）。
- 主场景由 Lead 改回 `res://scenes/main_menu.tscn`（不再经过 splash；splash 可留作备用或被忽略）。

## 3. frontend-dev（task-14）

1. **去掉腾讯味，回到独游简洁风**：主菜单删除公告栏、右上客服/隐私/音效圆钮、底部健康忠告/适龄/版号、右下「进入游戏」大按钮等平台化元素；保留像素简洁排版（标题 + 5 个按钮 + 少量装饰）。
2. **背景与人物**：菜单背景为**虚化星空**（可用现有星空图做高斯模糊/预生成 `menu_bg_blur.png` 1280×720，暗色调）；**右侧是无脸主角**（深色剪影/无脸的占星师，参考角色图，生成 `menu_hero_faceless.png`，约 560×720，右对齐，像素风，可配合轻微呼吸浮动/星尘粒子）。
3. **五项菜单**（文案严格用 `FateConfig.MENU_*`）：
   - `继续未尽之命运`：`GameState.has_resumable_run()` 时可用并显示「第X间·关卡名」；无存档则置灰；
   - `起新途之命运`：`start_new_run()` + corridor；
   - `设置`：音乐/音效音量弹窗（复用现有）；
   - `关于我们`：弹窗显示 `FateConfig.ABOUT_TEXT`；
   - `退出`：`GameState.save_game()` 后 `get_tree().quit()`。
   标题 `FateConfig.GAME_TITLE`「！？珠珠？！」+ 副标题；保留 `继续/新游戏` 跳转 corridor、`Audio.play_bgm("menu")`。
4. 启动页：不再作为默认入口（Lead 已把主场景改回 main_menu）；可把 splash 简化为极简 logo（不显示健康忠告/平台 logo），不强制使用。
5. `tools/gen_art_front.py` 追加菜单所需图片（虚化星空、无脸主角），像素风可复现。

## 4. gameplay-dev（task-15）

1. **NPC 触碰剧情**：走廊里当前关 NPC 与玩家距离 <70px 时触发一次：
   - 全屏黑幕淡入（0.35s）→ 居中白字显示 `GameState.get_story_line()`（可多行/逐字）→ 停留 3.2s → 黑幕淡出（0.6s）；
   - 同时 NPC 淡出（modulate alpha→0，0.5s）并隐藏；`GameState.mark_npc_seen(GameState.level)`；该 NPC 之后不再出现（`is_npc_seen`）。
   - 播放期间玩家输入冻结；触发一次即可。
2. **走廊左上角按钮**：像素「主菜单」按钮（含返回箭头），点击 `GameState.save_game()` → `change_scene_to_file("res://scenes/main_menu.tscn")`；保留顶部信息。
3. **右上角弹珠图标**：删除原「行囊」文字按钮/数量，改为**弹珠样式图标按钮**（用 `assets/art/ball_advanced.png` 或命核珠贴图，48×48 像素，带微光），点击运行时加载 `res://scenes/ui/character_panel.tscn`、`open_panel()`，连接 `closed` 后刷新；缺失时用 meta_fallback。
4. 玩家等级：走廊顶部信息可显示「Lv.X」（读 `GameState.character_level`）；`GameState.mark_npc_seen` 已保存，走廊启动时隐藏已触发 NPC。
5. 主菜单/教程大厅跳转不变；不要动 `scenes/main_menu.*`（frontend 所有）。

## 5. ui-dev（task-16）

1. **角色/行囊面板**（新）：`scenes/ui/character_panel.tscn` + `scripts/ui/character_panel.gd`
   ```gdscript
   signal closed
   func open_panel() -> void
   ```
   全屏半透明像素面板（深靛+鎏金，简洁独游风，不要平台浮夸）：
   - **左半**：主角立绘（用 `assets/art/ref_astrologer.png` 或基于其生成的像素立绘 `player_portrait.png`，占面板左 45%，底部显示「Lv.X / 经验 40/100」与进度条、主角名「持星辉法球的流浪占星师」）。
   - **右半**：顶部目录（tabs）用 `FateConfig.PANEL_TABS`：`角色信息` / `弹珠` / `卡牌`；
     - 角色信息：等级/经验条（`character_level/exp/exp_needed`）、命运碎片、最高分、本局进度（第X/10间）、已通关局数；
     - 弹珠：三种琉璃珠拥有数量（meta_balls_normal/advanced，命源显示折算说明），可 ± 勾选带入下一局（沿用 `select_meta_balls`，上限 3）；
     - 卡牌：`get_meta_card_stacks()` 图标+名称+数量，点击 `toggle_selected_card`（金框，上限 2）。
   - 右下「确认 / 关闭」→ `closed`；打开时 `open_panel()` 刷新（监听 meta_changed/character_changed）。
2. **三种弹珠图标**按描述重绘（16×16→48/64）：
   - `ball_normal.png`：透明偏白圆形（命运琉璃珠）；
   - `ball_advanced.png`：更凝练的白 + 金色荧光（命核琉璃珠）；
   - `ball_source.png`：金色（命源琉璃珠）。
   同步 HUD ③ 灯/行囊/走廊图标显示正确。
3. **游戏图标** `assets/art/app_icon.png` 512×512：主体一颗**命核琉璃珠**（白+金色荧光）居中偏左，**右侧露出主角侧脸一点点**（深色兜帽/侧脸剪影，像素风）；Lead 会复制为 `icon.png` 并重打包。
4. 旧 `meta_panel` 可保留但不再被走廊使用（或删除对它的引用）；所有 UI 保持像素简洁风、无平台化装饰。

## 6. 验收

- 各脚本 `--check-only` / `_syntax_check.gd` failed=0。
- Lead 窗口截图：简洁菜单（虚化星空+无脸主角+五项）、走廊左上按钮/右上弹珠图标、NPC 黑屏白字+NPC消失、角色面板三页（立绘+行囊）、升级经验、三阶弹珠图标、新游戏图标；APK 重建 + badging/apksigner。

# CONTRACT v1.7（v1.6 迭代：策划案(3) + 抠图换角 + 删走廊右上块）

> 本轮用户 3 条：1) 按《基础策划案 (3).docx》修改游戏内部；2) 回廊人物换成用户新给的 P1 图（**自己抠图，不要重画**）；3) 删去回廊界面顶部右上一整块的显示。
> 参考 `docs/CONTRACT_V6.md` 的 v1.5 基础。所有 `.gd` Tab 缩进、UTF-8 无 BOM。

## 1. Lead 已完成（v1.6 数据层）

- `assets/art/char_cutout.png`：由用户 P1 原图（`ref_astrologer_v2.png`，428×993、烘焙棋盘格背景）**已抠图**得到 320×986 透明 PNG（棋盘格用四角 flood fill 去除，保留原始像素画，未重画）。
- `FateConfig` 新增：
  - 存档点 `CHECKPOINT_CORRIDOR/SHOP/LEVEL/CLEAR=1..4`
  - `SHOP_ITEM_PURCHASE_LIMIT=1`、`SLOT_BALL_BONUS_MAX=2`、`BALL_CARRY_MAX=3`、`ITEM_CARRY_MAX=2`
  - `NPC_W_LABEL="W"`、`NPC_INTERACT_RADIUS=90`、`STORY_TYPE_SPEED=0.045`
  - `PERSONAL_ICON_PATH`
  - 弹珠说明 `BALL_BASE_DESC / BALL_GET_WAYS / BALL_LORES`；道具文案 `ITEM_LORES`（详情弹窗用）
  - 角色帧尺寸改为 `PLAYER_FRAME_SIZE=(72,222)`、`PLAYER_SCALE=0.85`（原图比例 320:986）
- `GameState` 新增/变更：
  ```gdscript
  # 购买限制 / 槽位弹珠上限
  GameState.bought_items_this_room: Array[String]
  GameState.is_item_bought(id) -> bool
  GameState.buy_item(id)  # 同房间每种限购1次；instant 类（命运的赠与/奖赏）改为直接进弹珠库
  GameState.slot_bonus_count:int       # 槽位“再射一球”本关已触发数（上限2）
  # 存档点
  GameState.checkpoint:int              # 1走廊 2商店 3关卡 4关卡结束
  GameState.checkpoint_purchases:Array[String]
  GameState.mark_checkpoint(point, purchases=[])   # 会 save
  GameState.get_checkpoint_purchases()
  # 三种弹珠局外携带
  GameState.meta_balls_high:int / selected_balls_high:int
  GameState.select_meta_ball_type(type, delta)     # 合计上限3
  # 失败结算
  GameState.fail_room() 返回 {"level_score","total_score","shards","best","level","story"}（无 carried）
  # 局末带出：所有弹珠（三种）与所有剩余道具全部进行囊
  ```
  `prepare_level` 在 `checkpoint==3` 时会自动恢复 `checkpoint_purchases`（关卡从零开始但保留购买）。

## 2. gameplay-dev（task-17）

1. **回廊人物换图**：`scripts/corridor/player.gd` 改用 ui-dev 生成的 `player_walk.png` / `player_idle.png`（帧 72×222、6/4 帧、0.85 倍）；不要再用程序化小人。NPC 也用同一组帧（flip 镜像、面朝玩家），**头顶显示 W 标签**。
2. **删顶部右上块**：删除 v1.5 右上角弹珠图标按钮/行囊数量整块，并且**不再放任何右上角常驻图标/文字**（按用户要求）；个人信息改为**点击主角本人**打开（可选：长按主角/双击）。
2. **个人信息打开方式**：点击主角本人（触屏点中角色 hitbox）→ 运行时 load `res://scenes/ui/character_panel.tscn`、`open_panel()`；closed 后刷新；走廊底部提示可加「点击角色查看个人信息」。
4. **NPC 对话（doc 第 62 条）**：
   - 当前关 NPC 为镜像（面朝玩家），头顶「W」；玩家靠近（<90px）时按 **W 键**（桌面）或点击 NPC（触屏）→ 黑屏/对话框：**逐字打字机**显示 `GameState.get_story_line()`（`STORY_TYPE_SPEED`）；文字播放完毕后再点击文本框 → 出现「进入试炼」按钮 → 点击进入商店（PREP）；同时 NPC 淡出消失 + `mark_npc_seen(level)`；播放期间冻结移动。
   - 玩家若绕过 NPC 直接到门前 → 门前出现「进入试炼」按钮 → 点击进入商店。
   - 进入商店时调用 `GameState.mark_checkpoint(CHECKPOINT_SHOP)`。
5. **关卡存档点**：玩家点「开始试炼」、正式进关卡前 → `GameState.mark_checkpoint(CHECKPOINT_LEVEL, GameState.get_pending_items())`（记录购买）；关卡完成 `complete_room` 已保存④；回到走廊时 `mark_checkpoint(CHECKPOINT_CORRIDOR)`。
6. **失败结算**：`fail_room()` 后 result UI 显示新字段；「重试本关」= `prepare_level(level)` 重新 prep（购买保留）；「返回上一存档点」= 回到 `level-2` 的走廊①点（`level<=2` 时按钮禁用/暗淡），实现：`GameState.level = max(1, GameState.level-2)`，清空本关分数/购买，`mark_checkpoint(CHECKPOINT_CORRIDOR)` → 切 corridor。
7. 槽位「再射一球」上限 2 已在 GameState 处理；购买的弹珠直接进库也已在 GameState 处理，gameplay 不需要再 grant extra。
8. 保留 v1.5 的行走动画手感、10 关、绿线、右端通道、双倍注等。

## 3. ui-dev（task-18）

1. **角色动画（勿重画）**：用 `assets/art/char_cutout.png`（320×986 原图抠图结果）生成
   - `assets/art/player_walk.png`：6 帧 × 72×222（透明底），**只做不改变画风的动画**：整体 bob、轻微前倾/后仰、斗篷下摆做 1~2px 摆动、法球光晕呼吸（可用逐帧位移/局部变形实现，禁止重绘人物）；
   - `assets/art/player_idle.png`：4 帧 × 72×222（呼吸/法球微光）；
   - `assets/art/player_portrait.png`：替换为 `char_cutout.png` 的半身裁切（角色面板左半用原图，不要再用手绘像素小人）；
   - 保证脚底对齐帧底，NEAREST 过滤。
2. **右上个人信息图标**：`assets/art/personal_icon.png`（64×64）按 doc 美术：微缩命运琉璃珠为底、珠内隐约琉璃匠侧影、外圈三道细碎裂痕、半透明、边缘淡蓝微光。
3. **道具/弹珠详情弹窗**：
   - 道具：价格下方增加 `FateConfig.ITEM_LORES[id]` 文案；**任何界面点击道具图标**都弹出（HUD ⑦、PREP 商店卡、面板卡牌页等）；
   - 弹珠：点击弹珠图标弹出详情（标题「命运/命核/命源琉璃珠」、将“价格”改为**基础得分**（`BALL_BASE_DESC`）、“使用方式”改为**获取方式**（`BALL_GET_WAYS`）+ `BALL_LORES` 文案）；HUD ③ 灯、⑧ 弹珠库、面板弹珠页均可点。
4. **PREP 商店**：每种道具每轮限购 1 次（`is_item_bought` / `can_buy_item`），已购买仍显示但按钮变「已购买」且不可再点；关卡内相同道具**不堆叠**（逐个图标显示）；「携带弹珠」「携带道具」两个标题字号放大、黄色。
5. **角色/行囊面板**：显示三种弹珠拥有数（含 `meta_balls_high`，命源不再写“折算”），勾选带入最多 3 颗（`select_meta_ball_type`）；道具全部带出、可勾选最多 2 个带入；角色信息页保持。
6. **失败结算窗口**：按 doc 第 85-88 条：三列从左到右「关卡得分」「本局总分」「获得命运碎片」；删除“带出物品”；按钮「重试本关」+「返回上一存档点」（level≤2 时禁用变暗）；胜利结算保持原有。
7. 商店界面可加“前往个人信息”入口（可选）。

## 4. audio-dev（task-19，小任务）

- 新增一首 `assets/audio/bgm/bgm_main.ogg`：40~60s 无缝循环、8bit 风、低沉挣扎又带希望（doc 音乐1）；让 start/主菜单、走廊、关卡内都播这一首（`Audio.play_bgm("menu"/"battle"/"shop")` 可统一映射到 bgm_main；胜利/失败短曲保留）。
- SFX 按 doc 第 145~175 条核对：点击（130~150ms 轻击）、玻璃碰撞（60~90ms）、成功“嗡”（80~130ms）、合成失败“咔”（60~90ms）、入槽“啵”（130~150ms）、发射嗡鸣（130~150ms）、开门（2~3s，进入关卡时）。若已有近似音效可复用并调整，缺的补上；`audio.gd` 接口不变。
- 自测峰值/循环接缝，报告文件清单。

## 5. 验收

- 各脚本 `--check-only` / `_syntax_check.gd` failed=0。
- Lead 窗口截图：主菜单、走廊（新人物行走/待机、W 标签/打字机对话/进入试炼、右上仅个人信息图标）、个人信息面板（原图立绘、三珠含命源、携带配置）、商店限购/不堆叠/文案、道具与弹珠详情弹窗、失败结算新按钮；APK 重建 + badging/apksigner。

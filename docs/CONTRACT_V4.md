# CONTRACT v1.4（v1.3 迭代：像素风 / 8bit 音乐 / 双倍注 / 新手引导 / 物理修复）

> 先读本文件；`docs/CONTRACT_V3.md` 为基础，本文件只写本轮增量。
> 所有 `.gd` Tab 缩进、UTF-8 无 BOM；不要越界改别人文件；接口变更先消息 `lead`。
> 本轮用户要求（9 条）：
> 1. 修复弹珠卡在最右边掉不下去 / 长时间默认遁入虚空清零；2. 初始新手引导（拖动道具）；
> 3. 音乐改 8bit 风格；4. 点击道具库「待使用」显示卡牌详情；5. 整体改像素风；
> 6. 每关买完道具、开始时弹对话框询问「双倍」（双倍奖励+双倍惩罚）；7. 游戏名改为「！？珠珠？！」；
> 8. 发射力度可回弹（长按后力度会回落，来回摆动）；9. 适当调宽柱子间隔。

## 1. 所有权（不变）

| 所有者 | 文件 |
|---|---|
| Lead | `project.godot`、`scripts/core/fate_config.gd`、`scripts/autoload/game_state.gd`、`docs/**`、集成/QA/构建 |
| gameplay-dev | `scenes/game.tscn`、`scenes/corridor.tscn`、`scripts/gameplay/**`、`scripts/corridor/**` |
| ui-dev | `scenes/ui/**`、`scenes/main_menu.tscn`、`scripts/ui/**`、`assets/art/**`、`assets/fonts/**`、`tools/gen_art.py` |
| audio-dev | `scripts/autoload/audio.gd`、`assets/audio/**`、`tools/gen_audio.py` |

## 2. Lead 已改（v1.3）

- 游戏名：`FateConfig.GAME_TITLE = "！？珠珠？！"`；`project.godot` 的 `application/config/name` 已改（APK 应用名/窗口标题随之为「！？珠珠？！」）。
- **立柱间距加宽**：`PEG_AREA = Rect2(656,168,552,424)`（原 528×384），`PEG_RADIUS = 11`（原 14），`PEG_JITTER = 2`；6×7 错落不变。
- **双倍注常量**：`DOUBLE_MODE_SCORE_MULT=2`、`DOUBLE_MODE_COIN_MULT=2`、`DOUBLE_MODE_PENALTY_MULT=2`、`DOUBLE_MODE_FAIL_SHARD_DIV=2`。
- **新手引导文案**：`TUTORIAL_TEXT_1/2/3`。
- GameState 新增：
  ```gdscript
  GameState.double_mode: bool
  GameState.set_double_mode(enabled)
  GameState.get_double_score_mult() -> float   # 1 或 2（award_ball_score 内部已乘）
  GameState.get_coin_mult() -> int             # 1 或 2（过关金币/白柱金币已用）
  GameState.get_penalty_mult() -> int          # 1 或 2（黑柱扣分由 gameplay 使用）
  GameState.white_coin_amount() -> int         # 白柱命中给的金币数（双倍=2）
  GameState.should_show_tutorial() -> bool
  GameState.mark_tutorial_seen()
  ```
  `award_ball_score`、`finish_level` 金币、`apply_pocket_bonus` 金币、`fail_room` 碎片已按双倍处理。

## 3. gameplay-dev 必改（task-8）

1. **物理修复（最重要）**
   - 取消「长时间默认遁入虚空清零」：去掉/停用 14s 超时判虚空。改为**卡住救援**：球速 < 35 px/s 持续 1.2s → 给一次朝台面中央上方的冲量；重复最多 4 次；仍卡住 → 传送到台面中央 (x≈900, y≈260) 以向下速度落下（仍可正常入框得分）。只有 y>760（真正掉出屏幕）才判虚空 0 分。
   - **最右侧卡球**：检查右侧轨道/闸门。闸门(GATE) 只在「没有球位于轨道区 x>1216」时关闭；关闭前若轨道内有球，把球向左推出。轨道底部挡板已存在；球停在导流斜面/轨道壁上时用上面的卡住救援处理。
   - 槽位隔板/立柱顶上/右侧墙边都要能被救援逻辑覆盖（任何低速度 1.2s 都触发）。
2. **力度回弹**：蓄力改为 0→1→0→1 的三角波来回摆动（约 1.05s 单程，按住不会停在满格），松手时取当前值发射；⑥ 的虚线轨迹与力度条/百分比实时跟随。
3. **双倍注**：`prep` 的 `start_pressed(double_mode: bool)`（见 §4）→ `_on_prep_started(double_mode)` 里 `GameState.set_double_mode(double_mode)` 后再进 PLAY；黑柱扣分乘 `GameState.get_penalty_mult()`；白柱给币用 `GameState.white_coin_amount()`；HUD 顶部或 ①格显示「双倍」标记（可加在 set_phase_hint 文案里）。
4. **新手引导接入**：进入 PLAY 后若 `GameState.should_show_tutorial()`，运行时 load `res://scenes/ui/tutorial.tscn`（缺失则内置简版提示），调用 `show_tutorial()`，连接 `closed` → `GameState.mark_tutorial_seen()`。只显示一次。
5. **像素风**：gameplay 里 `_draw` 的圆/弧/渐变改成像素块风格——使用 4px 对齐的矩形、方角、限制调色板（FateConfig 颜色）、线条宽度 ≥2、避免抗锯齿弧线（可用多段短直线近似阶梯）；弹珠/立柱贴图使用 nearest 过滤（`texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`）；粒子用小方块。保持现有逻辑不变。
6. 沿用立柱加宽后的 FateConfig 常量（board 已读常量，检查 `PEG_RADIUS` 缩放/碰撞是否随 11 生效）。
7. 自测：`_syntax_check.gd` failed=0；`_flow_test` 更新 PREP 开始信号参数、双倍、卡住救援时间缩短模拟。

## 4. ui-dev 必改（task-9）

1. **像素风全面替换**
   - `tools/gen_art.py` 重做美术为像素风：所有图先用 320×180（背景）/16×16（珠子、图标）/32×32（门等）低分辨率绘制，再用 NEAREST 放大到目标尺寸（1280×720、64×64、48×48、200×320、2560×720 等），目标文件路径/尺寸不变。限制调色板（深靛/紫/金/玉/白/黑），加像素抖动、1px 明暗边、无平滑渐变。包括 `bg_menu/bg_board/bg_corridor/peg_normal/peg_yellow/peg_green/peg_black/peg_white/ball_normal/ball_advanced/guardian/particle_dot/door/icons/*`。
   - UI 主题 `ui_theme.gd` 改为像素面板：`StyleBoxFlat` 圆角=0、边框 3~4px、无阴影/柔和高光，按钮方角+上下 2px 高光，字体可用现有中文字体但字号取整、行距紧凑；面板边角可用小方块装饰。
2. **PREP 双倍注对话框**：点击「开始试炼」→ 先弹对话框「命运双倍注？」，说明：得分×2、金币×2、黑柱惩罚×2、失败碎片减半；按钮「双倍押注」「稳妥开局」→ `start_pressed.emit(true/false)`。信号签名改为 `signal start_pressed(double_mode: bool)`（gameplay 已按此改）。
3. **卡牌详情弹窗**：⑦ 待使用道具/卡牌**短按（点击）**弹出详情面板（图标/名称/类别/描述/价格），点击空白/×关闭；长按仍是拖拽。注意点击与长按的判定阈值（长按 0.25s 起拖；<0.25s 松开算点击）。
4. **新手引导**：`scenes/ui/tutorial.tscn` + `scripts/ui/tutorial.gd`：`func show_tutorial()`、`signal closed`；半透明遮罩，高亮 ⑦ 道具区与右侧立柱/上方弹珠灯区域，显示 `FateConfig.TUTORIAL_TEXT_1/2/3`，一个小手/箭头动画从道具图标指向立柱与弹珠灯，底部「知道了」按钮 → closed。像素风。
5. 主菜单标题改为 `FateConfig.GAME_TITLE`（「！？珠珠？！」），副标题/版本同步；标题字体用像素装饰框。
6. 自测：`--check-only` 通过、窗口截图（像素主菜单/像素 prep+双倍对话框/卡牌详情/引导/HUD）。

## 5. audio-dev 必改（task-10）

- 把 5 首 BGM + 13 个 SFX 全部重制为 **8bit / chiptune 风格**（方波、三角波、噪声鼓、琶音、快速 arpeggio、低采样感），保持文件路径/文件名不变（`assets/audio/bgm/*.ogg`、`assets/audio/sfx/*.wav`），`audio.gd` 接口不变。
- BGM：menu 80s / battle 86s / shop 55s / victory 7s / defeat 7s（可微调时长，但须无缝循环、OGG Vorbis q4~6、总体积 ≤10MB）。
- SFX 需要“8bit 味”：短方波 blip、噪声爆、下行/上行滑音；时长与原要求一致即可。
- 自测：Python 读回波形检查峰值/削波/循环接缝；报告文件清单与大小。

## 6. 验收（Lead）

窗口渲染截图 → 像素风主菜单、PREP 双倍对话框、卡牌详情、新手引导、发射（力度回弹）、卡住救援、双倍得分、结算；无头 flow/mechanics 测试；APK 重建 + aapt2/apksigner 校验。

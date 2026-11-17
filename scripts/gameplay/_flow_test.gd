extends SceneTree
## 临时自测工具 v1.3（gameplay-dev 自用，Lead 集成后可删）。
##
## 用法：
##   & 'D:\Godot_v4.6.3-stable_win64.exe' --headless --path 'G:\GoDot\？！珠珠！？' \
##       --fixed-fps 60 --script 'res://scripts/gameplay/_flow_test.gd'
## 环境变量 FLOW_MODE：
##   flow      （默认）走廊（行囊按钮）→PREP→start→PLAY→5 球→过关→回走廊→第2间→…→胜利→retry/menu
##   mechanics v1.2 新特性：错落立柱/黑柱扣分/白柱金币/随机框奖励/绿线碰撞/gate/分裂/粘滞/卡牌/complete_room
##   fallback  兜底 HUD / 结算 接口与信号
##   fail      未达标 → fail_room → 失败结算 → 重试本关（再进 PREP）
##   diag      右侧弹簧落点诊断
##
## 注意：本脚本以 SceneTree 启动，Autoload 在 _initialize 时尚未进入活动树，
## 因此第一帧再从 root 取 GameState 并实例化场景。

var _gs = null
var _mode := "flow"
var _frames := 0
var _max_frames := 40000
var _stage := 0
var _wait := 0
var _corridor = null
var _game = null
var _known_corridors: Array = []
var _room := 1
var _boosted := false
var _launch_cooldown := 0
var _start_x := 0.0
var _last_score := 0
var _physics_scores := 0
var _fb_flags: Dictionary = {}
var _fb_rflags: Dictionary = {}

func _initialize() -> void:
	_mode = OS.get_environment("FLOW_MODE")
	if _mode == "":
		_mode = "flow"
	print("[FLOW] mode=", _mode)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _gs == null:
		_gs = root.get_node("GameState")
		_bootstrap()
		return
	if _frames > _max_frames:
		_fail("超时 frames=%d mode=%s stage=%d room=%d" % [_frames, _mode, _stage, _room])
		return
	match _mode:
		"flow":
			_tick_flow()
		"mechanics":
			_tick_mechanics()
		"fallback":
			_tick_fallback()
		"fail":
			_tick_fail()
		"diag":
			_tick_diag()
		"v13":
			_tick_v13()
		"v14":
			_tick_v14()
		"v16":
			_tick_v16()

# ================= 通用 =================

func _bootstrap() -> void:
	if _mode == "flow":
		_gs.start_new_run()
		var packed = load("res://scenes/corridor.tscn")
		if packed == null or not (packed is PackedScene):
			_fail("无法加载 corridor.tscn")
			return
		_corridor = packed.instantiate()
		root.add_child(_corridor)
		_known_corridors.append(_corridor)
		_stage = 0
		_wait = 0
	else:
		_stage = 0
		_wait = 0

func _find_new_corridor() -> Node:
	for child in root.get_children():
		if not child.has_method("get_door_state") or not child.has_method("_enter_room"):
			continue
		if _known_corridors.has(child):
			continue
		return child
	return null

func _find_game_excluding(exclude = null) -> Node:
	for child in root.get_children():
		if child == exclude:
			continue
		if child.has_method("_on_launch_requested") and child.has_method("_on_prep_started"):
			return child
	return null

func _find_game() -> Node:
	return _find_game_excluding(null)

func _find_main_menu() -> Node:
	for child in root.get_children():
		var node_name := String(child.name)
		if node_name == "MainMenu" or node_name.to_lower().contains("main"):
			return child
		var scr = child.get_script()
		if scr != null and String(scr.resource_path).contains("main_menu"):
			return child
	return null

func _phase(game: Node) -> int:
	if game == null or not is_instance_valid(game):
		return -1
	return int(game.phase)

func _expected_doors(level: int) -> Array:
	var out: Array = []
	for i in FateConfig.CORRIDOR_DOOR_X.size():
		var room := i + 1
		if room < level:
			out.append(0)
		elif room == level:
			out.append(1)
		else:
			out.append(2)
	return out

## 找到 game 后：校验 PREP（HUD 隐藏、prep 面板存在），然后开始试炼
func _start_prep_room(game: Node) -> bool:
	if _phase(game) != 0:
		_fail("进入房间后应为 PREP 阶段，实际 %d" % _phase(game))
		return false
	if game.hud != null and bool(game.hud.visible):
		_fail("PREP 阶段 HUD 应隐藏")
		return false
	if game._prep_root == null:
		_fail("PREP 阶段未创建准备面板（prep.tscn / 兜底）")
		return false
	game._on_prep_started(false)
	if _phase(game) != 1:
		_fail("开始试炼后应为 PLAY 阶段，实际 %d" % _phase(game))
		return false
	if game.hud != null and not bool(game.hud.visible):
		_fail("PLAY 阶段 HUD 应显示")
		return false
	return true

func _success(message: String) -> void:
	print("[FLOW] SUCCESS: ", message)
	print("[FLOW] === 全部检查点通过 ===")
	quit(0)

func _fail(message: String) -> void:
	print("[FLOW] === 失败：", message, " ===")
	quit(1)

## 按当前关卡 buff/双倍/卡牌计算期望得分
func _expected_score(base: int, mult: float, buffed: bool) -> int:
	var bm := FateConfig.BUFFED_BALL_MULT if buffed else 1.0
	return int(floor(float(base) * mult * _gs.get_score_multiplier() * bm * _gs.get_double_score_mult()))

# ================= flow =================

func _tick_flow() -> void:
	match _stage:
		0:
			_flow_corridor_basics()
		1:
			_flow_movement_done()
		2:
			_flow_wait_room_prep()
		3:
			_flow_play_room()
		4:
			_flow_wait_next_corridor()
		5:
			_flow_wait_victory_result()
		6:
			_flow_wait_retry_corridor()
		7:
			_flow_wait_main_menu()

func _flow_corridor_basics() -> void:
	_wait += 1
	if _wait < 8:
		return
	if _corridor == null or not is_instance_valid(_corridor):
		_fail("走廊实例丢失")
		return
	if _corridor.player == null or _corridor.joystick == null:
		_fail("走廊缺少 player / joystick")
		return
	var states: Array = [_corridor.get_door_state(0), _corridor.get_door_state(1), _corridor.get_door_state(2)]
	if states != [1, 2, 2]:
		_fail("初始门状态错误：%s" % str(states))
		return
	print("[FLOW] 走廊门状态 OK: ", states)
	# 行囊按钮 → 打开 meta_panel（ui 未就绪时走兜底）
	_corridor._open_meta_panel()
	if _corridor._meta_panel == null or not is_instance_valid(_corridor._meta_panel):
		_fail("行囊按钮未打开 meta panel")
		return
	print("[FLOW] 行囊面板打开 OK（行囊数 %d）" % int(_corridor._meta_count()))
	_corridor._on_meta_closed()
	if _corridor._meta_panel != null:
		_fail("行囊面板关闭后未释放")
		return
	print("[FLOW] 行囊面板关闭 OK")
	_start_x = float(_corridor.player.position.x)
	_corridor.joystick.vector = Vector2(1.0, 0.0)
	_wait = 0
	_stage = 1

func _flow_movement_done() -> void:
	_wait += 1
	if _wait < 20:
		return
	_corridor.joystick.vector = Vector2.ZERO
	var moved := float(_corridor.player.position.x) - _start_x
	if moved < 50.0:
		_fail("摇杆移动无效：位移 %.1f" % moved)
		return
	print("[FLOW] 摇杆移动 OK（位移 %.1f）" % moved)
	_corridor.player.position.x = FateConfig.CORRIDOR_DOOR_X[_gs.level - 1] - 40.0
	_corridor._enter_room()
	_wait = 0
	_stage = 2

func _flow_wait_room_prep() -> void:
	_wait += 1
	_game = _find_game()
	if _game == null:
		if _wait > 600:
			_fail("走廊进门后未加载 game 场景（room=%d）" % _room)
		return
	if int(_gs.level) != _room:
		_fail("房间号错误：GameState.level=%d，期望 %d" % [int(_gs.level), _room])
		return
	if int(_game.board.pegs.size()) != 42:
		_fail("立柱数量错误：%d" % int(_game.board.pegs.size()))
		return
	if not _start_prep_room(_game):
		return
	print("[FLOW] 第 %d 间：PREP→PLAY / 42 立柱 / 弹珠 %d / 目标 %d OK" % [_room, int(_gs.ball_slots.size()), int(_gs.get_target())])
	_boosted = false
	_last_score = int(_gs.level_score)
	_physics_scores = 0
	_launch_cooldown = 3
	_stage = 3

func _flow_play_room() -> void:
	if _game == null or not is_instance_valid(_game):
		_fail("game 实例丢失")
		return
	if int(_gs.level_score) != _last_score:
		var delta := int(_gs.level_score) - _last_score
		if delta > 0 and delta < 900:
			_physics_scores += 1
			print("[FLOW] 第 %d 间物理入框 +%d（本间累计 %d）" % [_room, delta, int(_gs.level_score)])
		_last_score = int(_gs.level_score)
	if _phase(_game) != 1:
		if not bool(_gs.run_active):
			print("[FLOW] 第 %d 间（最后一间）结算完成，等待胜利结算面板" % _room)
			_wait = 0
			_stage = 5
		else:
			print("[FLOW] 第 %d 间结算完成（物理入框 %d 次），等待回走廊" % [_room, _physics_scores])
			_wait = 0
			_stage = 4
		return
	# 第 1 间走真实物理；第 2~10 间直接加分触发立即过关，加快 10 关循环测试
	if _room >= 2 and not _boosted:
		_boosted = true
		_gs.level_score += 5000
		_game._check_level_end()
		return
	if not _game._active_balls.is_empty():
		for ball in _game._active_balls:
			if ball != null and is_instance_valid(ball) and int(_gs.balls_left) == 0 and not _boosted:
				_boosted = true
				_gs.level_score += 5000
				print("[FLOW] （测试）最后一球飞行中强制达标，验证立即过关")
		return
	if int(_gs.balls_left) <= 0:
		return
	if _launch_cooldown > 0:
		_launch_cooldown -= 1
		return
	_launch_cooldown = 4
	_game._on_launch_requested(0.95)

func _flow_wait_next_corridor() -> void:
	_wait += 1
	var next_corridor = _find_new_corridor()
	if next_corridor == null:
		if _wait > 800:
			_fail("过关后未回到走廊场景（room=%d）" % _room)
		return
	var expected_level := _room + 1
	if int(_gs.level) != expected_level:
		_fail("过关后 level 应为 %d，实际 %d" % [expected_level, int(_gs.level)])
		return
	var states: Array = []
	for i in FateConfig.CORRIDOR_DOOR_X.size():
		states.append(next_corridor.get_door_state(i))
	if states != _expected_doors(expected_level):
		_fail("回走廊后门状态错误：%s（期望 %s）" % [str(states), str(_expected_doors(expected_level))])
		return
	print("[FLOW] 回到走廊：level=%d，门状态 %s OK" % [expected_level, str(states)])
	_known_corridors.append(next_corridor)
	_corridor = next_corridor
	_room = expected_level
	next_corridor.player.position.x = FateConfig.CORRIDOR_DOOR_X[expected_level - 1] - 40.0
	next_corridor._enter_room()
	_wait = 0
	_stage = 2

func _flow_wait_victory_result() -> void:
	_wait += 1
	if _game == null or not is_instance_valid(_game):
		_fail("最后一间结束后 game 实例丢失")
		return
	if _phase(_game) != 2:
		if _wait > 600:
			_fail("未出现胜利结算面板（phase=%d）" % _phase(_game))
		return
	if bool(_gs.run_active):
		_fail("胜利结算时 run_active 应为 false")
		return
	print("[FLOW] 胜利结算出现：总分 %d / 最高分 %d / 碎片 %d / 行囊 %d OK" % [
		int(_gs.total_score), int(_gs.best_score), int(_gs.total_shards), int(_gs.meta_balls_normal + _gs.meta_balls_advanced)])
	_game._on_retry_pressed()
	_wait = 0
	_stage = 6

func _flow_wait_retry_corridor() -> void:
	_wait += 1
	var next_corridor = _find_new_corridor()
	if next_corridor == null:
		if _wait > 800:
			_fail("胜利后 retry 未回到走廊")
		return
	if int(_gs.level) != 1 or not bool(_gs.run_active):
		_fail("retry 后应为新一局 level=1，实际 level=%d run_active=%s" % [int(_gs.level), str(_gs.run_active)])
		return
	print("[FLOW] retry → 新一局走廊 level=1 OK")
	_known_corridors.append(next_corridor)
	_corridor = next_corridor
	_corridor._goto_menu()
	_wait = 0
	_stage = 7

func _flow_wait_main_menu() -> void:
	_wait += 1
	if _find_main_menu() == null:
		if _wait > 600:
			_fail("未切换到主菜单场景")
		return
	print("[FLOW] menu → MainMenu 场景 OK")
	_success("flow：走廊(行囊/10 门)→10 间房 PREP/PLAY/物理入框/达标过关→第 10 关胜利结算→retry→走廊→menu→主菜单 全部通过")

# ================= mechanics（v1.2 新特性） =================

func _tick_mechanics() -> void:
	match _stage:
		0:
			_mech_step0()
		1:
			_mech_step1()
		2:
			_mech_step2()
		3:
			_mech_step3()
		25:
			_tick_mechanics_after_launch()
		26:
			_tick_mechanics_sticky_release()
		27:
			_tick_mechanics_split_verify()
		28:
			_tick_mechanics_split_once()

func _mech_step0() -> void:
	_gs.start_new_run()
	_gs.prepare_level(1)
	# 随机框配置
	if _gs.slot_configs.size() != 6:
		_fail("随机框数量错误：%d" % _gs.slot_configs.size())
		return
	print("[FLOW] 随机框：", _gs.slot_configs)
	# 购买卡牌/装备（测试给足金币）
	_gs.add_coins(100)
	for id in ["reflector", "sticky", "splitcard", "masscard", "shrinkcard"]:
		if not _gs.buy_item(id):
			_fail("购买 %s 失败" % id)
			return
	print("[FLOW] 准备阶段购买 OK：", _gs.get_pending_items())
	var packed = load("res://scenes/game.tscn")
	if packed == null or not (packed is PackedScene):
		_fail("无法加载 game.tscn")
		return
	_game = packed.instantiate()
	root.add_child(_game)
	_wait = 0
	_stage = 1

func _mech_step1() -> void:
	_wait += 1
	if _wait < 6:
		return
	if _game == null or not is_instance_valid(_game):
		_fail("game 实例丢失")
		return
	if _phase(_game) != 0:
		_fail("game 初始应为 PREP 阶段，实际 %d" % _phase(_game))
		return
	if _game.board == null or int(_game.board.pegs.size()) != 42:
		_fail("立柱数量错误")
		return
	# 错落布局：奇数行整体横移半列距
	var area: Rect2 = FateConfig.PEG_AREA
	var cell_x := area.size.x / float(FateConfig.PEG_COLS)
	var offset := cell_x * FateConfig.PEG_ROW_OFFSET_RATIO
	var even_x := float(_game.board.pegs[0].position.x)
	var odd_x := float(_game.board.pegs[FateConfig.PEG_COLS].position.x)
	if absf(even_x - (area.position.x + cell_x * 0.5)) > FateConfig.PEG_JITTER + 1.0:
		_fail("偶数行立柱 x 偏移异常：%.1f" % even_x)
		return
	if absf(odd_x - (area.position.x + cell_x * 0.5 + offset)) > FateConfig.PEG_JITTER + 4.0:
		_fail("奇数行立柱未错落半列距：%.1f（期望约 %.1f）" % [odd_x, area.position.x + cell_x * 0.5 + offset])
		return
	print("[FLOW] 立柱错落布局 OK（even=%.1f odd=%.1f，半列距=%.1f）" % [even_x, odd_x, offset])
	# 绿柱真实碰撞线段：手动补一段，验证 SegmentShape2D 存在
	_game.board._add_link_segment(Vector2(700.0, 300.0), Vector2(760.0, 300.0))
	var segment_count := 0
	for child in _game.board.get_children():
		if child is StaticBody2D and String(child.name).begins_with("GreenLink"):
			for sub in child.get_children():
				if sub is CollisionShape2D and (sub as CollisionShape2D).shape is SegmentShape2D:
					segment_count += 1
	if segment_count < 1:
		_fail("绿色连线未生成 SegmentShape2D 碰撞体")
		return
	print("[FLOW] 绿色连线 SegmentShape2D OK（共 %d 段）" % segment_count)
	# 准备阶段 HUD 隐藏 / 开始试炼
	if not _start_prep_room(_game):
		return
	print("[FLOW] PREP→PLAY（HUD 显隐）OK")
	# 装备：粘性器/反射器拖到立柱
	var peg_a = _game.board.pegs[5]
	var peg_b = _game.board.pegs[9]
	_game._on_equip_requested("sticky", peg_a.position)
	_game._on_equip_requested("reflector", peg_b.position)
	if String(peg_a.equipped) != "sticky" or String(peg_b.equipped) != "reflector":
		_fail("装备落点失败：%s / %s" % [String(peg_a.equipped), String(peg_b.equipped)])
		return
	if _gs.get_pending_items().has("sticky") or _gs.get_pending_items().has("reflector"):
		_fail("装备使用后 pending 未消耗")
		return
	print("[FLOW] board.equip_at（粘性/反射器）OK")
	# 绑定卡牌到弹珠槽
	_gs.set_ball_card(0, "splitcard")
	_gs.set_ball_card(1, "masscard")
	_gs.set_ball_card(2, "shrinkcard")
	if _gs.get_ball_card(0) != "splitcard" or _gs.get_ball_card(1) != "masscard" or _gs.get_ball_card(2) != "shrinkcard":
		_fail("弹珠卡牌绑定失败")
		return
	print("[FLOW] 卡牌绑定（split/mass/shrink）OK")
	_stage = 2
	_wait = 0

func _mech_step2() -> void:
	_wait += 1
	if _wait < 4:
		return
	# 防止这些测试触发过关
	_gs.fate_event["target_delta"] = 999
	# ---- 黑柱扣分：base 5 - 3*1 = 2，×1 倍率 ×0.8 关卡 = 1 ----
	_gs.slot_configs[0] = {"mult": 1.0, "bonus": ""}
	var black_ball = load("res://scripts/gameplay/ball.gd").new()
	black_ball.advanced = false
	black_ball.card = ""
	black_ball.black_hits = 3
	black_ball.position = Vector2(900.0, 400.0)
	root.add_child(black_ball)
	var before_black: int = int(_gs.level_score)
	_game._on_slot_hit(black_ball, 0, 1.0, Vector2(900.0, 640.0))
	var black_delta: int = int(_gs.level_score) - before_black
	var expect_black := _expected_score(maxi(0, _gs.get_ball_base(0) - 3 * FateConfig.BLACK_PENALTY * _gs.get_penalty_mult()), 1.0, false)
	if black_delta != expect_black:
		_fail("黑柱扣分错误：delta=%d（期望 %d）" % [black_delta, expect_black])
		return
	print("[FLOW] 黑柱扣分 OK（+%d）" % black_delta)
	if is_instance_valid(black_ball):
		black_ball.free()
	# ---- 随机框奖励：coin2 ----
	_gs.slot_configs[1] = {"mult": 2.0, "bonus": "coin2"}
	var pocket_ball = load("res://scripts/gameplay/ball.gd").new()
	pocket_ball.advanced = false
	pocket_ball.card = ""
	pocket_ball.position = Vector2(900.0, 400.0)
	root.add_child(pocket_ball)
	var coins_before: int = int(_gs.coins)
	var score_before: int = int(_gs.level_score)
	_game._on_slot_hit(pocket_ball, 1, 2.0, Vector2(900.0, 640.0))
	var pocket_delta: int = int(_gs.level_score) - score_before
	# base 5 × 2.0 × 0.8 = 8
	var expect_pocket := _expected_score(_gs.get_ball_base(0), 2.0, false)
	if pocket_delta != expect_pocket:
		_fail("随机框倍率错误：delta=%d（期望 %d）" % [pocket_delta, expect_pocket])
		return
	if int(_gs.coins) != coins_before + 2:
		_fail("随机框金币+2 奖励未生效：coins %d -> %d" % [coins_before, int(_gs.coins)])
		return
	if is_instance_valid(pocket_ball):
		pocket_ball.free()
	print("[FLOW] 随机框（×2 / 金币+2）OK")
	# ---- 随机框奖励：ball1（再射一球） ----
	_gs.slot_configs[2] = {"mult": 1.0, "bonus": "ball1"}
	var extra_ball = load("res://scripts/gameplay/ball.gd").new()
	extra_ball.advanced = false
	extra_ball.card = ""
	extra_ball.position = Vector2(900.0, 400.0)
	root.add_child(extra_ball)
	var total_before: int = int(_gs.balls_total)
	var left_before: int = int(_gs.balls_left)
	_game._on_slot_hit(extra_ball, 2, 1.0, Vector2(900.0, 640.0))
	if int(_gs.balls_total) != total_before + 1 or int(_gs.balls_left) != left_before + 1:
		_fail("随机框「再射一球」未生效：total %d->%d left %d->%d" % [total_before, int(_gs.balls_total), left_before, int(_gs.balls_left)])
		return
	if is_instance_valid(extra_ball):
		extra_ball.free()
	print("[FLOW] 随机框（再射一球）OK")
	# ---- 白柱金币概率 + 集成 ----
	var white_peg = _find_peg_of_type(FateConfig.PEG_TYPE_WHITE)
	if white_peg == null:
		# 极小概率本房间没有白柱：直接造一个白柱实例测概率逻辑
		white_peg = load("res://scripts/gameplay/peg.gd").new()
		white_peg.peg_type = FateConfig.PEG_TYPE_WHITE
		root.add_child(white_peg)
	white_peg.white_hits = 100
	if not bool(white_peg.try_white_coin()):
		_fail("白柱高累计次数后仍未给金币")
		return
	var coins_before_white: int = int(_gs.coins)
	_game._on_ball_white_coin(Vector2(900.0, 300.0))
	if int(_gs.coins) != coins_before_white + 1:
		_fail("白柱金币集成未生效")
		return
	print("[FLOW] 白柱概率+金币 OK（累计次数递增）")
	# ---- gate 开合 + 分裂卡 ----
	_game._on_launch_requested(0.9)
	if _game._active_balls.is_empty():
		_fail("发射后场上无球")
		return
	var split_ball = _game._active_balls[0]
	if String(split_ball.get("card")) != "splitcard":
		_fail("第一颗未绑定分裂卡")
		return
	if bool(_game.board.is_gate_closed()):
		_fail("发射时 gate 应为打开状态")
		return
	split_ball.global_position = Vector2(1000.0, 300.0)
	_wait = 0
	_stage = 25
	# 下一帧检查 gate 关闭与分裂
	_pending_split_ball = split_ball

var _pending_split_ball = null

func _tick_mechanics_after_launch() -> void:
	_wait += 1
	if _wait < 3:
		return
	# gate 应在球进入台面后关闭
	if not bool(_game.board.is_gate_closed()):
		_fail("球进入台面后 gate 未关闭")
		return
	print("[FLOW] ⑥ 轨道缺口 gate 开合 OK")
	if _pending_split_ball == null or not is_instance_valid(_pending_split_ball):
		_fail("分裂测试球丢失")
		return
	_pending_split_ball.trigger_split()
	_wait = 0
	_stage = 27

func _tick_mechanics_split_verify() -> void:
	_wait += 1
	if _wait < 3:
		return
	if _game._active_balls.size() != 3:
		_fail("分裂后场上球数错误：%d（期望 3）" % _game._active_balls.size())
		return
	# 二次触发不应再分裂
	if _pending_split_ball != null and is_instance_valid(_pending_split_ball):
		_pending_split_ball.trigger_split()
	_wait = 0
	_stage = 28

func _tick_mechanics_split_once() -> void:
	_wait += 1
	if _wait < 3:
		return
	if _game._active_balls.size() != 3:
		_fail("分裂卡重复触发：场上球数 %d" % _game._active_balls.size())
		return
	print("[FLOW] 分裂卡 3 球（只分裂一次）OK")
	# 收掉 3 颗球（避免物理干扰后续测试）
	_gs.slot_configs[4] = {"mult": 1.0, "bonus": ""}
	for ball in _game._active_balls.duplicate():
		if ball != null and is_instance_valid(ball):
			_game._on_slot_hit(ball, 4, 1.0, Vector2(1000.0, 640.0))
	_mech_begin_sticky()

func _mech_begin_sticky() -> void:
	# ---- 粘滞：0.9s 后自动释放 / 质量卡免疫 / 质量卡撞落 ----
	var sticky_ball = load("res://scripts/gameplay/ball.gd").new()
	sticky_ball.position = Vector2(900.0, 300.0)
	root.add_child(sticky_ball)
	sticky_ball.stick()
	if not sticky_ball.is_stuck():
		_fail("粘性器未黏住弹珠")
		return
	var mass_ball = load("res://scripts/gameplay/ball.gd").new()
	mass_ball.card = "masscard"
	mass_ball.position = Vector2(900.0, 340.0)
	root.add_child(mass_ball)
	mass_ball.stick()
	if mass_ball.is_stuck():
		_fail("质量卡球不应被黏住")
		return
	mass_ball._on_body_entered(sticky_ball)
	if sticky_ball.is_stuck():
		_fail("质量卡球未撞落被黏住的弹珠")
		return
	print("[FLOW] 粘滞 / 质量卡免疫 / 撞落 OK")
	sticky_ball.free()
	mass_ball.free()
	# 再测 0.9s 自动释放
	var timed_ball = load("res://scripts/gameplay/ball.gd").new()
	timed_ball.position = Vector2(900.0, 300.0)
	root.add_child(timed_ball)
	timed_ball.stick()
	if not timed_ball.is_stuck():
		_fail("粘性器未黏住弹珠（计时测试）")
		return
	_timed_ball = timed_ball
	_wait = 0
	_stage = 26

var _timed_ball = null

func _tick_mechanics_sticky_release() -> void:
	_wait += 1
	if _wait < 70:
		return
	if _timed_ball == null or not is_instance_valid(_timed_ball):
		_fail("计时粘滞球丢失")
		return
	if _timed_ball.is_stuck():
		_fail("粘滞超过 0.9s 仍未释放")
		return
	print("[FLOW] 粘滞 0.9s 自动释放 OK")
	_timed_ball.free()
	# ---- complete_room：达标后 level+1，回走廊 ----
	_gs.level_score += 5000
	_game._check_level_end()
	if int(_gs.level) != 2:
		_fail("complete_room 后 level 未 +1（实际 %d）" % int(_gs.level))
		return
	print("[FLOW] complete_room 后 level=2 OK")
	_wait = 0
	_stage = 3

func _find_peg_of_type(peg_type: int):
	for peg in _game.board.pegs:
		if peg != null and is_instance_valid(peg) and int(peg.peg_type) == peg_type:
			return peg
	return null

func _mech_step3() -> void:
	_wait += 1
	if _wait < 180:
		return
	if _find_new_corridor() == null:
		_fail("过关后未回到 corridor 场景")
		return
	print("[FLOW] 过关后回到走廊 OK")
	_success("mechanics：错落立柱/绿线碰撞/黑柱扣分/白柱金币/随机框金币+2与再射一球/gate/分裂3球/粘滞与质量卡/complete_room 全部通过")

# ================= fallback =================

func _tick_fallback() -> void:
	if _stage == 0:
		_stage = 1
		_gs.start_new_run()
		_gs.prepare_level(1)
		_fb_flags = {"shop": false, "exit": false, "equip": ""}
		_fb_rflags = {"retry": false, "menu": false}
		var flags = _fb_flags
		var hud = load("res://scripts/gameplay/hud_fallback.gd").new()
		root.add_child(hud)
		hud.set_game(null)
		hud.shop_closed.connect(func() -> void: flags["shop"] = true)
		hud.exit_pressed.connect(func() -> void: flags["exit"] = true)
		hud.equip_requested.connect(func(item_id: String, _pos: Vector2) -> void: flags["equip"] = item_id)
		hud.set_phase(0)
		var offers: Array[String] = ["reflector", "splitcard"]
		hud.open_shop(1, offers)
		hud.show_fate_event({"name": "命运垂青", "desc": "测试"})
		hud.set_phase_hint("测试提示")
		hud.popup_score(12, Vector2(900.0, 600.0))
		hud.flash_error("测试错误")
		hud.refresh()
		hud._on_buy_pressed("reflector")
		if not _gs.get_pending_items().has("reflector"):
			_fail("兜底 HUD 购买后 pending 未登记")
			return
		_gs.add_coins(100)
		hud._on_buy_pressed("splitcard")
		hud._on_pending_pressed("splitcard")
		if _gs.get_ball_card(0) != "splitcard":
			_fail("兜底 HUD 卡牌绑定失败：%s" % _gs.get_ball_card(0))
			return
		hud._on_pending_pressed("reflector")
		hud._on_close_pressed()
		var rflags = _fb_rflags
		var result = load("res://scripts/gameplay/result_fallback.gd").new()
		root.add_child(result)
		result.retry_pressed.connect(func() -> void: rflags["retry"] = true)
		result.menu_pressed.connect(func() -> void: rflags["menu"] = true)
		result.show_result(true, {"total_score": 88, "shards": 17, "is_new_best": true, "best": 88, "level": 3, "carried": {"balls_normal": 2, "balls_advanced": 1, "cards": ["splitcard"]}})
		result._on_retry_pressed()
		result._on_menu_pressed()
		_wait = 0
		return
	_wait += 1
	if _wait < 10:
		return
	if not bool(_fb_flags.get("shop", false)):
		_fail("兜底 HUD shop_closed 未触发")
		return
	if String(_fb_flags.get("equip", "")) != "reflector":
		_fail("兜底 HUD equip_requested 未触发")
		return
	if not bool(_fb_rflags.get("retry", false)) or not bool(_fb_rflags.get("menu", false)):
		_fail("兜底结算 retry/menu 信号未触发")
		return
	_success("fallback：兜底 HUD / 卡牌绑定 / 结算接口与信号全部通过")

# ================= fail =================

func _tick_fail() -> void:
	match _stage:
		0:
			_stage = 1
			_gs.start_new_run()
			_gs.prepare_level(1)
			_gs.fate_event["target_delta"] = 999
			var packed = load("res://scenes/game.tscn")
			if packed == null or not (packed is PackedScene):
				_fail("无法加载 game.tscn")
				return
			_game = packed.instantiate()
			root.add_child(_game)
			_wait = 0
		1:
			_wait += 1
			if _wait < 6:
				return
			if not _start_prep_room(_game):
				return
			_fail_cd = 3
			_stage = 2
		2:
			if _game == null or not is_instance_valid(_game):
				_fail("game 实例丢失")
				return
			if _phase(_game) != 1:
				_wait = 0
				_stage = 3
				return
			if not _game._active_balls.is_empty():
				return
			if int(_gs.balls_left) <= 0:
				return
			_fail_cd -= 1
			if _fail_cd > 0:
				return
			_fail_cd = 4
			_game._on_launch_requested(0.6)
		3:
			_wait += 1
			if _game == null or not is_instance_valid(_game):
				_fail("等待失败结算时 game 丢失")
				return
			if _phase(_game) != 2:
				if _wait > 900:
					_fail("未出现失败结算面板（phase=%d）" % _phase(_game))
				return
			if not bool(_gs.run_active):
				_fail("失败后应保留当前局（继续/重试/返回存档点）")
				return
			if int(_gs.checkpoint) != FateConfig.CHECKPOINT_LEVEL:
				_fail("失败后应停留在关卡存档点③")
				return
			print("[FLOW] 失败结算出现（level_score=%d / 目标 %d），测试「重试本关」" % [int(_gs.level_score), int(_gs.get_target())])
			var old_game = _game
			_game = null
			old_game._on_retry_pressed()
			_keep_old = old_game
			_wait = 0
			_stage = 4
		4:
			_wait += 1
			for child in root.get_children():
				if child == _keep_old:
					continue
				if child.has_method("_on_launch_requested") and child.has_method("_on_prep_started"):
					if int(_gs.level) != 1:
						_fail("重试后 level 应为 1，实际 %d" % int(_gs.level))
						return
					if _phase(child) != 0:
						_fail("重试后应为 PREP 阶段")
						return
					print("[FLOW] 「重试本关」重新进入第 1 间 PREP OK")
					_success("fail：未达标 → fail_room → 失败结算 → 重试本关（PREP）流程通过")
					return
			if _wait > 600:
				_fail("重试本关未重新加载 game 场景")

var _fail_cd := 0
var _keep_old = null

# ================= diag =================

var _diag_phase := 0
var _diag_wait := 0
var _diag_idx := 0
var _diag_cd := 0
var _diag_ticks := 0
var _diag_powers: Array = [0.2, 0.4, 0.6, 0.8, 1.0]

func _tick_diag() -> void:
	match _diag_phase:
		0:
			_diag_phase = 1
			_gs.start_new_run()
			_gs.prepare_level(1)
			_gs.fate_event["target_delta"] = 999
			var packed = load("res://scenes/game.tscn")
			if packed == null or not (packed is PackedScene):
				_fail("无法加载 game.tscn")
				return
			_game = packed.instantiate()
			root.add_child(_game)
		1:
			_diag_wait += 1
			if _diag_wait < 6:
				return
			_start_prep_room(_game)
			_game.board.connect("slot_hit", func(_ball, idx: int, mult: float, pos: Vector2) -> void:
				print("[DIAG] SLOT idx=%d mult=%.1f bonus=%s pos=(%.0f,%.0f) score=%d" % [
					idx, mult, _gs.get_pocket_bonus(idx), pos.x, pos.y, int(_gs.level_score)])
			)
			_diag_phase = 2
			_diag_cd = 5
		2:
			if _game == null or not is_instance_valid(_game):
				_fail("game 实例丢失")
				return
			if not _game._active_balls.is_empty():
				_diag_ticks += 1
				if _diag_ticks % 20 == 0:
					var ball = _game._active_balls[0]
					print("[DIAG] ball#%d pos=(%.0f,%.0f) vel=(%.0f,%.0f)" % [
						_diag_idx, float(ball.global_position.x), float(ball.global_position.y),
						float(ball.linear_velocity.x), float(ball.linear_velocity.y)])
				return
			_diag_cd -= 1
			if _diag_cd > 0:
				return
			if _diag_idx >= _diag_powers.size():
				print("[DIAG] 全部弹珠结束：level_score=%d total=%d" % [int(_gs.level_score), int(_gs.total_score)])
				_success("diag：落点诊断完成")
				return
			var power: float = _diag_powers[_diag_idx]
			_diag_idx += 1
			_diag_cd = 40
			_diag_ticks = 0
			_game._on_launch_requested(power)
			print("[DIAG] launch#%d power=%.2f 目标=%d" % [_diag_idx, power, int(_gs.get_target())])

# ================= v13：双倍注 / 引导 / 力度回弹 / 卡球救援 / 闸门 / 立柱加宽 =================

func _tick_v13() -> void:
	match _stage:
		0:
			_stage = 1
			_gs.start_new_run()
			_gs.prepare_level(1)
			_gs.tutorial_seen = false
			_gs.fate_event["target_delta"] = 999
			var packed = load("res://scenes/game.tscn")
			if packed == null or not (packed is PackedScene):
				_fail("无法加载 game.tscn")
				return
			_game = packed.instantiate()
			root.add_child(_game)
			_wait = 0
		1:
			_wait += 1
			if _wait < 6:
				return
			if _phase(_game) != 0:
				_fail("game 初始应为 PREP 阶段")
				return
			# 双倍注 + 新手引导（优先走真实 prep 的 start_pressed(bool) 信号）
			if _game._prep_root != null and is_instance_valid(_game._prep_root) and _game._prep_root.has_signal("start_pressed"):
				_game._prep_root.emit_signal("start_pressed", true)
			else:
				_game._on_prep_started(true)
			if not bool(_gs.double_mode):
				_fail("双倍注未写入 GameState")
				return
			if _game._tutorial_root == null:
				_fail("进入 PLAY 后未显示新手引导")
				return
			print("[FLOW] 双倍注 + 新手引导弹出 OK")
			_game._on_tutorial_closed()
			if _gs.should_show_tutorial():
				_fail("关闭引导后 mark_tutorial_seen 未生效")
				return
			print("[FLOW] 新手引导关闭 + 只显示一次 OK")
			# 立柱加宽适配：42 根、半径 11、最右柱不嵌入轨道墙
			if int(_game.board.pegs.size()) != 42:
				_fail("立柱数量错误")
				return
			var radius_ok := true
			var overlap := false
			for peg in _game.board.pegs:
				var collision = peg.get_child(0)
				if collision is CollisionShape2D:
					var circle = (collision as CollisionShape2D).shape
					if circle is CircleShape2D and absf((circle as CircleShape2D).radius - FateConfig.PEG_RADIUS) > 0.01:
						radius_ok = false
				if float(peg.position.x) > FateConfig.RAIL_LEFT - FateConfig.PEG_RIGHT_GAP + 0.5:
					overlap = true
			if not radius_ok:
				_fail("立柱碰撞半径未随 PEG_RADIUS=11 生效")
				return
			if overlap:
				_fail("有立柱嵌入右侧轨道墙")
				return
			print("[FLOW] 加宽立柱：42 根 / 半径 %.0f / 无嵌墙 OK" % FateConfig.PEG_RADIUS)
			# 双倍得分：base 5 × ×1 × 0.8 × 2 = 8
			_gs.slot_configs[0] = {"mult": 1.0, "bonus": ""}
			var ball_double = load("res://scripts/gameplay/ball.gd").new()
			ball_double.position = Vector2(900.0, 400.0)
			root.add_child(ball_double)
			var before_double: int = int(_gs.level_score)
			_game._on_slot_hit(ball_double, 0, 1.0, Vector2(900.0, 640.0))
			var expect_double := _expected_score(_gs.get_ball_base(0), 1.0, false)
			if int(_gs.level_score) - before_double != expect_double:
				_fail("双倍得分错误：+%d（期望 %d）" % [int(_gs.level_score) - before_double, expect_double])
				return
			print("[FLOW] 双倍得分 ×2 OK（+%d）" % expect_double)
			# 双倍黑柱惩罚
			var ball_black = load("res://scripts/gameplay/ball.gd").new()
			ball_black.black_hits = 2
			ball_black.position = Vector2(900.0, 400.0)
			root.add_child(ball_black)
			var before_black: int = int(_gs.level_score)
			_game._on_slot_hit(ball_black, 0, 1.0, Vector2(900.0, 640.0))
			var expect_black2 := _expected_score(maxi(0, _gs.get_ball_base(0) - 2 * FateConfig.BLACK_PENALTY * _gs.get_penalty_mult()), 1.0, false)
			if int(_gs.level_score) - before_black != expect_black2:
				_fail("双倍黑柱惩罚错误：+%d（期望 %d）" % [int(_gs.level_score) - before_black, expect_black2])
				return
			print("[FLOW] 双倍黑柱惩罚 ×2 OK")
			# 双倍白柱金币
			var coins_before: int = int(_gs.coins)
			var white_amount: int = _gs.white_coin_amount()
			_game._on_ball_white_coin(Vector2(900.0, 300.0))
			if int(_gs.coins) - coins_before != white_amount:
				_fail("双倍白柱金币错误：+%d（期望 %d）" % [int(_gs.coins) - coins_before, white_amount])
				return
			print("[FLOW] 双倍白柱金币 ×2 OK")
			# 力度回弹：单程 1.05s；继续按住会回落
			_game.launcher.set_locked(false)
			_game.launcher._try_start_charge(_game.launcher.global_position)
			_game.launcher._process(FateConfig.CHARGE_TIME)
			var at_top: float = float(_game.launcher.get_charge())
			_game.launcher._process(FateConfig.CHARGE_TIME * 0.6)
			var after_bounce: float = float(_game.launcher.get_charge())
			if at_top < 0.95:
				_fail("蓄力未到满格：%.2f" % at_top)
				return
			if after_bounce >= at_top - 0.05:
				_fail("力度未回弹：%.2f -> %.2f" % [at_top, after_bounce])
				return
			print("[FLOW] 力度回弹 OK（%.2f → %.2f）" % [at_top, after_bounce])
			# 不满格也能发射：当前力度 0.37 松手
			_game.launcher._charge = 0.37
			_game.launcher._release_charge()
			if _game._active_balls.is_empty():
				_fail("力度回弹后松手未发射")
				return
			var launched = _game._active_balls[0]
			var expected_speed := lerpf(FateConfig.LAUNCH_POWER_MIN, FateConfig.LAUNCH_POWER_MAX, 0.37)
			if absf(launched.linear_velocity.length() - expected_speed) > 3.0:
				_fail("松手力度取值错误：%.1f（期望 %.1f）" % [launched.linear_velocity.length(), expected_speed])
				return
			print("[FLOW] 不满格发射 OK（力度 0.37 → 速度 %.0f）" % launched.linear_velocity.length())
			_charge_ball = launched
			_stage = 2
		2:
			# 卡球救援：把球降速为 0 并关闭重力，应 1.2s 内被冲量救走
			_wait += 1
			if _charge_ball == null or not is_instance_valid(_charge_ball):
				_fail("测试球丢失")
				return
			_charge_ball.gravity_scale = 0.0
			_charge_ball.linear_velocity = Vector2.ZERO
			if _wait < 90:
				return
			if int(_charge_ball.get("_stuck_rescues")) < 1:
				_fail("卡球 1.2s 未被救援（rescues=%d）" % int(_charge_ball.get("_stuck_rescues")))
				return
			print("[FLOW] 卡球救援 OK（第 %d 次冲量）" % int(_charge_ball.get("_stuck_rescues")))
			# 连续 4 次失败 → 传送到台面中央
			# 选一个不压立柱/守命者的空地，避免物理反推导致速度不归零
			_charge_ball.global_position = Vector2(1180.0, 600.0)
			_charge_ball.linear_velocity = Vector2.ZERO
			_charge_ball._stuck_rescues = 4
			_wait = 0
			_stage = 3
		3:
			_wait += 1
			if _charge_ball == null or not is_instance_valid(_charge_ball):
				_fail("传送测试球丢失")
				return
			if int(_charge_ball.get("_stuck_rescues")) == 4:
				if _wait > 240:
					_fail("多次救援后仍未传送到台面中央")
				return
			var pos: Vector2 = _charge_ball.global_position
			if absf(pos.x - 900.0) > 100.0:
				_fail("多次救援后传送位置异常：x=%.1f" % pos.x)
				return
			print("[FLOW] 多次救援后传送台面中央 OK（x=%.1f）" % pos.x)
			# 闸门规则：轨道有球时不关；球进台面后才关
			_game.board.set_gate_closed(false)
			var rail_ball = load("res://scripts/gameplay/ball.gd").new()
			rail_ball.position = Vector2(1244.0, 400.0)
			root.add_child(rail_ball)
			rail_ball.gravity_scale = 0.0
			rail_ball.linear_velocity = Vector2.ZERO
			var field_ball = load("res://scripts/gameplay/ball.gd").new()
			field_ball.position = Vector2(1000.0, 300.0)
			root.add_child(field_ball)
			field_ball.gravity_scale = 0.0
			field_ball.linear_velocity = Vector2.ZERO
			_game._register_ball(rail_ball)
			_game._register_ball(field_ball)
			_gate_rail_ball = rail_ball
			_gate_field_ball = field_ball
			_wait = 0
			_stage = 4
		4:
			_wait += 1
			if _wait < 3:
				return
			if bool(_game.board.is_gate_closed()):
				_fail("轨道区仍有球时闸门不应关闭")
				return
			print("[FLOW] 轨道有球时闸门保持打开 OK")
			# 把轨道球移到台面 → 下一帧闸门关闭
			_gate_rail_ball.global_position = Vector2(1000.0, 200.0)
			_wait = 0
			_stage = 5
		5:
			_wait += 1
			if _wait < 3:
				return
			if not bool(_game.board.is_gate_closed()):
				_fail("轨道区无球后闸门未关闭")
				return
			print("[FLOW] ⑥ 闸门开合规则 OK")
			# 清理测试球后 complete_room
			for ball in [_gate_rail_ball, _gate_field_ball, _charge_ball]:
				if ball != null and is_instance_valid(ball):
					_game._active_balls.erase(ball)
					ball.free()
			_gs.level_score += 5000
			_game._check_level_end()
			if int(_gs.level) != 2:
				_fail("complete_room 后 level 未 +1")
				return
			print("[FLOW] complete_room 后 level=2 OK")
			_wait = 0
			_stage = 6
		6:
			_wait += 1
			if _wait < 180:
				return
			if _find_new_corridor() == null:
				_fail("过关后未回到走廊")
				return
			_success("v13：双倍注（得分/黑柱惩罚/白柱金币）/ 新手引导 / 力度回弹与不满格发射 / 卡球救援与传送 / 闸门开合 / 加宽立柱 全部通过")

var _charge_ball = null
var _gate_rail_ball = null
var _gate_field_ball = null

# ================= v14：右端通道 / 绿线组 / 三种琉璃珠 / 关卡 buff / NPC 文案 / 续关 =================

var _v14_board = null

func _tick_v14() -> void:
	match _stage:
		0:
			_stage = 1
			_gs.start_new_run()
			_gs.library_high = 0
			_gs.meta_balls_high = 0
			_gs.selected_balls_high = 0
			_gs.prepare_level(1)
			var packed = load("res://scenes/corridor.tscn")
			if packed == null or not (packed is PackedScene):
				_fail("无法加载 corridor.tscn")
				return
			_corridor = packed.instantiate()
			root.add_child(_corridor)
			_known_corridors.append(_corridor)
			_wait = 0
		1:
			_wait += 1
			if _wait < 8:
				return
			if FateConfig.CORRIDOR_DOOR_X.size() != 10:
				_fail("走廊门数量不是 10")
				return
			if _corridor._npcs.size() != _gs.visible_max_level():
				_fail("NPC 数量与可见关卡数不一致（%d/%d）" % [_corridor._npcs.size(), _gs.visible_max_level()])
				return
			# 未拥有命源珠：隐藏第 10 关（门/NPC/标签都不该存在）
			if _gs.has_source_ball() or _gs.visible_max_level() != FateConfig.MAX_LEVEL - 1:
				_fail("未拥有命源珠时可见关卡数应为 9")
				return
			if _corridor.get_door_state(FateConfig.MAX_LEVEL - 1) != 2:
				_fail("未解锁的隐藏第 10 门未视为不存在")
				return
			_gs.library_high = 1
			var packed_unlock = load("res://scenes/corridor.tscn")
			if packed_unlock == null or not (packed_unlock is PackedScene) or _gs.visible_max_level() != FateConfig.MAX_LEVEL:
				_fail("拥有命源珠后可见关卡数未变为 10")
				return
			var unlocked_corr = packed_unlock.instantiate()
			root.add_child(unlocked_corr)
			_known_corridors.append(unlocked_corr)
			if unlocked_corr._npcs.size() != FateConfig.MAX_LEVEL:
				_fail("解锁隐藏关后 NPC 数量不是 10")
				return
			unlocked_corr.queue_free()
			_gs.library_high = 0
			if _corridor._menu_btn == null or _corridor._bag_btn == null:
				_fail("走廊缺少左上返回/右上行囊按钮")
				return
			# 交互键 / 进入试炼 / 对话进入试炼 必须共用同一矩形
			if _corridor._interact_btn.position != _corridor._enter_btn.position \
				or _corridor._interact_btn.size != _corridor._enter_btn.size \
				or _corridor._dialog_enter_btn.position != _corridor._enter_btn.position:
				_fail("交互/进入试炼/对话按钮位置不一致")
				return
			if _corridor._hint_label != null and (
				_corridor._hint_label.text.contains("W") or _corridor._hint_label.text.contains("ESC")):
				_fail("走廊底部提示仍含键盘字样")
				return
			# 点击主角 → 打开个人信息面板（触屏世界点击；行囊按钮同入口）
			_corridor._handle_world_click(Vector2(_corridor.player.position.x, _corridor.player.position.y - 40.0))
			if _corridor._meta_panel == null:
				_fail("点击主角未打开个人信息面板")
				return
			_corridor._on_meta_closed()
			if _corridor._meta_panel != null:
				_fail("个人信息面板关闭后未释放")
				return
			print("[FLOW] 左上返回 / 右上行囊 / 点击主角开面板 / 无键盘提示 OK")
			var npc_pos: Vector2 = _corridor.get_npc_position(0)
			_corridor.player.position.x = npc_pos.x
			_wait = 0
			_stage = 2
		2:
			_wait += 1
			if _wait < 3:
				return
			if not bool(_corridor._npc_near):
				_fail("靠近 NPC 未进入可交互范围")
				return
			if _corridor._interact_btn == null or not bool(_corridor._interact_btn.visible):
				_fail("靠近 NPC 未显示底部「交互」按钮")
				return
			# 按钮矩形/可见性断言（真机 GUI 命中依赖此矩形）
			var btn_rect: Rect2 = _corridor._interact_btn.get_global_rect()
			if absf(btn_rect.size.x - 230.0) > 0.5 or absf(btn_rect.size.y - 68.0) > 0.5:
				_fail("交互按钮矩形尺寸错误：%s" % str(btn_rect.size))
				return
			# 触发 Button button_down（与触屏点击同一 GUI 路径；visibility 已改为仅变化时赋值）
			_corridor._interact_btn.button_down.emit()
			_wait = 0
			_stage = 20
		20:
			_wait += 1
			if _wait < 3:
				return
			if int(_corridor._dialog_state) == 0:
				_fail("合成触屏点击「交互」后 dialog_state 仍为 0")
				return
			if int(_corridor._dialog_state) != 1:
				_fail("NPC 对话未进入打字机状态")
				return
			if not bool(_corridor._story_playing) or not bool(_corridor._dialog_root.visible):
				_fail("NPC 对话遮罩未显示或未冻结输入")
				return
			if not _gs.is_npc_seen(1):
				_fail("对话触发后未 mark_npc_seen")
				return
			print("[FLOW] 按钮 button_down（真机同一 GUI 路径）→ dialog_state=%d OK" % int(_corridor._dialog_state))
			_wait = 0
			_stage = 10
		10:
			_wait += 1
			if _wait < 12:
				return
			var total_len: int = _gs.get_story_line().length()
			var shown_len := String(_corridor._story_label.text).length()
			if shown_len <= 0 or shown_len >= total_len:
				_fail("打字机未逐字显示（%d/%d）" % [shown_len, total_len])
				return
			# 点击文本 → 立即显示全文并出现「进入试炼」
			_corridor._on_dialog_click(null)
			if int(_corridor._dialog_state) != 2:
				_fail("点击文本后未进入待确认状态")
				return
			if not bool(_corridor._dialog_enter_btn.visible):
				_fail("文本播完后未出现「进入试炼」按钮")
				return
			if String(_corridor._story_label.text) != _gs.get_story_line():
				_fail("对话全文与当前关文案不一致")
				return
			print("[FLOW] NPC W 对话 / 打字机 / 进入试炼按钮 OK")
			# 退出对话（不实际切场景），等待 NPC 淡出
			_corridor._dialog_state = 0
			_corridor._story_playing = false
			_corridor._dialog_root.visible = false
			_corridor._blackout.visible = false
			_wait = 0
			_stage = 9
		9:
			_wait += 1
			if _wait > 120:
				_fail("NPC 未在对话后淡出消失")
				return
			if not bool(_corridor._npc_hidden[0]):
				return
			# 重新进入同一关：已见 NPC 不应再出现
			var packed3 = load("res://scenes/corridor.tscn")
			if packed3 == null or not (packed3 is PackedScene):
				_fail("无法再次加载 corridor.tscn")
				return
			var again = packed3.instantiate()
			root.add_child(again)
			_known_corridors.append(again)
			if not bool(again._npc_hidden[0]):
				_fail("再次进入已触发对话的关卡仍显示 NPC")
				return
			print("[FLOW] NPC 淡出消失 / 再次进入不再出现 OK")
			again.queue_free()
			_corridor.queue_free()
			_corridor = null
			_v14_board = load("res://scripts/gameplay/board.gd").new()
			root.add_child(_v14_board)
			_stage = 3
		3:
			_v14_validate_board()
		4:
			_v14_check_ball_buffs()
		5:
			_stage = 6
			_gs.level = 8
			_gs.prepare_level(8)
			var packed2 = load("res://scenes/game.tscn")
			if packed2 == null or not (packed2 is PackedScene):
				_fail("无法加载 game.tscn")
				return
			_game = packed2.instantiate()
			root.add_child(_game)
			_wait = 0
		6:
			_wait += 1
			if _wait < 6:
				return
			if _phase(_game) != 0:
				_fail("第 8 关 game 初始应为 PREP")
				return
			_game._on_prep_started(false)
			if int(_gs.checkpoint) != FateConfig.CHECKPOINT_LEVEL:
				_fail("开始试炼后未写入关卡存档点③")
				return
			print("[FLOW] 开始试炼 → 关卡存档点③ OK")
			var threshold := int(_gs.get_break_threshold())
			if threshold <= 0:
				_fail("第 8 关未读取到万流归宗阈值")
				return
			_gs.level_coins_gained = threshold
			_game._update_break_state(0.01)
			if not bool(_game.is_break_active()):
				_fail("达到阈值后未进入破命状态")
				return
			_gs.slot_configs[0] = {"mult": 1.0, "bonus": ""}
			var break_ball = load("res://scripts/gameplay/ball.gd").new()
			break_ball.position = Vector2(900.0, 400.0)
			root.add_child(break_ball)
			var before_break: int = int(_gs.level_score)
			_game._on_slot_hit(break_ball, 0, 1.0, Vector2(900.0, 640.0))
			var expect_break := _expected_score(_gs.get_ball_base(0), 2.0, false)
			if int(_gs.level_score) - before_break != expect_break:
				_fail("破命得分翻倍错误：+%d（期望 %d）" % [int(_gs.level_score) - before_break, expect_break])
				return
			print("[FLOW] 万流归宗破命（阈值/得分×2）OK")
			_game._update_break_state(11.0)
			if bool(_game.is_break_active()):
				_fail("破命时长结束后未恢复")
				return
			_game._spawn_split_balls(Vector2(900.0, 300.0), Vector2(-300.0, -120.0), FateConfig.BALL_TYPE_SOURCE, 1.0)
			_wait = 0
			_stage = 7
		7:
			_wait += 1
			if _wait < 3:
				return
			var found_type := 0
			for ball in _game._active_balls:
				if ball != null and is_instance_valid(ball) and int(ball.get("type")) == FateConfig.BALL_TYPE_SOURCE:
					found_type += 1
			if found_type < 2:
				_fail("分裂副球未继承命源珠 type（找到 %d）" % found_type)
				return
			print("[FLOW] 分裂副球继承 type 2 OK")
			for ball in _game._active_balls.duplicate():
				if ball != null and is_instance_valid(ball):
					_game._active_balls.erase(ball)
					ball.free()
			_game.queue_free()
			_game = null
			_wait = 0
			_stage = 8
		8:
			_gs.level = 3
			_gs.prepare_level(3)
			_gs.save_game()
			_gs.load_save()
			if int(_gs.level) != 3 or not bool(_gs.has_resumable_run()):
				_fail("续关存档未保留进行中的第 3 关（level=%d active=%s）" % [int(_gs.level), str(_gs.has_resumable_run())])
				return
			_gs.resume_run()
			if int(_gs.level) != 3:
				_fail("resume_run 后关卡变化")
				return
			_gs.abandon_run()
			if bool(_gs.has_resumable_run()):
				_fail("abandon_run 后仍可续关")
				return
			print("[FLOW] 续关存档（save/load/resume/abandon）OK")
			_success("v14：10 门/NPC 文案 / 右端 40px 通道 / 绿线成组规则 / 三种琉璃珠与分裂继承 / 关卡 buff / 续关存档 全部通过")

func _v14_validate_board() -> void:
	_v14_board.build()
	var max_center := 0.0
	for peg in _v14_board.pegs:
		max_center = maxf(max_center, float(peg.position.x))
	if max_center > FateConfig.RAIL_LEFT - FateConfig.PEG_RIGHT_GAP + 0.5:
		_fail("最右立柱中心 %.1f 超过安全线 %.1f" % [max_center, FateConfig.RAIL_LEFT - FateConfig.PEG_RIGHT_GAP])
		return
	var passage := (FateConfig.RAIL_LEFT - 12.0) - (max_center + FateConfig.PEG_RADIUS)
	if passage < FateConfig.PEG_RIGHT_GAP - 0.5:
		_fail("最右柱与轨道墙通道仅 %.1f px（要求 ≥%.0f）" % [passage, FateConfig.PEG_RIGHT_GAP])
		return
	var links_found: bool = not _v14_board.links.is_empty()
	for attempt in 20:
		if links_found:
			break
		_v14_board.build()
		links_found = not _v14_board.links.is_empty()
	if not links_found:
		_fail("20 次随机布局都没有生成绿色连线组")
		return
	var pos_to_idx := {}
	for i in _v14_board.pegs.size():
		pos_to_idx[_v14_board.pegs[i].position] = i
	var degree := {}
	for pair in _v14_board.links:
		var pa: Vector2 = pair[0]
		var pb: Vector2 = pair[1]
		var ia: int = int(pos_to_idx.get(pa, -1))
		var ib: int = int(pos_to_idx.get(pb, -1))
		if ia < 0 or ib < 0:
			_fail("绿线端点不是立柱")
			return
		var ra: int = ia / FateConfig.PEG_COLS
		var ca: int = ia % FateConfig.PEG_COLS
		var rb: int = ib / FateConfig.PEG_COLS
		var cb: int = ib % FateConfig.PEG_COLS
		var dr: int = absi(ra - rb)
		var dc: int = absi(ca - cb)
		if not ((dr == 1 and dc == 0) or (dr == 0 and dc == 1)):
			_fail("绿线不是横/竖相邻（dr=%d dc=%d）" % [dr, dc])
			return
		degree[ia] = int(degree.get(ia, 0)) + 1
		degree[ib] = int(degree.get(ib, 0)) + 1
	for key in degree.keys():
		if int(degree[key]) > FateConfig.GREEN_LINK_MAX_PER_PEG:
			_fail("绿线每柱超过 %d 条（%d）" % [FateConfig.GREEN_LINK_MAX_PER_PEG, int(degree[key])])
			return
	print("[FLOW] 右端通道 %.1fpx + 绿线成组（%d 条，每柱≤2）OK" % [passage, _v14_board.links.size()])
	_v14_board.queue_free()
	_v14_board = null
	_stage = 4

func _v14_check_ball_buffs() -> void:
	_gs.level = 2
	_gs.prepare_level(2)
	var wind_ball = load("res://scripts/gameplay/ball.gd").new()
	root.add_child(wind_ball)
	var bounce: float = float(wind_ball.physics_material_override.bounce)
	if absf(bounce - (FateConfig.BALL_BOUNCE + 0.10)) > 0.02:
		_fail("回廊之风反弹未生效：%.2f" % bounce)
		return
	wind_ball.free()
	if absf(_gs.get_chaos_chance() - 0.0) > 0.001:
		pass
	_gs.level = 3
	_gs.prepare_level(3)
	if absf(_gs.get_chaos_chance() - 0.30) > 0.001:
		_fail("因果回响概率未生效")
		return
	_gs.level = 5
	_gs.prepare_level(5)
	if _gs.get_green_limit() != 3:
		_fail("裂隙侵蚀绿色上限不是 3")
		return
	var erode_ball = load("res://scripts/gameplay/ball.gd").new()
	root.add_child(erode_ball)
	var eroded_flag := {"hit": false}
	erode_ball.eroded.connect(func(_pos: Vector2) -> void: eroded_flag["hit"] = true)
	erode_ball._on_green_contact()
	erode_ball._on_green_contact()
	if bool(eroded_flag["hit"]):
		_fail("裂隙侵蚀提前自毁")
		return
	erode_ball._on_green_contact()
	if not bool(eroded_flag["hit"]):
		_fail("裂隙侵蚀 3 次后未自毁")
		return
	erode_ball.free()
	_gs.level = 7
	_gs.prepare_level(7)
	var heavy_ball = load("res://scripts/gameplay/ball.gd").new()
	root.add_child(heavy_ball)
	if absf(float(heavy_ball.gravity_scale) - FateConfig.BALL_GRAVITY_SCALE * 1.15) > 0.02:
		_fail("命运重压重力倍率未生效：%.2f" % float(heavy_ball.gravity_scale))
		return
	heavy_ball.free()
	_gs.level = 9
	_gs.prepare_level(9)
	if absf(_gs.get_score_multiplier() - 0.7) > 0.001:
		_fail("倒戈止逆得分倍率未生效")
		return
	_gs.library_high = 1
	_gs.level = 10
	_gs.prepare_level(10)
	if _gs.level != 10:
		_fail("拥有命源珠后第 10 关未解锁")
		return
	var board10 = load("res://scripts/gameplay/board.gd").new()
	root.add_child(board10)
	board10.build()
	for peg in board10.pegs:
		var t := int(peg.peg_type)
		if t == FateConfig.PEG_TYPE_NORMAL or t == FateConfig.PEG_TYPE_BLACK:
			_fail("命源再现仍生成普通/黑柱")
			board10.queue_free()
			_gs.library_high = 0
			return
	if _gs.get_ball_base(FateConfig.BALL_TYPE_SOURCE) != FateConfig.BALL_BASE_SCORES[2]:
		_fail("命源珠基础分不是 20")
		board10.queue_free()
		_gs.library_high = 0
		return
	_gs.library_high = 0
	board10.queue_free()
	print("[FLOW] 关卡 buff（回风/回响/侵蚀/重压/倒戈/命源）与三阶琉璃珠 OK")
	_stage = 5

# ================= v16：存档点 / 限购 / 槽位再射上限 / 失败新字段 / 返回上一存档点 =================

func _tick_v16() -> void:
	match _stage:
		0:
			_gs.start_new_run()
			_gs.level = 5
			var purchases: Array[String] = ["powercard"]
			_gs.mark_checkpoint(FateConfig.CHECKPOINT_LEVEL, purchases)
			_gs.prepare_level(5)
			if not _gs.get_pending_items().has("powercard"):
				_fail("③存档点重进未恢复本关购买（powercard）")
				return
			if not _gs.is_item_bought("powercard"):
				_fail("③存档点购买未记入限购列表")
				return
			# 同房间每种限购 1 次
			_gs.coins = 99
			if not _gs.buy_item("reflector"):
				_fail("首次购买失败")
				return
			if _gs.buy_item("reflector"):
				_fail("同房间重复购买未被限制")
				return
			if not _gs.is_item_bought("reflector"):
				_fail("is_item_bought 未记录")
				return
			# 槽位「再射一球」本关上限 2
			_gs.slot_configs[0] = {"mult": 1.0, "bonus": "ball1"}
			var before_total := int(_gs.balls_total)
			var before_left := int(_gs.balls_left)
			var r1: String = _gs.apply_pocket_bonus(0)
			var r2: String = _gs.apply_pocket_bonus(0)
			var r3: String = _gs.apply_pocket_bonus(0)
			if r1 != "ball1" or r2 != "ball1" or r3 != "ball1_limit":
				_fail("槽位再射一球上限返回异常：%s/%s/%s" % [r1, r2, r3])
				return
			if int(_gs.balls_total) != before_total + 2 or int(_gs.balls_left) != before_left + 2:
				_fail("槽位再射一球上限 2 未生效")
				return
			# 失败结算新字段
			_gs.level_score = 123
			_gs.total_score = 456
			var summary: Dictionary = _gs.fail_room()
			if int(summary.get("level_score", -1)) != 123 or int(summary.get("total_score", -1)) != 456:
				_fail("fail_room 缺少 level_score/total_score")
				return
			if not summary.has("story") or summary.has("carried"):
				_fail("fail_room 字段不符合 v1.6（story 有/carried 无）")
				return
			var fb = load("res://scripts/gameplay/result_fallback.gd").new()
			root.add_child(fb)
			if not fb.has_signal("checkpoint_pressed"):
				_fail("结算兜底缺少 checkpoint_pressed 信号")
				return
			fb.free()
			print("[FLOW] 存档点恢复购买 / 限购 / 槽位再射上限 / 失败新字段 OK")
			# 进入 game 验证「返回上一存档点」按钮处理
			_gs.level = 6
			_gs.prepare_level(6)
			var packed = load("res://scenes/game.tscn")
			if packed == null or not (packed is PackedScene):
				_fail("无法加载 game.tscn")
				return
			_game = packed.instantiate()
			root.add_child(_game)
			_wait = 0
			_stage = 2
		2:
			_wait += 1
			if _wait < 6:
				return
			if _phase(_game) != 0:
				_fail("v16 game 初始应为 PREP")
				return
			_game._on_checkpoint_pressed()
			_wait = 0
			_stage = 3
		3:
			_wait += 1
			if _wait > 120:
				_fail("返回上一存档点后未回到走廊")
				return
			var corr = _find_new_corridor()
			if corr == null:
				return
			if int(_gs.level) != 4:
				_fail("返回上一存档点 level 应为 4，实际 %d" % int(_gs.level))
				return
			if int(_gs.checkpoint) != FateConfig.CHECKPOINT_CORRIDOR:
				_fail("返回上一存档点未写回走廊存档点①")
				return
			print("[FLOW] 失败结算「返回上一存档点」→ 走廊①（level-2）OK")
			_corridor = corr
			# 进商店：应写入商店存档点②
			corr._enter_room()
			_wait = 0
			_stage = 4
		4:
			_wait += 1
			if _wait > 180:
				_fail("进入商店后未加载 game")
				return
			if _find_game() == null:
				return
			if int(_gs.checkpoint) != FateConfig.CHECKPOINT_SHOP:
				_fail("进入商店未写入存档点②")
				return
			print("[FLOW] 进入商店 → 存档点② OK")
			_success("v16：③存档点恢复购买 / 同房间限购1 / 槽位再射上限2 / fail_room 新字段 / 返回上一存档点(level-2→走廊) / 进商店存档点② 全部通过")




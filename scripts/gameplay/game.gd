extends Node2D
## 《！？珠珠？！》v1.3 房间玩法主流程（game.tscn 根节点脚本）。
##
## 流程状态机：
##   PREP（准备阶段：上方商店 + 下方牌组，HUD 隐藏，结束时选择是否双倍注）
##   → PLAY（正式游玩，右侧弹簧发射）→ TRANSITION → 回走廊 / RESULT
##
## 台面/弹簧/球/守命者分别在 board.gd / launcher.gd / ball.gd / guardian.gd。
## UI（hud/prep/tutorial/result）由 ui-dev 提供，全部运行时 load() 并做接口校验，
## 缺失/不兼容时用内置兜底。双倍注与新手引导在本文件接入。

const BOARD_SCRIPT := preload("res://scripts/gameplay/board.gd")
const LAUNCHER_SCRIPT := preload("res://scripts/gameplay/launcher.gd")
const BALL_SCRIPT := preload("res://scripts/gameplay/ball.gd")
const FX_SCRIPT := preload("res://scripts/gameplay/fx.gd")
const HUD_FALLBACK := preload("res://scripts/gameplay/hud_fallback.gd")
const RESULT_FALLBACK := preload("res://scripts/gameplay/result_fallback.gd")

const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const PREP_SCENE_PATH := "res://scenes/ui/prep.tscn"
const TUTORIAL_SCENE_PATH := "res://scenes/ui/tutorial.tscn"
const RESULT_SCENE_PATH := "res://scenes/ui/result.tscn"
const CORRIDOR_SCENE_PATH := "res://scenes/corridor.tscn"
const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"

## 流程阶段（数值与 v1.1 保持一致：0=PREP/旧SHOP，1=PLAY，2=RESULT，3=TRANSITION）
enum Phase { PREP, PLAY, RESULT, TRANSITION }

var phase: int = Phase.PREP
var board = null
var launcher = null
var hud = null
var fx = null
var camera: Camera2D = null

var _active_balls: Array = []
var _hud_layer: CanvasLayer = null
var _ui_layer: CanvasLayer = null
var _prep_layer: CanvasLayer = null
var _prep_root = null
var _prep_offers: Array[String] = []
var _prep_buttons: Array = []
var _prep_coins_label: Label = null
var _prep_error_label: Label = null
var _tutorial_layer: CanvasLayer = null
var _tutorial_root = null
var _overlay_root: Node = null
var _level_resolved := false
var _result_victory := false
var _refresh_timer := 0.0

# ================= 生命周期 =================

func _ready() -> void:
	randomize()
	_setup_camera()
	fx = FX_SCRIPT.new()
	add_child(fx)
	fx.setup(camera)
	board = BOARD_SCRIPT.new()
	board.setup(fx)
	add_child(board)
	board.connect("slot_hit", Callable(self, "_on_slot_hit"))
	launcher = LAUNCHER_SCRIPT.new()
	launcher.setup(fx)
	add_child(launcher)
	launcher.connect("launch_requested", Callable(self, "_on_launch_requested"))
	launcher.set_locked(true)
	_setup_hud()
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.score_changed.connect(_on_score_changed)
	GameState.balls_changed.connect(_on_balls_changed)
	GameState.items_changed.connect(_on_items_changed)
	GameState.library_changed.connect(_on_library_changed)
	# 兜底：直接启动 game.tscn（调试/重试漏 prepare）时补一次本关准备
	if GameState.ball_slots.is_empty() or GameState.slot_configs.is_empty():
		GameState.prepare_level(GameState.level)
	board.build()
	board.set_gate_closed(false)
	_enter_prep()

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.2:
		_refresh_timer = 0.0
		_refresh_hud()
		if phase == Phase.PREP:
			_refresh_prep_ui()
	# ⑥ 运动改变区：只有在「台面有球、且轨道区 x>1216 没有球」时才关闸；
	# 若台面球与轨道球同时存在，先把轨道内的球向左推，避免闸门夹球。
	if phase == Phase.PLAY and not bool(board.is_gate_closed()):
		var has_playfield := false
		var rail_balls: Array = []
		for ball in _active_balls:
			if ball == null or not is_instance_valid(ball):
				continue
			if float(ball.global_position.x) > FateConfig.RAIL_LEFT:
				rail_balls.append(ball)
			else:
				has_playfield = true
		if has_playfield and rail_balls.is_empty():
			board.set_gate_closed(true)
		elif has_playfield:
			for ball in rail_balls:
				if float(ball.global_position.y) < 260.0:
					ball.linear_velocity.x = -520.0
	if phase == Phase.PLAY:
		_check_level_end()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_goto_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_goto_menu()
			get_viewport().set_input_as_handled()

# ================= 场景骨架 =================

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = FateConfig.VIEW_SIZE * 0.5
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	add_child(camera)
	camera.make_current()

func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)
	var instance = _instantiate_scene(HUD_SCENE_PATH)
	var compatible := instance != null \
		and instance.has_method("set_phase") \
		and instance.has_method("refresh") \
		and instance.has_signal("equip_requested")
	if compatible:
		hud = instance
	else:
		if instance != null:
			instance.free()
		hud = HUD_FALLBACK.new()
	_hud_layer.add_child(hud)
	if hud.has_signal("exit_pressed"):
		hud.connect("exit_pressed", Callable(self, "_on_exit_pressed"))
	if hud.has_signal("equip_requested"):
		hud.connect("equip_requested", Callable(self, "_on_equip_requested"))
	if hud.has_method("set_game"):
		hud.call("set_game", self)
	if hud.has_method("set_phase"):
		hud.call("set_phase", 0)

func _instantiate_scene(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		return null
	return (packed as PackedScene).instantiate()

func _ensure_ui_layer() -> CanvasLayer:
	if _ui_layer == null:
		_ui_layer = CanvasLayer.new()
		_ui_layer.layer = 20
		add_child(_ui_layer)
	return _ui_layer

func _close_overlay() -> void:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.queue_free()
	_overlay_root = null

# ================= PREP 准备阶段 =================

func _enter_prep() -> void:
	phase = Phase.PREP
	_level_resolved = false
	_cleanup_active_balls()
	if hud != null:
		hud.visible = false
	if launcher != null:
		launcher.set_locked(true)
	Audio.play_bgm("menu")
	_prep_offers = _roll_offers()
	_open_prep_ui()

## 房间开始时抽取 3 件商店货品
func _roll_offers() -> Array[String]:
	var pool: Array[String] = []
	for id in FateConfig.ITEMS.keys():
		pool.append(String(id))
	var offers: Array[String] = []
	while offers.size() < FateConfig.SHOP_OFFER_COUNT and not pool.is_empty():
		var idx := randi() % pool.size()
		offers.append(pool[idx])
		pool.remove_at(idx)
	return offers

func _open_prep_ui() -> void:
	_prep_layer = CanvasLayer.new()
	_prep_layer.layer = 30
	add_child(_prep_layer)
	var scene = _instantiate_scene(PREP_SCENE_PATH)
	var compatible := scene != null and scene.has_method("open_prep") and scene.has_signal("start_pressed")
	if compatible:
		_prep_root = scene
		_prep_layer.add_child(scene)
		scene.connect("start_pressed", Callable(self, "_on_prep_started"))
		scene.call("open_prep", GameState.level, _prep_offers)
	else:
		if scene != null:
			scene.free()
		_build_prep_fallback()

## prep.tscn 缺失/不兼容时的内置简版：3 件货品购买 + 开始试炼
func _build_prep_fallback() -> void:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_prep_root = panel
	_prep_layer.add_child(panel)
	var theme := Theme.new()
	if fx != null and fx.has_method("ui_font"):
		theme.default_font = fx.ui_font()
	theme.default_font_size = 20
	panel.theme = theme
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.06, 0.92)
	bg.size = FateConfig.VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var title := Label.new()
	title.text = "命运回廊 · 准备阶段"
	title.position = Vector2(340.0, 24.0)
	title.size = Vector2(600.0, 44.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	panel.add_child(title)
	var info := Label.new()
	info.text = "第%d间「%s」｜目标 %d 分｜%s" % [
		GameState.level, GameState.get_level_name(), GameState.get_target(), GameState.get_level_buff_text()]
	info.position = Vector2(240.0, 72.0)
	info.size = Vector2(800.0, 30.0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	panel.add_child(info)
	if not GameState.fate_event.is_empty():
		var fate := Label.new()
		fate.text = "命运事件 · %s：%s" % [String(GameState.fate_event.get("name", "")), String(GameState.fate_event.get("desc", ""))]
		fate.position = Vector2(240.0, 102.0)
		fate.size = Vector2(800.0, 26.0)
		fate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fate.add_theme_font_size_override("font_size", 16)
		fate.add_theme_color_override("font_color", FateConfig.COLOR_VIOLET)
		panel.add_child(fate)
	_prep_coins_label = Label.new()
	_prep_coins_label.position = Vector2(20.0, 136.0)
	_prep_coins_label.size = Vector2(300.0, 30.0)
	_prep_coins_label.add_theme_font_size_override("font_size", 20)
	_prep_coins_label.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	panel.add_child(_prep_coins_label)
	var shop_title := Label.new()
	shop_title.text = "命运商店（点击购买，开局后不再出售）"
	shop_title.position = Vector2(340.0, 140.0)
	shop_title.size = Vector2(600.0, 28.0)
	shop_title.add_theme_font_size_override("font_size", 18)
	shop_title.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	panel.add_child(shop_title)
	_prep_buttons.clear()
	for i in _prep_offers.size():
		panel.add_child(_make_prep_row(_prep_offers[i], i))
	_prep_error_label = Label.new()
	_prep_error_label.position = Vector2(340.0, 520.0)
	_prep_error_label.size = Vector2(600.0, 30.0)
	_prep_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prep_error_label.add_theme_font_size_override("font_size", 18)
	_prep_error_label.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
	_prep_error_label.modulate.a = 0.0
	panel.add_child(_prep_error_label)
	var start_safe := Button.new()
	start_safe.text = "稳妥开局"
	start_safe.position = Vector2(440.0, 570.0)
	start_safe.size = Vector2(190.0, 64.0)
	start_safe.add_theme_font_size_override("font_size", 24)
	start_safe.pressed.connect(_on_prep_started.bind(false))
	panel.add_child(start_safe)
	var start_double := Button.new()
	start_double.text = "双倍押注"
	start_double.position = Vector2(650.0, 570.0)
	start_double.size = Vector2(190.0, 64.0)
	start_double.add_theme_font_size_override("font_size", 24)
	start_double.pressed.connect(_on_prep_started.bind(true))
	panel.add_child(start_double)
	_refresh_prep_ui()

func _make_prep_row(item_id: String, index: int) -> Control:
	var data: Dictionary = FateConfig.ITEMS.get(item_id, {})
	var row := HBoxContainer.new()
	row.position = Vector2(340.0, 176.0 + float(index) * 104.0)
	row.size = Vector2(600.0, 88.0)
	row.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = "%s\n[%s]" % [String(data.get("name", item_id)), String(data.get("tag", ""))]
	name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	row.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = String(data.get("desc", ""))
	desc_label.custom_minimum_size = Vector2(330.0, 0.0)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	row.add_child(desc_label)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(120.0, 60.0)
	buy.add_theme_font_size_override("font_size", 17)
	buy.text = "%d 金币" % int(data.get("cost", 0))
	buy.pressed.connect(_on_prep_buy.bind(item_id))
	row.add_child(buy)
	_prep_buttons.append({"id": item_id, "button": buy})
	return row

func _on_prep_buy(item_id: String) -> void:
	if GameState.buy_item(item_id):
		Audio.play_sfx("buy")
		_refresh_prep_ui()
	else:
		_show_prep_error("金币不足，命运拒绝了你")

func _refresh_prep_ui() -> void:
	if _prep_coins_label != null and is_instance_valid(_prep_coins_label):
		_prep_coins_label.text = "金币 %d  ｜  行囊带入卡 %d" % [GameState.coins, GameState.run_loadout_cards.size()]
	for entry in _prep_buttons:
		var button = entry.get("button")
		if button != null and is_instance_valid(button):
			button.disabled = not GameState.can_buy_item(String(entry.get("id", "")))

func _show_prep_error(text: String) -> void:
	if _prep_error_label == null or not is_instance_valid(_prep_error_label):
		return
	_prep_error_label.text = text
	_prep_error_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(_prep_error_label, "modulate:a", 0.0, 0.5)

func _on_prep_started(double_mode: bool = false) -> void:
	if phase != Phase.PREP:
		return
	# 双倍注：先写入 GameState，再进入正式游玩
	GameState.set_double_mode(double_mode)
	phase = Phase.PLAY
	if _prep_root != null and is_instance_valid(_prep_root):
		_prep_root.queue_free()
	_prep_root = null
	_prep_buttons.clear()
	_prep_coins_label = null
	_prep_error_label = null
	if _prep_layer != null:
		_prep_layer.queue_free()
		_prep_layer = null
	if hud != null:
		hud.visible = true
		if hud.has_method("set_phase"):
			hud.call("set_phase", 1)
		if hud.has_method("set_phase_hint"):
			var hint := "按住右下弹簧蓄力，松手发射（弹珠沿右侧轨道上行）"
			if GameState.double_mode:
				hint += "\n双倍注：得分/金币×2，黑柱惩罚×2，失败碎片减半"
			hud.call("set_phase_hint", hint)
		if hud.has_method("refresh"):
			hud.call("refresh")
	if launcher != null:
		launcher.set_locked(false)
	board.set_gate_closed(false)
	Audio.play_bgm("battle")
	_refresh_hud()
	# 新手引导：只在第一次进入 PLAY 时显示
	if GameState.should_show_tutorial():
		_show_tutorial()

# ================= 新手引导 =================

func _show_tutorial() -> void:
	if _tutorial_layer != null:
		return
	_tutorial_layer = CanvasLayer.new()
	_tutorial_layer.layer = 25
	add_child(_tutorial_layer)
	var scene = _instantiate_scene(TUTORIAL_SCENE_PATH)
	var compatible := scene != null and scene.has_method("show_tutorial") and scene.has_signal("closed")
	if compatible:
		_tutorial_root = scene
		_tutorial_layer.add_child(scene)
		scene.connect("closed", Callable(self, "_on_tutorial_closed"))
		scene.call("show_tutorial")
	else:
		if scene != null:
			scene.free()
		_tutorial_root = _build_tutorial_fallback()
		_tutorial_layer.add_child(_tutorial_root)

func _build_tutorial_fallback() -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, 0.78)
	bg.size = FateConfig.VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var box := ColorRect.new()
	box.position = Vector2(300.0, 180.0)
	box.size = Vector2(680.0, 360.0)
	box.color = Color(0.11, 0.08, 0.19, 0.98)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(box)
	var title := Label.new()
	title.text = "新手引导"
	title.position = Vector2(0.0, 18.0)
	title.size = Vector2(680.0, 40.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	box.add_child(title)
	var lines: Array[String] = [FateConfig.TUTORIAL_TEXT_1, FateConfig.TUTORIAL_TEXT_2, FateConfig.TUTORIAL_TEXT_3]
	for i in lines.size():
		var line := Label.new()
		line.text = "%d. %s" % [i + 1, lines[i]]
		line.position = Vector2(40.0, 90.0 + float(i) * 64.0)
		line.size = Vector2(600.0, 40.0)
		line.add_theme_font_size_override("font_size", 20)
		line.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
		box.add_child(line)
	var ok := Button.new()
	ok.text = "知道了"
	ok.position = Vector2(240.0, 288.0)
	ok.size = Vector2(200.0, 56.0)
	ok.add_theme_font_size_override("font_size", 22)
	ok.pressed.connect(_on_tutorial_closed)
	box.add_child(ok)
	return panel

func _on_tutorial_closed() -> void:
	if _tutorial_root != null and is_instance_valid(_tutorial_root):
		_tutorial_root.queue_free()
	_tutorial_root = null
	if _tutorial_layer != null:
		_tutorial_layer.queue_free()
		_tutorial_layer = null
	GameState.mark_tutorial_seen()

# ================= 装备拖拽落点 =================

func _on_equip_requested(item_id: String, screen_pos: Vector2) -> void:
	if phase != Phase.PLAY or board == null:
		return
	if not _active_balls.is_empty() or GameState.balls_left <= 0:
		_hud_error("弹珠飞行中，无法改造立柱")
		return
	var world_pos := screen_pos
	var vp := get_viewport()
	if vp != null:
		world_pos = vp.get_canvas_transform().affine_inverse() * screen_pos
	if not bool(board.equip_at(world_pos, item_id)):
		_hud_error("需要把装备拖到立柱上（距离 40px 内）")
		return
	if GameState.consume_pending_item(item_id):
		Audio.play_sfx("buy")
		if fx != null:
			fx.burst(world_pos, FateConfig.COLOR_GOLD, 10, 160.0)
		_refresh_hud()
	else:
		_hud_error("该道具已失效")

# ================= 发射阶段 =================

func _on_launch_requested(power_t: float) -> void:
	if phase != Phase.PLAY or not _active_balls.is_empty():
		return
	var info := GameState.take_next_ball()
	if info.is_empty():
		_hud_error("没有可用的弹珠了")
		return
	var card := String(info.get("card", ""))
	var ball = BALL_SCRIPT.new()
	ball.advanced = bool(info.get("advanced", false))
	ball.card = card
	ball.radius_scale = FateConfig.SHRINK_SCALE if card == "shrinkcard" else 1.0
	ball.position = FateConfig.LAUNCH_POS
	add_child(ball)
	_register_ball(ball)
	var speed := lerpf(FateConfig.LAUNCH_POWER_MIN, FateConfig.LAUNCH_POWER_MAX, clampf(power_t, 0.0, 1.0))
	match card:
		"powercard":
			speed *= 1.3
		"shrinkcard":
			speed *= FateConfig.SHRINK_SPEED_MULT
	ball.linear_velocity = Vector2(0.0, -speed)
	board.set_gate_closed(false)
	if launcher != null:
		launcher.set_locked(true)
	Audio.play_sfx("launch")
	if fx != null:
		fx.burst(ball.global_position, FateConfig.COLOR_GOLD, 12, 180.0)
		fx.shake(2.0, 0.12)
	_refresh_hud()

## 注册一颗场上的球（含分裂副球），统一连接信号
func _register_ball(ball: Node) -> void:
	_active_balls.append(ball)
	ball.connect("peg_hit", Callable(self, "_on_ball_peg_hit"))
	ball.connect("fell_out", Callable(self, "_on_ball_fell_out").bind(ball))
	ball.connect("white_coin", Callable(self, "_on_ball_white_coin"))
	ball.connect("stuck_at", Callable(self, "_on_ball_stuck"))
	ball.connect("split_requested", Callable(self, "_on_ball_split_requested").bind(ball))

func _on_ball_peg_hit(peg_type: int, world_pos: Vector2, equipped: String) -> void:
	var sfx := &"peg"
	var color := Color(0.75, 0.72, 0.85)
	match peg_type:
		FateConfig.PEG_TYPE_YELLOW:
			sfx = &"peg_yellow"
			color = FateConfig.COLOR_GOLD
		FateConfig.PEG_TYPE_GREEN:
			sfx = &"peg_green"
			color = FateConfig.COLOR_JADE
		FateConfig.PEG_TYPE_BLACK:
			sfx = &"crack"
			color = Color(0.55, 0.35, 0.95)
		FateConfig.PEG_TYPE_WHITE:
			sfx = &"peg"
			color = FateConfig.COLOR_WHITE_PEG
	Audio.play_sfx(sfx, -2.0, randf_range(0.92, 1.08))
	if fx != null:
		fx.burst(world_pos, color, 5, 130.0, 2.2, 240.0)
		if equipped != "":
			fx.burst(world_pos, color, 3, 90.0, 1.6, 160.0)
		if peg_type == FateConfig.PEG_TYPE_BLACK:
			fx.popup("-%d" % (FateConfig.BLACK_PENALTY * GameState.get_penalty_mult()), world_pos + Vector2(0.0, -18.0), Color(0.62, 0.42, 0.95), 22)
		elif peg_type == FateConfig.PEG_TYPE_WHITE:
			fx.burst(world_pos, Color(1.0, 1.0, 1.0), 4, 100.0, 1.8, 180.0)

func _on_ball_white_coin(world_pos: Vector2) -> void:
	# 白柱给币数量受双倍注影响（普通 1 / 双倍 2）
	var amount := GameState.white_coin_amount()
	GameState.add_coins(amount)
	Audio.play_sfx("coin")
	if fx != null:
		fx.popup("+%d 金币" % amount, world_pos + Vector2(0.0, -26.0), FateConfig.COLOR_GOLD, 24)
	_refresh_hud()

func _on_ball_stuck(world_pos: Vector2) -> void:
	Audio.play_sfx("guardian", -4.0)
	if fx != null:
		fx.burst(world_pos, FateConfig.COLOR_JADE, 10, 120.0)
		fx.popup("黏住", world_pos + Vector2(0.0, -22.0), FateConfig.COLOR_JADE, 22)

## 分裂卡：撞到第一根柱子后由 ball 发出请求，这里生成 2 颗副球（共 3 颗）
## 信号参数顺序：split_requested(world_pos, velocity) + bind(ball)
## 注意：body_entered 处于物理查询 flush 中，不能立即 add_child 物理体，
## 因此用 call_deferred 延迟到帧末再生成副球。
func _on_ball_split_requested(world_pos: Vector2, velocity: Vector2, source_ball: Node) -> void:
	if source_ball == null or not is_instance_valid(source_ball):
		return
	call_deferred("_spawn_split_balls", world_pos, velocity,
		bool(source_ball.get("advanced")), float(source_ball.get("radius_scale")))

func _spawn_split_balls(world_pos: Vector2, velocity: Vector2, advanced: bool, radius_scale: float) -> void:
	var base_angle := velocity.angle()
	var speed := maxf(velocity.length() * 0.8, 260.0)
	for i in 2:
		var child = BALL_SCRIPT.new()
		child.advanced = advanced
		child.card = ""
		child.radius_scale = radius_scale
		child.position = world_pos + Vector2(0.0, 16.0 + float(i) * 16.0)
		add_child(child)
		_register_ball(child)
		var angle := base_angle + deg_to_rad(40.0) * (1.0 if i == 0 else -1.0)
		child.linear_velocity = Vector2(cos(angle), sin(angle)) * speed
	Audio.play_sfx("crack")
	if fx != null:
		fx.burst(world_pos, Color(1.0, 0.45, 0.48), 18, 240.0)
		fx.popup("分裂！", world_pos + Vector2(0.0, -30.0), Color(1.0, 0.45, 0.48), 24)
		fx.shake(3.0)

# ================= 单球结算 =================

func _on_slot_hit(ball: Node, slot_index: int, _mult: float, world_pos: Vector2) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	if bool(ball.get("settled")):
		return
	ball.set("settled", true)
	var advanced := bool(ball.get("advanced"))
	var card := String(ball.get("card"))
	var buffed := card != ""
	var yellow_hits := int(ball.get("yellow_hits"))
	var black_hits := int(ball.get("black_hits"))
	var base := GameState.get_ball_base(advanced)
	# 黑柱：每撞一次最终得分 -1（双倍注时惩罚×2，最低 0）
	if black_hits > 0:
		base = maxi(0, base - black_hits * FateConfig.BLACK_PENALTY * GameState.get_penalty_mult())
	# v1.2：倍率以 GameState 随机框配置为准
	var mult := GameState.get_pocket_mult(slot_index)
	var value := GameState.award_ball_score(base, yellow_hits, mult, buffed)
	var popup_pos := world_pos + Vector2(0.0, -40.0)
	if hud != null and hud.has_method("popup_score"):
		hud.call("popup_score", value, popup_pos)
	if mult <= 0.0:
		Audio.play_sfx("void")
		if fx != null:
			fx.popup("×0", popup_pos, FateConfig.COLOR_VIOLET, 28)
			fx.burst(world_pos, Color(0.35, 0.20, 0.60), 18, 260.0)
			fx.flash(Color(0.18, 0.05, 0.30), 0.25, 0.5)
			fx.shake(4.0)
	else:
		Audio.play_sfx("slot")
		if fx != null:
			var popup_color := FateConfig.COLOR_GOLD if value >= 20 else FateConfig.COLOR_TEXT
			fx.popup("+%d" % value, popup_pos, popup_color, 32)
			fx.burst(world_pos, FateConfig.COLOR_GOLD, 16, 280.0)
			if mult >= 1.5:
				fx.flash(FateConfig.COLOR_GOLD, 0.14, 0.4)
				fx.shake(3.0)
	# 随机框奖励：金币+2 / 再射一球（金币数受双倍注影响）
	var coins_before_bonus := GameState.coins
	var bonus := GameState.apply_pocket_bonus(slot_index)
	if bonus == "coin2":
		Audio.play_sfx("coin")
		if fx != null:
			fx.popup("金币 +%d" % maxi(GameState.coins - coins_before_bonus, 1), popup_pos + Vector2(0.0, -26.0), FateConfig.COLOR_GOLD, 22)
	elif bonus == "ball1":
		Audio.play_sfx("launch", -4.0)
		if fx != null:
			fx.popup("再射一球", popup_pos + Vector2(0.0, -26.0), FateConfig.COLOR_JADE, 22)
	_finish_ball(ball)

func _on_ball_fell_out(world_pos: Vector2, ball: Node) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	if bool(ball.get("settled")):
		return
	ball.set("settled", true)
	var base := GameState.get_ball_base(bool(ball.get("advanced")))
	var black_hits := int(ball.get("black_hits"))
	if black_hits > 0:
		base = maxi(0, base - black_hits * FateConfig.BLACK_PENALTY * GameState.get_penalty_mult())
	GameState.award_ball_score(base, int(ball.get("yellow_hits")), 0.0, String(ball.get("card")) != "")
	var popup_pos := world_pos + Vector2(0.0, -40.0)
	if hud != null and hud.has_method("popup_score"):
		hud.call("popup_score", 0, popup_pos)
	Audio.play_sfx("void")
	if fx != null:
		fx.popup("坠入虚空", popup_pos, FateConfig.COLOR_CRIMSON, 26)
		fx.burst(world_pos, Color(0.30, 0.10, 0.45), 16, 240.0)
		fx.flash(Color(0.10, 0.02, 0.15), 0.30, 0.6)
		fx.shake(5.0)
	_finish_ball(ball)

func _finish_ball(ball: Node) -> void:
	_active_balls.erase(ball)
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	if launcher != null and phase == Phase.PLAY:
		launcher.set_locked(GameState.balls_left <= 0)
	_check_level_end()

func _cleanup_active_balls() -> void:
	for ball in _active_balls:
		if ball != null and is_instance_valid(ball):
			ball.queue_free()
	_active_balls.clear()

# ================= 关卡判定 =================

## 所有弹珠结算完（含分裂副球）后判定：达标立即过关；弹珠用尽未达标失败。
func _check_level_end() -> void:
	if phase != Phase.PLAY or _level_resolved:
		return
	if not _active_balls.is_empty():
		return
	if GameState.level_score >= GameState.get_target():
		_level_resolved = true
		_on_level_cleared()
		return
	if GameState.balls_left > 0:
		return
	_level_resolved = true
	_on_run_failed()

func _on_level_cleared() -> void:
	phase = Phase.TRANSITION
	if launcher != null:
		launcher.set_locked(true)
	if hud != null and hud.has_method("set_phase_hint"):
		hud.call("set_phase_hint", "命运偏移 · 本间通过！")
	if fx != null:
		fx.popup("命运偏移 · 本间通过", FateConfig.VIEW_SIZE * 0.5, FateConfig.COLOR_GOLD, 42)
		fx.flash(FateConfig.COLOR_GOLD, 0.28, 0.7)
		fx.shake(3.0)
	Audio.play_sfx("win")
	var result := GameState.complete_room()
	if bool(result.get("last", false)):
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		var summary: Dictionary = result.get("summary", {})
		_show_result(true, summary)
		return
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	Audio.play_sfx("click")
	get_tree().change_scene_to_file(CORRIDOR_SCENE_PATH)

func _on_run_failed() -> void:
	phase = Phase.TRANSITION
	if launcher != null:
		launcher.set_locked(true)
	Audio.play_sfx("lose")
	if fx != null:
		fx.flash(Color(0.08, 0.0, 0.12), 0.35, 0.8)
		fx.shake(4.0)
	var summary := GameState.fail_room()
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	_show_result(false, summary)

# ================= 结算 =================

func _show_result(victory: bool, summary: Dictionary) -> void:
	phase = Phase.RESULT
	_result_victory = victory
	if hud != null and hud.has_method("set_phase"):
		hud.call("set_phase", 2)
	_close_overlay()
	Audio.play_bgm("victory" if victory else "defeat")
	var layer := _ensure_ui_layer()
	var result = _instantiate_scene(RESULT_SCENE_PATH)
	if result == null or not result.has_method("show_result"):
		if result != null:
			result.free()
		result = RESULT_FALLBACK.new()
	_overlay_root = result
	layer.add_child(result)
	result.call("show_result", victory, summary)
	if result.has_signal("retry_pressed"):
		result.connect("retry_pressed", Callable(self, "_on_retry_pressed"))
	if result.has_signal("menu_pressed"):
		result.connect("menu_pressed", Callable(self, "_on_menu_pressed"))

func _on_retry_pressed() -> void:
	if _result_victory:
		GameState.start_new_run()
		var err := get_tree().change_scene_to_file(CORRIDOR_SCENE_PATH)
		if err != OK:
			get_tree().reload_current_scene()
	else:
		GameState.prepare_level(GameState.level)
		var err := get_tree().change_scene_to_file(GAME_SCENE_PATH)
		if err != OK:
			get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	_goto_menu()

func _on_exit_pressed() -> void:
	_goto_menu()

# ================= 回主菜单 =================

func _goto_menu() -> void:
	GameState.reset_to_title()
	Audio.play_bgm("menu")
	if ResourceLoader.exists(MENU_SCENE_PATH):
		var err := get_tree().change_scene_to_file(MENU_SCENE_PATH)
		if err == OK:
			return
	_show_missing_menu_fallback()

func _show_missing_menu_fallback() -> void:
	_close_overlay()
	phase = Phase.RESULT
	var layer := _ensure_ui_layer()
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root = panel
	layer.add_child(panel)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.05, 1.0)
	bg.size = FateConfig.VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)
	var label := Label.new()
	label.text = "主菜单场景尚未就绪\nres://scenes/main_menu.tscn"
	label.position = Vector2(240.0, 280.0)
	label.size = Vector2(800.0, 120.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	panel.add_child(label)

# ================= 状态刷新 =================

func _refresh_hud() -> void:
	if hud != null and hud.has_method("refresh"):
		hud.call("refresh")

func _hud_error(text: String) -> void:
	if hud != null and hud.has_method("flash_error"):
		hud.call("flash_error", text)

func _on_coins_changed(_value: int) -> void:
	_refresh_hud()

func _on_score_changed(_level_score: int, _total_score: int) -> void:
	_refresh_hud()

func _on_balls_changed(_balls_left: int, _balls_total: int) -> void:
	_refresh_hud()

func _on_items_changed() -> void:
	_refresh_hud()

func _on_library_changed(_normal: int, _advanced: int) -> void:
	_refresh_hud()

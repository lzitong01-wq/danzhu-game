extends Node2D
## 2D 横版命运走廊（P1 v1.2）：3 个房间门 = 3 关。
## - 虚拟摇杆（左下）移动角色，桌面 A/D、←/→ 也可
## - 当前房间门发光可进入；已通过的门变暗；未解锁的门封印（锁链）
## - 进门：GameState.prepare_level(level) → change_scene_to_file("res://scenes/game.tscn")
## - 背景 assets/art/bg_corridor.png 存在则平铺，缺失则程序化渐变走廊
## - 顶部信息与摇杆在 CanvasLayer 中（屏幕空间），世界层用 Camera2D 跟随
## - v1.2：顶部「行囊 N」+「行囊」按钮 → 打开局外 meta_panel（缺失用内置兜底）

const PLAYER_SCRIPT := preload("res://scripts/corridor/player.gd")
const JOYSTICK_SCRIPT := preload("res://scripts/corridor/joystick.gd")
const META_FALLBACK := preload("res://scripts/corridor/meta_fallback.gd")
const PX := preload("res://scripts/gameplay/px.gd")

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const META_PANEL_PATH := "res://scenes/ui/meta_panel.tscn"

var player = null
var camera: Camera2D = null
var joystick = null

var _ui_layer: CanvasLayer = null
var _info_label: Label = null
var _hint_label: Label = null
var _enter_btn: Button = null
var _bag_btn: Button = null
var _meta_layer: CanvasLayer = null
var _meta_panel = null
var _entering := false
var _time := 0.0

var _font: Font = null
var _bg_texture: Texture2D = null
var _door_texture: Texture2D = null
var _stars: Array = []

func _ready() -> void:
	randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 直接从编辑器/调试启动走廊时，兜底开一局（正常流程由主菜单 start_new_run）
	if not GameState.run_active and GameState.ball_slots.is_empty():
		GameState.start_new_run()
	_load_assets()
	_build_player_and_camera()
	_build_ui()
	Audio.play_bgm("menu")
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	if _entering:
		return
	# 移动：摇杆优先 + 键盘
	var dir := 0.0
	if joystick != null:
		dir = float(joystick.vector.x)
	dir += _key_axis()
	if absf(dir) > 0.01:
		dir = clampf(dir, -1.0, 1.0)
		player.position.x = clampf(
			player.position.x + dir * FateConfig.CORRIDOR_PLAYER_SPEED * delta,
			0.0,
			FateConfig.CORRIDOR_LENGTH)
		player.facing = 1.0 if dir > 0.0 else -1.0
	# 相机跟随（限制在 0..CORRIDOR_LENGTH）
	var half_view := FateConfig.VIEW_SIZE.x * 0.5
	camera.position.x = clampf(player.position.x, half_view, FateConfig.CORRIDOR_LENGTH - half_view)
	camera.position.y = FateConfig.VIEW_SIZE.y * 0.5
	_update_door_interaction()
	_update_info()
	queue_redraw()

func _key_axis() -> float:
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0
	return axis

# ================= 资源与骨架 =================

func _load_assets() -> void:
	_font = _load_font()
	var bg_path := "res://assets/art/bg_corridor.png"
	if ResourceLoader.exists(bg_path):
		var bg = load(bg_path)
		if bg is Texture2D:
			_bg_texture = bg
	var door_path := "res://assets/art/door.png"
	if ResourceLoader.exists(door_path):
		var door = load(door_path)
		if door is Texture2D:
			_door_texture = door
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in 170:
		_stars.append({
			"pos": Vector2(rng.randf_range(0.0, FateConfig.CORRIDOR_LENGTH), rng.randf_range(70.0, FateConfig.CORRIDOR_FLOOR_Y - 20.0)),
			"radius": rng.randf_range(0.8, 2.0),
			"alpha": rng.randf_range(0.06, 0.35),
		})

func _load_font() -> Font:
	var candidates: Array = ["res://assets/fonts/FateBody.ttf", "res://assets/fonts/FateTitle.ttf"]
	for p in candidates:
		var path := String(p)
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Font:
				return res
	return ThemeDB.fallback_font

func _build_player_and_camera() -> void:
	var start_x: float = FateConfig.CORRIDOR_PLAYER_START.x
	if GameState.level > 1:
		var prev_index := clampi(GameState.level - 2, 0, FateConfig.CORRIDOR_DOOR_X.size() - 1)
		start_x = FateConfig.CORRIDOR_DOOR_X[prev_index] + 150.0
	player = PLAYER_SCRIPT.new()
	player.position = Vector2(start_x, FateConfig.CORRIDOR_FLOOR_Y)
	add_child(player)
	camera = Camera2D.new()
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.position = Vector2(
		clampf(start_x, FateConfig.VIEW_SIZE.x * 0.5, FateConfig.CORRIDOR_LENGTH - FateConfig.VIEW_SIZE.x * 0.5),
		FateConfig.VIEW_SIZE.y * 0.5)
	camera.limit_left = 0
	camera.limit_right = int(FateConfig.CORRIDOR_LENGTH)
	camera.limit_top = 0
	camera.limit_bottom = int(FateConfig.VIEW_SIZE.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)
	# 顶部信息条
	var bar := ColorRect.new()
	bar.position = Vector2(0.0, 0.0)
	bar.size = Vector2(1280.0, 64.0)
	bar.color = Color(0.05, 0.03, 0.09, 0.78)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var theme := Theme.new()
	if _font != null:
		theme.default_font = _font
	theme.default_font_size = 20
	root.theme = theme
	_info_label = Label.new()
	_info_label.position = Vector2(20.0, 14.0)
	_info_label.size = Vector2(1120.0, 40.0)
	_info_label.add_theme_font_size_override("font_size", 22)
	_info_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info_label)
	# 行囊按钮（v1.2）
	_bag_btn = Button.new()
	_bag_btn.text = "行囊"
	_bag_btn.position = Vector2(1160.0, 12.0)
	_bag_btn.size = Vector2(104.0, 40.0)
	_bag_btn.add_theme_font_size_override("font_size", 18)
	_bag_btn.pressed.connect(_open_meta_panel)
	root.add_child(_bag_btn)
	_hint_label = Label.new()
	_hint_label.position = Vector2(260.0, 672.0)
	_hint_label.size = Vector2(760.0, 36.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 19)
	_hint_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)
	# 摇杆
	joystick = JOYSTICK_SCRIPT.new()
	root.add_child(joystick)
	# 进入试炼按钮（靠近当前门时显示）
	_enter_btn = Button.new()
	_enter_btn.text = "进入试炼"
	_enter_btn.position = Vector2(540.0, 424.0)
	_enter_btn.size = Vector2(200.0, 64.0)
	_enter_btn.add_theme_font_size_override("font_size", 26)
	_enter_btn.visible = false
	_enter_btn.pressed.connect(_enter_room)
	root.add_child(_enter_btn)

# ================= 门与交互 =================

## 门状态：0=已通过，1=当前，2=封印
func get_door_state(index: int) -> int:
	if index < 0 or index >= FateConfig.CORRIDOR_DOOR_X.size():
		return 2
	var room := index + 1
	if room < GameState.level:
		return 0
	if room == GameState.level:
		return 1
	return 2

func _update_door_interaction() -> void:
	var index := GameState.level - 1
	if index < 0 or index >= FateConfig.CORRIDOR_DOOR_X.size():
		if _enter_btn != null:
			_enter_btn.visible = false
		return
	var door_x: float = FateConfig.CORRIDOR_DOOR_X[index]
	var distance := absf(player.position.x - door_x)
	var near := distance < 90.0
	if _enter_btn != null:
		_enter_btn.visible = near
	if _hint_label != null:
		if near:
			_hint_label.text = "点击「进入试炼」或继续向前走进入第%d间「%s」" % [index + 1, GameState.get_level_name()]
		else:
			_hint_label.text = "摇杆移动 · 走进当前房间门（桌面 A/D 或 ←/→）"
	# 直接走进门触发
	if distance < 58.0:
		_enter_room()

func _enter_room() -> void:
	if _entering:
		return
	_entering = true
	Audio.play_sfx("click")
	GameState.prepare_level(GameState.level)
	var err := get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if err != OK:
		_entering = false

func _update_info() -> void:
	if _info_label == null:
		return
	_info_label.text = "第 %d / %d 间     金币 %d     命运碎片 %d     最高分 %d     行囊 %d" % [
		clampi(GameState.level, 1, FateConfig.MAX_LEVEL),
		FateConfig.MAX_LEVEL,
		GameState.coins,
		GameState.total_shards,
		GameState.best_score,
		_meta_count(),
	]

## 局外行囊总件数（弹珠 + 卡牌）
func _meta_count() -> int:
	return int(GameState.meta_balls_normal) + int(GameState.meta_balls_advanced) + int(GameState.meta_cards.size())

# ================= 局外行囊面板 =================

func _open_meta_panel() -> void:
	if _meta_panel != null and is_instance_valid(_meta_panel):
		return
	if _meta_layer == null:
		_meta_layer = CanvasLayer.new()
		_meta_layer.layer = 20
		add_child(_meta_layer)
	var scene = null
	if ResourceLoader.exists(META_PANEL_PATH):
		var packed = load(META_PANEL_PATH)
		if packed is PackedScene:
			scene = (packed as PackedScene).instantiate()
	var compatible: bool = scene != null and scene.has_method("open_panel") and scene.has_signal("closed")
	if compatible:
		_meta_panel = scene
	else:
		if scene != null:
			scene.free()
		_meta_panel = META_FALLBACK.new()
	_meta_layer.add_child(_meta_panel)
	if _meta_panel.has_signal("closed"):
		_meta_panel.connect("closed", Callable(self, "_on_meta_closed"))
	if _meta_panel.has_method("open_panel"):
		_meta_panel.call("open_panel")
	Audio.play_sfx("click")

func _on_meta_closed() -> void:
	if _meta_panel != null and is_instance_valid(_meta_panel):
		_meta_panel.queue_free()
	_meta_panel = null
	_update_info()

# ================= 绘制 =================

func _draw() -> void:
	var length := FateConfig.CORRIDOR_LENGTH
	var floor_y := FateConfig.CORRIDOR_FLOOR_Y
	# 背景
	if _bg_texture != null:
		draw_texture_rect(_bg_texture, Rect2(0.0, 0.0, length, FateConfig.VIEW_SIZE.y), true)
	else:
		draw_rect(Rect2(0.0, 0.0, length, FateConfig.VIEW_SIZE.y), FateConfig.COLOR_BG_DEEP)
		var bands := 16
		for i in bands:
			var t := float(i) / float(bands)
			var col := FateConfig.COLOR_BG_DEEP.lerp(FateConfig.COLOR_BG_LOW, t)
			draw_rect(Rect2(0.0, t * FateConfig.VIEW_SIZE.y, length, FateConfig.VIEW_SIZE.y / float(bands) + 1.0), col)
		# 星尘
		for star in _stars:
			var pos: Vector2 = star["pos"]
			PX.rect(self, Rect2(pos, Vector2(4.0, 4.0)), Color(0.8, 0.75, 0.95, float(star["alpha"])))
		# 走廊石柱
		var x := 160.0
		while x < length:
			draw_rect(Rect2(x - 18.0, 150.0, 36.0, floor_y - 150.0), Color(0.10, 0.07, 0.17, 0.9))
			draw_rect(Rect2(x - 30.0, 128.0, 60.0, 24.0), Color(0.13, 0.09, 0.22, 0.95))
			draw_line(Vector2(x - 18.0, 152.0), Vector2(x - 18.0, floor_y), Color(0.55, 0.45, 0.85, 0.12), 2.0)
			draw_line(Vector2(x + 18.0, 152.0), Vector2(x + 18.0, floor_y), Color(0.55, 0.45, 0.85, 0.12), 2.0)
			x += 320.0
	# 地面
	draw_rect(Rect2(0.0, floor_y, length, FateConfig.VIEW_SIZE.y - floor_y), Color(0.05, 0.03, 0.09, 0.95))
	draw_line(Vector2(0.0, floor_y), Vector2(length, floor_y), Color(0.55, 0.45, 0.85, 0.55), 3.0)
	var tile_x := 0.0
	while tile_x < length:
		draw_line(Vector2(tile_x, floor_y + 8.0), Vector2(tile_x + 60.0, floor_y + 8.0), Color(0.42, 0.34, 0.66, 0.18), 2.0)
		tile_x += 120.0
	# 三个房间门
	for i in FateConfig.CORRIDOR_DOOR_X.size():
		_draw_door(i)

func _draw_door(index: int) -> void:
	if _font == null:
		_font = _load_font()
	var font := _font
	var door_x: float = FateConfig.CORRIDOR_DOOR_X[index]
	var floor_y := FateConfig.CORRIDOR_FLOOR_Y
	var state := get_door_state(index)
	var frame_color := Color(0.30, 0.25, 0.40)
	var hole_color := Color(0.03, 0.02, 0.06, 0.95)
	var label_color := FateConfig.COLOR_TEXT_DIM
	var label_text := "已通过"
	if state == 1:
		var pulse := 0.5 + 0.5 * sin(_time * 2.4)
		# 门口光晕（像素盘）
		PX.disc(self, Vector2(door_x, floor_y - 150.0), 140.0, Color(0.91, 0.76, 0.42, 0.05 + 0.05 * pulse))
		draw_rect(Rect2(door_x - 100.0, floor_y - 320.0, 200.0, 320.0), Color(0.91, 0.76, 0.42, 0.05 + 0.04 * pulse))
		frame_color = FateConfig.COLOR_GOLD
		hole_color = Color(0.35, 0.26, 0.12, 0.85)
		label_color = FateConfig.COLOR_GOLD
		label_text = "第%d间 · %s" % [index + 1, _room_name(index)]
	elif state == 0:
		frame_color = Color(0.36, 0.31, 0.46)
		hole_color = Color(0.02, 0.01, 0.04, 0.98)
		label_color = Color(0.60, 0.55, 0.68)
		label_text = "第%d间 · 已通过" % (index + 1)
	else:
		frame_color = Color(0.22, 0.18, 0.32)
		hole_color = Color(0.03, 0.02, 0.05, 0.98)
		label_color = Color(0.45, 0.40, 0.52)
		label_text = "第%d间 · 封印" % (index + 1)
	# 门洞（拱形）
	var door_w := 150.0
	var door_h := 300.0
	var top_y := floor_y - door_h
	var arch_radius := door_w * 0.5
	draw_rect(Rect2(door_x - door_w * 0.5 - 14.0, top_y - 14.0, door_w + 28.0, door_h + 14.0), frame_color)
	PX.disc(self, Vector2(door_x, top_y), arch_radius + 14.0, frame_color)
	draw_rect(Rect2(door_x - door_w * 0.5, top_y, door_w, door_h), hole_color)
	PX.disc(self, Vector2(door_x, top_y), arch_radius, hole_color)
	# door.png 叠加（如有）
	if _door_texture != null:
		var tint := Color(1.0, 1.0, 1.0, 0.9)
		if state == 0:
			tint = Color(0.55, 0.5, 0.65, 0.8)
		elif state == 2:
			tint = Color(0.3, 0.25, 0.4, 0.9)
		draw_texture_rect(_door_texture, Rect2(door_x - 100.0, floor_y - 320.0, 200.0, 320.0), false, tint)
	# 封印锁链
	if state == 2:
		for k in 3:
			var y := top_y + 70.0 + float(k) * 70.0
			draw_line(Vector2(door_x - 60.0, y), Vector2(door_x + 60.0, y + 26.0), Color(0.42, 0.36, 0.52, 0.85), 4.0)
			draw_line(Vector2(door_x - 60.0, y + 26.0), Vector2(door_x + 60.0, y), Color(0.42, 0.36, 0.52, 0.85), 4.0)
		PX.disc(self, Vector2(door_x, floor_y - 150.0), 16.0, Color(0.35, 0.30, 0.45, 0.95))
		PX.ring(self, Vector2(door_x, floor_y - 150.0), 10.0, Color(0.6, 0.55, 0.7, 0.9), 1)
	# 当前门指示箭头
	if state == 1:
		var bob := sin(_time * 3.0) * 6.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(door_x - 14.0, top_y - 54.0 + bob),
			Vector2(door_x + 14.0, top_y - 54.0 + bob),
			Vector2(door_x, top_y - 34.0 + bob),
		]), FateConfig.COLOR_GOLD)
	# 门名标签（放在拱顶上方，加半透明底避免与光柱/门拱重叠）
	draw_rect(Rect2(door_x - 224.0, top_y - 122.0, 448.0, 32.0), Color(0.02, 0.01, 0.05, 0.55))
	draw_string(font, Vector2(door_x - 220.0, top_y - 98.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, 440.0, 24, label_color)

func _room_name(index: int) -> String:
	var level := clampi(index + 1, 1, FateConfig.MAX_LEVEL)
	return FateConfig.LEVEL_NAMES[level - 1]

# ================= 返回主菜单 =================

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_goto_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			_goto_menu()
			get_viewport().set_input_as_handled()

func _goto_menu() -> void:
	if _entering:
		return
	GameState.reset_to_title()
	Audio.play_bgm("menu")
	if ResourceLoader.exists(MENU_SCENE_PATH):
		get_tree().change_scene_to_file(MENU_SCENE_PATH)

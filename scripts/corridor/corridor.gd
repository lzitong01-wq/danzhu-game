extends Node2D
## 2D 横版命运走廊（v1.7 纯手游）：10 个房间门 = 10 关 + 每关 NPC。
## - 用户 P1 抠图角色：walk/idle 帧动画；虚拟摇杆移动，全部触屏
## - 顶部只留「← 返回」「行囊」，无其它常驻信息；交互键在底部偏右
## - 靠近 NPC 点「交互」→ P1 对话（左椭圆立绘+右圆角文本框+打字机）→「进入试炼」→ 商店
## - 绕过 NPC 到门前 → 中间偏右「进入试炼」→ 商店
## - 远景回廊：视差背景、旋转琉璃珠、守命者剪影（ui 资源缺失时程序化兜底）

const PLAYER_SCRIPT := preload("res://scripts/corridor/player.gd")
const JOYSTICK_SCRIPT := preload("res://scripts/corridor/joystick.gd")
const META_FALLBACK := preload("res://scripts/corridor/meta_fallback.gd")
const PX := preload("res://scripts/gameplay/px.gd")

const GAME_SCENE_PATH := "res://scenes/game.tscn"
const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const META_PANEL_PATH := "res://scenes/ui/meta_panel.tscn"
const CHARACTER_PANEL_PATH := "res://scenes/ui/character_panel.tscn"
## 触屏动作按钮统一矩形：交互 / 进入试炼 / 对话进入试炼共用
const ACTION_BTN_RECT := Rect2(740.0, 430.0, 230.0, 68.0)

var player = null
var camera: Camera2D = null
var joystick = null

var _ui_layer: CanvasLayer = null
var _hint_label: Label = null
var _story_label: Label = null
var _enter_btn: Button = null
var _menu_btn: Button = null
var _bag_btn: Button = null
var _interact_btn: Button = null
var _cinematic_layer: CanvasLayer = null
var _blackout: ColorRect = null
var _dialog_root: Control = null
var _dialog_enter_btn: Button = null
var _dialog_click_hint: Label = null
var _dialog_portrait: TextureRect = null
var _meta_layer: CanvasLayer = null
var _meta_panel = null
var _entering := false
var _story_playing := false
var _dialog_state := 0
var _dialog_full := ""
var _dialog_chars := 0.0
var _time := 0.0
var _orb_angle := 0.0

var _font: Font = null
var _bg_texture: Texture2D = null
var _bg_texture_v2: Texture2D = null
var _door_texture: Texture2D = null
var _idle_texture: Texture2D = null
var _portrait_texture: Texture2D = null
var _orb_texture: Texture2D = null
var _guardian_texture: Texture2D = null
var _bag_icon: Texture2D = null
var _stars: Array = []
var _npcs: Array = []
var _npc_sprites: Array = []
var _npc_hidden: Array = []
var _npc_alpha: Array = []
var _fading_npc := -1
var _story_shown := false
var _npc_near := false
var _action_cd := 0.0

func _ready() -> void:
	randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 直接从编辑器/调试启动走廊时，兜底开一局（正常流程由主菜单 start_new_run）
	if not GameState.run_active and GameState.ball_slots.is_empty():
		GameState.start_new_run()
	# 回到走廊 = 存档点①（刚过关后 checkpoint=CLEAR 时落点）
	if GameState.checkpoint == FateConfig.CHECKPOINT_CLEAR:
		GameState.mark_checkpoint(FateConfig.CHECKPOINT_CORRIDOR)
	# 隐藏关未解锁时，若存档 level 超过可见上限则夹回（不泄露第 10 间）
	var visible_max := GameState.visible_max_level()
	if int(GameState.level) > visible_max:
		GameState.level = visible_max
		GameState.save_game()
	_load_assets()
	_build_player_and_camera()
	_build_npcs()
	_build_ui()
	_build_cinematic()
	Audio.play_bgm("menu")
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_orb_angle += delta * 0.35
	if _action_cd > 0.0:
		_action_cd = maxf(0.0, _action_cd - delta)
	if _entering:
		return
	# 对话打字机推进
	if _dialog_state == 1:
		_update_typewriter(delta)
	# 对话/遮罩期间冻结玩家移动
	if _dialog_state != 0:
		player.update_motion(0.0, delta)
		_update_fading_npc(delta)
		_animate_npcs()
		queue_redraw()
		return
	# 移动：虚拟摇杆（触屏），角色内部做加速度/摩擦与帧动画
	var dir := 0.0
	if joystick != null:
		dir = clampf(float(joystick.vector.x), -1.0, 1.0)
	player.update_motion(dir, delta)
	var new_x: float = player.position.x + player.get_speed() * delta
	var clamped_x: float = clampf(new_x, 0.0, FateConfig.CORRIDOR_LENGTH)
	if absf(clamped_x - new_x) > 0.01:
		player.velocity_x = 0.0
	player.position.x = clamped_x
	# 相机跟随（限制在 0..CORRIDOR_LENGTH）
	var half_view := FateConfig.VIEW_SIZE.x * 0.5
	camera.position.x = clampf(player.position.x, half_view, FateConfig.CORRIDOR_LENGTH - half_view)
	camera.position.y = FateConfig.VIEW_SIZE.y * 0.5
	_update_door_interaction()
	_update_npc_prompt()
	_update_fading_npc(delta)
	_animate_npcs()
	queue_redraw()

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
	if ResourceLoader.exists(FateConfig.PLAYER_IDLE_SPRITE):
		var idle = load(FateConfig.PLAYER_IDLE_SPRITE)
		if idle is Texture2D:
			_idle_texture = idle
	# v1.7 远景背景 / 旋转珠 / 守命者 / 行囊图标（ui 未交付时留空走程序化兜底）
	_bg_texture_v2 = _load_texture("res://assets/art/corridor_bg_v2.png")
	_orb_texture = _load_texture("res://assets/art/orb_glow.png")
	_guardian_texture = _load_texture("res://assets/art/guardian_silhouette.png")
	_bag_icon = _load_texture("res://assets/art/bag_icon.png")
	_portrait_texture = _load_texture("res://assets/art/player_portrait.png")
	if _portrait_texture == null:
		_portrait_texture = _load_texture(FateConfig.PLAYER_IDLE_SPRITE)
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in 420:
		_stars.append({
			"pos": Vector2(rng.randf_range(0.0, FateConfig.CORRIDOR_LENGTH), rng.randf_range(70.0, FateConfig.CORRIDOR_FLOOR_Y - 20.0)),
			"radius": rng.randf_range(0.8, 2.0),
			"alpha": rng.randf_range(0.06, 0.35),
		})

## 安全加载贴图，缺失返回 null
func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is Texture2D:
		return res
	return null

## 每关门前 NPC：与玩家同一组抠图帧（镜像、面朝玩家），头顶 W；已看过的关卡不再出现
func _build_npcs() -> void:
	_npcs.clear()
	_npc_sprites.clear()
	_npc_hidden.clear()
	_npc_alpha.clear()
	_fading_npc = -1
	var visible_max := mini(GameState.visible_max_level(), FateConfig.CORRIDOR_DOOR_X.size())
	for i in visible_max:
		var seen := GameState.is_npc_seen(i + 1)
		var npc_x: float = FateConfig.CORRIDOR_DOOR_X[i] - FateConfig.CORRIDOR_NPC_OFFSET
		_npcs.append(Vector2(npc_x, FateConfig.CORRIDOR_FLOOR_Y))
		_npc_hidden.append(seen)
		_npc_alpha.append(1.0)
		if seen or _idle_texture == null:
			_npc_sprites.append(null)
			continue
		var sprite := Sprite2D.new()
		sprite.texture = _idle_texture
		sprite.hframes = FateConfig.PLAYER_IDLE_FRAMES
		sprite.vframes = 1
		sprite.frame = 0
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2.ONE * FateConfig.PLAYER_SCALE
		var frame_h := float(_idle_texture.get_height())
		sprite.position = Vector2(npc_x, FateConfig.CORRIDOR_FLOOR_Y - frame_h * FateConfig.PLAYER_SCALE * 0.5)
		sprite.modulate = Color(0.72, 0.66, 0.95)
		sprite.z_index = 5
		add_child(sprite)
		_npc_sprites.append(sprite)

func _animate_npcs() -> void:
	if _npc_sprites.is_empty():
		return
	var current := clampi(GameState.level - 1, 0, _npc_sprites.size() - 1)
	for i in _npc_sprites.size():
		if i < _npc_hidden.size() and bool(_npc_hidden[i]):
			continue
		var sprite = _npc_sprites[i]
		if sprite == null or not is_instance_valid(sprite):
			continue
		sprite.frame = int(_time * 4.0) % FateConfig.PLAYER_IDLE_FRAMES
		# NPC 面朝玩家（与玩家镜像）
		sprite.flip_h = player != null and player.position.x < _npcs[i].x
		var base := Color(1.0, 0.95, 0.8) if i == current else Color(0.62, 0.56, 0.82)
		var alpha: float = float(_npc_alpha[i]) if i < _npc_alpha.size() else 1.0
		sprite.modulate = Color(base.r, base.g, base.b, alpha)

## NPC 淡出（约 0.5s）后隐藏，只在对话触发时调用
func _begin_npc_fade(index: int) -> void:
	if index < 0 or index >= _npcs.size():
		return
	_fading_npc = index

func _update_fading_npc(delta: float) -> void:
	if _fading_npc < 0 or _fading_npc >= _npc_alpha.size():
		return
	var index := _fading_npc
	_npc_alpha[index] = maxf(0.0, float(_npc_alpha[index]) - delta / 0.5)
	var sprite = _npc_sprites[index] if index < _npc_sprites.size() else null
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate.a = float(_npc_alpha[index])
	if float(_npc_alpha[index]) <= 0.0:
		_npc_hidden[index] = true
		if sprite != null and is_instance_valid(sprite):
			sprite.hide()
		_fading_npc = -1
	queue_redraw()

## 靠近当前关 NPC 时给出交互提示（W / 点击 NPC）
func _update_npc_prompt() -> void:
	_npc_near = false
	var want_interact := false
	if _dialog_state == 0:
		var index := GameState.level - 1
		if index >= 0 and index < mini(GameState.visible_max_level(), _npcs.size()) \
			and not bool(_npc_hidden[index]) and not GameState.is_npc_seen(GameState.level):
			var npc_pos: Vector2 = _npcs[index]
			_npc_near = absf(player.position.x - npc_pos.x) < FateConfig.NPC_INTERACT_RADIUS
			want_interact = _npc_near
	if _interact_btn != null:
		# 仅在变化时赋值：每帧隐藏/显示会取消 Button 的 press（真机点击无反应根因）
		if _interact_btn.visible != want_interact:
			_interact_btn.visible = want_interact
	if _npc_near and _hint_label != null:
		_hint_label.text = "点击「交互」与 NPC 对话"

## 尝试开启当前关 NPC 对话（触屏交互键）
func try_open_npc_dialog() -> bool:
	if not _npc_near or _dialog_state != 0 or _entering:
		return false
	var index := GameState.level - 1
	if index < 0 or index >= _npcs.size():
		return false
	if bool(_npc_hidden[index]) or GameState.is_npc_seen(GameState.level):
		return false
	_trigger_npc_dialog(index)
	return true

func _trigger_npc_dialog(index: int) -> void:
	if _dialog_state != 0:
		return
	_story_shown = true
	_story_playing = true
	_dialog_state = 1
	_dialog_full = GameState.get_story_line()
	_dialog_chars = 0.0
	GameState.mark_npc_seen(GameState.level)
	_begin_npc_fade(index)
	if joystick != null:
		joystick.vector = Vector2.ZERO
	Audio.play_sfx("click")
	if _dialog_root == null or _blackout == null or _story_label == null:
		return
	_blackout.visible = true
	_blackout.color = Color(0.02, 0.01, 0.05, 0.82)
	if _dialog_portrait != null:
		_dialog_portrait.visible = _dialog_portrait.texture != null
	_story_label.text = ""
	_story_label.modulate.a = 1.0
	if _dialog_enter_btn != null:
		_dialog_enter_btn.visible = false
	if _dialog_click_hint != null:
		_dialog_click_hint.text = "点击文本框继续"
		_dialog_click_hint.visible = true
	_dialog_root.visible = true
	_dialog_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if _hint_label != null:
		_hint_label.text = ""

## 逐字打字机：STORY_TYPE_SPEED 秒/字
func _update_typewriter(delta: float) -> void:
	if _dialog_state != 1:
		return
	_dialog_chars += delta / maxf(FateConfig.STORY_TYPE_SPEED, 0.001)
	var count := mini(int(_dialog_chars), _dialog_full.length())
	if _story_label != null:
		_story_label.text = _dialog_full.substr(0, count)
	if count >= _dialog_full.length():
		_finish_typing()

func _finish_typing() -> void:
	_dialog_state = 2
	if _story_label != null:
		_story_label.text = _dialog_full
	if _dialog_enter_btn != null:
		_dialog_enter_btn.visible = true
	# 避免继续提示「点击文本框」造成误导
	if _dialog_click_hint != null:
		_dialog_click_hint.text = "点击「进入试炼」进入商店"
		_dialog_click_hint.visible = true

## 对话文本区域点击：打字中→立刻显示全文；已播完→显示「进入试炼」
func _on_dialog_click(_event: InputEvent) -> void:
	if _dialog_state == 1:
		_finish_typing()
	elif _dialog_state == 2 and _dialog_enter_btn != null:
		_dialog_enter_btn.visible = true

func _on_dialog_enter_pressed() -> void:
	if _dialog_state == 0:
		return
	_dialog_state = 0
	_story_playing = false
	if _dialog_root != null:
		_dialog_root.visible = false
	if _blackout != null:
		_blackout.visible = false
	if _story_label != null:
		_story_label.text = ""
	Audio.play_sfx("click")
	_enter_room()

## 黑屏白字剧情层（独立 CanvasLayer，盖住世界与摇杆）
func _build_cinematic() -> void:
	_cinematic_layer = CanvasLayer.new()
	_cinematic_layer.layer = 40
	add_child(_cinematic_layer)
	_dialog_root = Control.new()
	_dialog_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_root.gui_input.connect(_on_dialog_click)
	_dialog_root.visible = false
	_cinematic_layer.add_child(_dialog_root)
	_blackout = ColorRect.new()
	_blackout.position = Vector2.ZERO
	_blackout.size = FateConfig.VIEW_SIZE
	_blackout.color = Color(0.02, 0.01, 0.05, 0.82)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_root.add_child(_blackout)
	# P1 对话：左侧椭圆角色放大图（player_portrait，椭圆 mask + 淡蓝紫描边）
	_dialog_portrait = TextureRect.new()
	_dialog_portrait.position = Vector2(70.0, 118.0)
	_dialog_portrait.size = Vector2(390.0, 480.0)
	_dialog_portrait.texture = _portrait_texture
	_dialog_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialog_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialog_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dialog_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_portrait.visible = _portrait_texture != null
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	if (d > 0.5) discard;
	vec4 c = texture(TEXTURE, UV);
	float edge = smoothstep(0.38, 0.5, d);
	vec3 glow = vec3(0.58, 0.70, 1.0);
	c.rgb = mix(c.rgb, glow, edge * 0.55);
	c.a *= 1.0 - smoothstep(0.49, 0.5, d);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_dialog_portrait.material = mat
	_dialog_root.add_child(_dialog_portrait)
	# 右侧圆角文案框
	var textbox := Panel.new()
	textbox.position = Vector2(490.0, 150.0)
	textbox.size = Vector2(700.0, 360.0)
	textbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.07, 0.06, 0.13, 0.94)
	box_style.border_color = Color(0.55, 0.48, 0.78, 0.9)
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(18)
	box_style.content_margin_left = 24.0
	box_style.content_margin_right = 24.0
	box_style.content_margin_top = 20.0
	box_style.content_margin_bottom = 20.0
	textbox.add_theme_stylebox_override("panel", box_style)
	_dialog_root.add_child(textbox)
	_story_label = Label.new()
	_story_label.position = Vector2(518.0, 178.0)
	_story_label.size = Vector2(644.0, 300.0)
	_story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_story_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.add_theme_font_size_override("font_size", 22)
	_story_label.add_theme_color_override("font_color", Color(0.96, 0.94, 1.0))
	_story_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_story_label.add_theme_constant_override("outline_size", 3)
	_story_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_root.add_child(_story_label)
	# 文字播完后出现在界面中间偏右
	_dialog_enter_btn = Button.new()
	_dialog_enter_btn.text = "进入试炼"
	_dialog_enter_btn.position = ACTION_BTN_RECT.position
	_dialog_enter_btn.size = ACTION_BTN_RECT.size
	_dialog_enter_btn.add_theme_font_size_override("font_size", 24)
	_dialog_enter_btn.visible = false
	_dialog_enter_btn.pressed.connect(_on_dialog_enter_pressed)
	_dialog_enter_btn.button_down.connect(_on_dialog_enter_pressed)
	_dialog_root.add_child(_dialog_enter_btn)
	_dialog_click_hint = Label.new()
	_dialog_click_hint.text = "点击文本框继续"
	_dialog_click_hint.position = Vector2(700.0, 520.0)
	_dialog_click_hint.size = Vector2(360.0, 28.0)
	_dialog_click_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_click_hint.add_theme_font_size_override("font_size", 16)
	_dialog_click_hint.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	_dialog_click_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_root.add_child(_dialog_click_hint)

func get_npc_position(index: int) -> Vector2:
	if index < 0 or index >= _npcs.size():
		return Vector2.ZERO
	return _npcs[index]

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
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	_ui_layer.add_child(root)
	var theme := Theme.new()
	if _font != null:
		theme.default_font = _font
	theme.default_font_size = 20
	root.theme = theme
	# 左上角：返回（保存后回主菜单）
	_menu_btn = Button.new()
	_menu_btn.text = "← 返回"
	_menu_btn.position = Vector2(16.0, 14.0)
	_menu_btn.size = Vector2(150.0, 52.0)
	_menu_btn.add_theme_font_size_override("font_size", 20)
	_menu_btn.pressed.connect(_goto_menu)
	root.add_child(_menu_btn)
	# 右上角：行囊 / 个人信息面板（图标 + 文字并排，确保一眼可读）
	_bag_btn = Button.new()
	_bag_btn.position = Vector2(1108.0, 14.0)
	_bag_btn.size = Vector2(156.0, 52.0)
	_bag_btn.add_theme_font_size_override("font_size", 20)
	_bag_btn.text = "  行囊"
	if _bag_icon != null:
		var bag_icon_rect := TextureRect.new()
		bag_icon_rect.texture = _bag_icon
		bag_icon_rect.position = Vector2(10.0, 8.0)
		bag_icon_rect.size = Vector2(34.0, 36.0)
		bag_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bag_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bag_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bag_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bag_btn.add_child(bag_icon_rect)
	_bag_btn.pressed.connect(_open_meta_panel)
	root.add_child(_bag_btn)
	_hint_label = Label.new()
	_hint_label.position = Vector2(260.0, 676.0)
	_hint_label.size = Vector2(760.0, 36.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)
	# 摇杆
	joystick = JOYSTICK_SCRIPT.new()
	root.add_child(joystick)
	# 底部偏右：触屏「交互」键（靠近 NPC 时出现）
	_interact_btn = Button.new()
	_interact_btn.text = "交互"
	_interact_btn.position = ACTION_BTN_RECT.position
	_interact_btn.size = ACTION_BTN_RECT.size
	_interact_btn.add_theme_font_size_override("font_size", 26)
	_interact_btn.visible = false
	_interact_btn.pressed.connect(_on_interact_pressed)
	_interact_btn.button_down.connect(_on_interact_pressed)
	root.add_child(_interact_btn)
	# 界面中间偏右：「进入试炼」（门前/对话完成后）
	_enter_btn = Button.new()
	_enter_btn.text = "进入试炼"
	_enter_btn.position = ACTION_BTN_RECT.position
	_enter_btn.size = ACTION_BTN_RECT.size
	_enter_btn.add_theme_font_size_override("font_size", 24)
	_enter_btn.visible = false
	_enter_btn.pressed.connect(_enter_room)
	_enter_btn.button_down.connect(_enter_room)
	root.add_child(_enter_btn)

## 点击触屏交互键：靠近 NPC → 对话（button_down/pressed 双通道，带去抖）
func _on_interact_pressed() -> void:
	if _action_cd > 0.0:
		return
	_action_cd = 0.2
	Audio.play_sfx("click")
	try_open_npc_dialog()

# ================= 门与交互 =================

## 门状态：0=已通过，1=当前，2=封印
func get_door_state(index: int) -> int:
	if index < 0 or index >= FateConfig.CORRIDOR_DOOR_X.size():
		return 2
	# 未解锁的隐藏关（第10间）视为不存在
	if index >= GameState.visible_max_level():
		return 2
	var room := index + 1
	if room < GameState.level:
		return 0
	if room == GameState.level:
		return 1
	return 2

func _update_door_interaction() -> void:
	var index := GameState.level - 1
	if index < 0 or index >= mini(GameState.visible_max_level(), FateConfig.CORRIDOR_DOOR_X.size()):
		if _enter_btn != null and _enter_btn.visible:
			_enter_btn.visible = false
		return
	var door_x: float = FateConfig.CORRIDOR_DOOR_X[index]
	var distance := absf(player.position.x - door_x)
	var near := distance < 90.0
	if _enter_btn != null:
		var want_visible := near and _dialog_state == 0
		# 仅在变化时赋值：每帧隐藏/显示会取消 Button 的 press
		if _enter_btn.visible != want_visible:
			_enter_btn.visible = want_visible
	if _hint_label != null:
		if near:
			_hint_label.text = "点击「进入试炼」进入第%d间「%s」" % [index + 1, GameState.get_level_name()]
		else:
			_hint_label.text = "摇杆移动 · 靠近 NPC 或门时点击「交互」"

func _enter_room() -> void:
	if _entering:
		return
	_entering = true
	Audio.play_sfx("door")
	# 进入商店（PREP）= 存档点②
	GameState.mark_checkpoint(FateConfig.CHECKPOINT_SHOP)
	GameState.prepare_level(GameState.level)
	var err := get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if err != OK:
		_entering = false

## 局外行囊总件数（弹珠 + 卡牌）
func _meta_count() -> int:
	return int(GameState.meta_balls_normal) + int(GameState.meta_balls_advanced) + int(GameState.meta_cards.size())

# ================= 角色 / 行囊面板 =================

func _open_meta_panel() -> void:
	if _meta_panel != null and is_instance_valid(_meta_panel):
		return
	if _meta_layer == null:
		_meta_layer = CanvasLayer.new()
		_meta_layer.layer = 20
		add_child(_meta_layer)
	var scene = null
	# v1.5：优先新角色/行囊面板，其次旧 meta_panel，最后内置兜底
	var candidates: Array = [CHARACTER_PANEL_PATH, META_PANEL_PATH]
	for path in candidates:
		var p := String(path)
		if not ResourceLoader.exists(p):
			continue
		var packed = load(p)
		if packed is PackedScene:
			scene = (packed as PackedScene).instantiate()
			if scene != null and scene.has_method("open_panel") and scene.has_signal("closed"):
				break
			if scene != null:
				scene.free()
				scene = null
	var compatible: bool = scene != null and scene.has_method("open_panel") and scene.has_signal("closed")
	if compatible:
		_meta_panel = scene
	else:
		if scene != null and is_instance_valid(scene):
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

# ================= 绘制 =================

func _draw() -> void:
	var length := FateConfig.CORRIDOR_LENGTH
	var floor_y := FateConfig.CORRIDOR_FLOOR_Y
	if _bg_texture_v2 != null:
		_draw_background_parallax()
	else:
		_draw_fallback_far(length)
	# 远景旋转琉璃珠 + 守命者剪影（视差/固定构图）
	_draw_orb_and_guardian()
	# 地面
	draw_rect(Rect2(0.0, floor_y, length, FateConfig.VIEW_SIZE.y - floor_y), Color(0.05, 0.03, 0.09, 0.95))
	draw_line(Vector2(0.0, floor_y), Vector2(length, floor_y), Color(0.55, 0.45, 0.85, 0.55), 3.0)
	var tile_x := 0.0
	while tile_x < length:
		draw_line(Vector2(tile_x, floor_y + 8.0), Vector2(tile_x + 60.0, floor_y + 8.0), Color(0.42, 0.34, 0.66, 0.18), 2.0)
		tile_x += 120.0
	# 房间门（仅可见关卡；未解锁的隐藏关不绘制）
	var visible_max := mini(GameState.visible_max_level(), FateConfig.CORRIDOR_DOOR_X.size())
	for i in visible_max:
		_draw_door(i)
	# NPC（idle sprite 缺失时用程序化像素剪影兜底）
	_draw_npcs()
	_draw_vignette()

## v2 远景背景：0.35 视差 + 多块拼贴覆盖视口
func _draw_background_parallax() -> void:
	var tex := _bg_texture_v2
	var view_w := FateConfig.VIEW_SIZE.x
	var cam_x: float = camera.position.x if camera != null else player.position.x
	var offset := fposmod((cam_x - view_w * 0.5) * 0.35, view_w)
	var base := cam_x - view_w * 0.5 - offset - view_w
	for i in 3:
		draw_texture_rect(tex, Rect2(base + float(i) * view_w, 0.0, view_w, FateConfig.VIEW_SIZE.y), false,
			Color(0.92, 0.88, 1.0, 1.0))

## 程序化远景兜底：暗紫棕长廊 + 透视柱列 + 两侧黯淡命核光点
func _draw_fallback_far(length: float) -> void:
	draw_rect(Rect2(0.0, 0.0, length, FateConfig.VIEW_SIZE.y), Color(0.07, 0.05, 0.10))
	var bands := 16
	for i in bands:
		var t := float(i) / float(bands)
		var col := Color(0.07, 0.05, 0.10).lerp(Color(0.13, 0.09, 0.17), t)
		draw_rect(Rect2(0.0, t * FateConfig.VIEW_SIZE.y, length, FateConfig.VIEW_SIZE.y / float(bands) + 1.0), col)
	# 星尘/两侧黯淡命运珠
	for star in _stars:
		var pos: Vector2 = star["pos"]
		var a := float(star["alpha"])
		PX.rect(self, Rect2(pos, Vector2(4.0, 4.0)), Color(0.72, 0.68, 0.92, a))
		if int(pos.x) % 7 == 0:
			PX.rect(self, Rect2(pos + Vector2(-4.0, -4.0), Vector2(12.0, 12.0)), Color(0.45, 0.42, 0.72, a * 0.25))
	# 透视柱列：近处大、远处矮，营造纵深
	var x := 0.0
	var idx := 0
	while x < length:
		var depth := 0.35 + 0.65 * absf(sin(float(idx) * 0.7))
		var col_w := 18.0 + 26.0 * depth
		var top := 120.0 - 40.0 * depth
		draw_rect(Rect2(x - col_w * 0.5, top, col_w, FateConfig.CORRIDOR_FLOOR_Y - top),
			Color(0.10, 0.07, 0.15, 0.55 + 0.25 * depth))
		draw_rect(Rect2(x - col_w * 0.9, top - 12.0, col_w * 1.8, 14.0), Color(0.14, 0.10, 0.20, 0.7))
		PX.rect(self, Rect2(x - 4.0, top + 20.0, 8.0, 8.0), Color(0.55, 0.65, 1.0, 0.10 + 0.12 * depth))
		x += 210.0
		idx += 1

## 中部偏上：缓慢旋转的明亮命核珠；右侧偏下：模糊守命者上半身（下半身渐隐）
func _draw_orb_and_guardian() -> void:
	var cam_x: float = camera.position.x if camera != null else player.position.x
	var orb_pos := Vector2(cam_x - 110.0, 236.0)
	var pulse := 0.5 + 0.5 * sin(_time * 1.7)
	if _orb_texture != null:
		draw_set_transform(orb_pos, _orb_angle, Vector2(1.1, 1.1))
		draw_texture_rect(_orb_texture, Rect2(-96.0, -96.0, 192.0, 192.0), false, Color(0.72, 0.82, 1.0, 0.30 + 0.16 * pulse))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_set_transform(orb_pos, _orb_angle * 1.7, Vector2(0.72, 0.72))
		draw_texture_rect(_orb_texture, Rect2(-96.0, -96.0, 192.0, 192.0), false, Color(1.0, 0.96, 0.9, 0.85))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		PX.disc(self, orb_pos, 54.0 + 6.0 * pulse, Color(0.55, 0.68, 1.0, 0.10 + 0.06 * pulse))
		PX.disc(self, orb_pos, 26.0, Color(0.85, 0.90, 1.0, 0.85))
		PX.ring(self, orb_pos, 34.0, Color(0.55, 0.70, 1.0, 0.55), 1)
		for k in 6:
			var ang := _orb_angle + TAU * float(k) / 6.0
			PX.rect(self, Rect2(orb_pos + Vector2(cos(ang), sin(ang)) * 46.0 - Vector2(2.0, 2.0), Vector2(4.0, 4.0)),
				Color(0.7, 0.8, 1.0, 0.35))
	# 守命者：画面右侧偏下，上半身清晰、下半身渐隐
	var gpos := Vector2(cam_x + 380.0, 420.0)
	if _guardian_texture != null:
		var size := Vector2(430.0, 640.0)
		draw_texture_rect(_guardian_texture, Rect2(gpos - size * 0.5, size), false, Color(0.62, 0.58, 0.78, 0.62))
	else:
		var body_h := 300.0
		var cloak := PackedVector2Array([
			gpos + Vector2(-120.0, 170.0), gpos + Vector2(-96.0, -40.0),
			gpos + Vector2(-60.0, -120.0), gpos + Vector2(0.0, -160.0),
			gpos + Vector2(60.0, -120.0), gpos + Vector2(96.0, -40.0),
			gpos + Vector2(120.0, 170.0),
		])
		draw_colored_polygon(cloak, Color(0.10, 0.08, 0.15, 0.62))
		PX.disc(self, gpos + Vector2(0.0, -150.0), 42.0, Color(0.12, 0.10, 0.17, 0.7))
		PX.ring(self, gpos + Vector2(0.0, -150.0), 42.0, Color(0.45, 0.52, 0.78, 0.35), 1)
		# 下半身用竖条渐隐（不画过实的腿）
		for k in 6:
			var a := 0.30 - float(k) * 0.045
			draw_rect(Rect2(gpos.x - 120.0 + float(k) * 8.0, gpos.y + 40.0 + float(k) * 18.0, 240.0 - float(k) * 16.0, 18.0),
				Color(0.10, 0.08, 0.15, maxf(a, 0.0)))
	# 守命者区域轻微暗角
	draw_rect(Rect2(cam_x + 220.0, 120.0, 420.0, 520.0), Color(0.02, 0.01, 0.04, 0.12))

## 暗角：上方/两侧渐暗，压抑感
func _draw_vignette() -> void:
	var cam_x: float = camera.position.x if camera != null else player.position.x
	var left: float = cam_x - FateConfig.VIEW_SIZE.x * 0.5
	for k in 5:
		var a := 0.20 - float(k) * 0.035
		draw_rect(Rect2(left + float(k) * 12.0, 0.0, 12.0, FateConfig.VIEW_SIZE.y), Color(0.02, 0.01, 0.04, a))
		draw_rect(Rect2(left + FateConfig.VIEW_SIZE.x - float(k + 1) * 12.0, 0.0, 12.0, FateConfig.VIEW_SIZE.y), Color(0.02, 0.01, 0.04, a))
		draw_rect(Rect2(left, float(k) * 14.0, FateConfig.VIEW_SIZE.x, 14.0), Color(0.02, 0.01, 0.04, a * 1.4))

## NPC 程序化兜底绘制 + 当前关 NPC 的柔光标记
func _draw_npcs() -> void:
	var current := clampi(GameState.level - 1, 0, maxi(_npcs.size() - 1, 0))
	for i in _npcs.size():
		if i < _npc_hidden.size() and bool(_npc_hidden[i]):
			continue
		var pos: Vector2 = _npcs[i]
		var alpha: float = float(_npc_alpha[i]) if i < _npc_alpha.size() else 1.0
		var color := Color(1.0, 0.92, 0.7) if i == current else Color(0.55, 0.50, 0.72)
		color.a *= alpha
		# 当前 NPC：脚下柔光
		if i == current:
			var pulse := 0.5 + 0.5 * sin(_time * 2.5)
			PX.rect(self, Rect2(pos.x - 24.0, pos.y - 2.0, 48.0, 4.0), Color(0.91, 0.76, 0.42, (0.25 + 0.2 * pulse) * alpha))
		if _idle_texture != null:
			continue
		# 与玩家同形象的像素剪影
		var bob := sin(_time * 2.0 + float(i)) * 1.5
		PX.disc(self, Vector2(pos.x, pos.y - 42.0 + bob), 11.0, Color(0.10, 0.07, 0.16, alpha))
		var cloak := PackedVector2Array([
			Vector2(pos.x - 14.0, pos.y), Vector2(pos.x - 12.0, pos.y - 26.0),
			Vector2(pos.x - 6.0, pos.y - 42.0 + bob), Vector2(pos.x, pos.y - 48.0 + bob),
			Vector2(pos.x + 6.0, pos.y - 42.0 + bob), Vector2(pos.x + 12.0, pos.y - 26.0),
			Vector2(pos.x + 14.0, pos.y),
		])
		draw_colored_polygon(cloak, Color(0.16, 0.12, 0.26, alpha))
		draw_polyline(cloak, Color(color.r, color.g, color.b, 0.55), 2.0)
		PX.rect(self, Rect2(pos.x - 3.0, pos.y - 32.0, 6.0, 6.0), Color(0.65, 0.82, 1.0, 0.9 * alpha))

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
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 手机切后台 / 关闭窗口：保存进行中的一局，便于续关
		GameState.save_game()

func _unhandled_input(event: InputEvent) -> void:
	if _entering:
		return
	var screen_pos := _pressed_screen_pos(event)
	if screen_pos.x < 0.0:
		return
	# 1) 对话中：进入试炼 / 推进打字机（触屏兜底）
	if _dialog_state != 0:
		if _dialog_enter_btn != null and _dialog_enter_btn.visible \
			and _dialog_enter_btn.get_global_rect().has_point(screen_pos):
			get_viewport().set_input_as_handled()
			_on_dialog_enter_pressed()
			return
		get_viewport().set_input_as_handled()
		if _dialog_state == 1:
			_finish_typing()
		elif _dialog_state == 2 and _dialog_enter_btn != null:
			_dialog_enter_btn.visible = true
		return
	# 2) 交互按钮兜底（真机触摸未走 Button.pressed 时）
	if _interact_btn != null and _interact_btn.visible and _npc_near \
		and _interact_btn.get_global_rect().has_point(screen_pos):
		get_viewport().set_input_as_handled()
		try_open_npc_dialog()
		return
	# 3) 进入试炼按钮兜底
	if _enter_btn != null and _enter_btn.visible and _enter_btn.get_global_rect().has_point(screen_pos):
		get_viewport().set_input_as_handled()
		_enter_room()
		return
	# 4) 世界点击：主角 / 当前关 NPC
	if screen_pos.x < 280.0 and screen_pos.y > 520.0:
		return
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	_handle_world_click(world_pos)

## 取出按下事件的屏幕坐标（鼠标左键 / 触屏）
func _pressed_screen_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			return mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			return st.position
	return Vector2(-1.0, -1.0)

## 点击主角 → 个人信息面板；点击当前关 NPC → 直接对话（触屏）
func _handle_world_click(world_pos: Vector2) -> void:
	if player != null and absf(world_pos.x - player.position.x) < 60.0 \
		and world_pos.y > player.position.y - 210.0 and world_pos.y < player.position.y + 12.0:
		_open_meta_panel()
		get_viewport().set_input_as_handled()
		return
	var index := GameState.level - 1
	if index < 0 or index >= mini(GameState.visible_max_level(), _npcs.size()):
		return
	if bool(_npc_hidden[index]) or GameState.is_npc_seen(GameState.level):
		return
	var npc_pos: Vector2 = _npcs[index]
	if absf(world_pos.x - npc_pos.x) < 60.0 \
		and world_pos.y > npc_pos.y - 210.0 and world_pos.y < npc_pos.y + 12.0 \
		and absf(player.position.x - npc_pos.x) < FateConfig.NPC_INTERACT_RADIUS:
		_trigger_npc_dialog(index)
		get_viewport().set_input_as_handled()

func _goto_menu() -> void:
	if _entering:
		return
	_entering = true
	# 返回标题不结束本局（保留 run_active 供「继续试炼」），仅保存
	GameState.save_game()
	Audio.play_bgm("menu")
	if ResourceLoader.exists(MENU_SCENE_PATH):
		var err := get_tree().change_scene_to_file(MENU_SCENE_PATH)
		if err != OK:
			_entering = false

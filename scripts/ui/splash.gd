extends Control
## 《！？珠珠？！》v1.5 极简启动页（备用，不再作为默认入口）。
##
## Lead 已将 project.godot 主场景改回 res://scenes/main_menu.tscn；本场景保留为极简备用：
##   黑底 / 淡星尘 → 像素 studio 徽记淡入 → 副标题 → 「点击任意处进入」→ 主菜单。
## 不含健康游戏忠告、发行商 logo、加载条、版号/适龄等平台化元素。
##
## 只读使用 FateConfig / FateUI；不直接书写 Autoload 标识符（--check-only 兼容）。

const UI := preload("res://scripts/ui/ui_theme.gd")

const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const LOGO_PATH := "res://assets/art/splash_logo.png"

## 允许点击进入的最短时间（秒），让 logo 淡入完成。
const MIN_SHOW_TIME := 0.9

var _ready_for_input := false
var _busy := false
var _hint: Label = null
var _logo: TextureRect = null


func _ready() -> void:
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)

	_build_background()
	_build_logo()
	_build_hint()

	UI.play_bgm("menu")
	_after_intro.call_deferred()


func _build_background() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(black)
	add_child(black)

	var stars := StarField.new()
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(stars)
	add_child(stars)


func _build_logo() -> void:
	_logo = TextureRect.new()
	_logo.name = "StudioLogo"
	_logo.texture = _load_texture(LOGO_PATH)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.position = Vector2(240.0, 250.0)
	_logo.size = Vector2(800.0, 224.0)
	_logo.pivot_offset = Vector2(400.0, 112.0)
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(1.02, 1.02)
	add_child(_logo)

	# logo 缺失时兜底：用标题字体现画 studio 名。
	var fallback := UI.title(FateConfig.SPLASH_STUDIO, 46, FateConfig.COLOR_GOLD)
	fallback.position = Vector2(240.0, 296.0)
	fallback.size = Vector2(800.0, 92.0)
	fallback.modulate.a = 0.0
	fallback.visible = _logo.texture == null
	add_child(fallback)

	var subtitle := UI.label(FateConfig.GAME_SUBTITLE, 19,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(0.0, 486.0)
	subtitle.size = Vector2(1280.0, 28.0)
	subtitle.modulate.a = 0.0
	add_child(subtitle)

	var tween := create_tween()
	tween.tween_property(_logo, "modulate:a", 1.0, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_logo, "scale", Vector2.ONE, 1.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if fallback.visible:
		tween.parallel().tween_property(fallback, "modulate:a", 1.0, 0.8)
	tween.tween_property(subtitle, "modulate:a", 1.0, 0.5)


func _build_hint() -> void:
	_hint = UI.label("点击任意处进入命运回廊", 15,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.position = Vector2(0.0, 660.0)
	_hint.size = Vector2(1280.0, 26.0)
	_hint.modulate.a = 0.0
	add_child(_hint)


func _after_intro() -> void:
	await get_tree().create_timer(MIN_SHOW_TIME).timeout
	_ready_for_input = true
	var tween := create_tween()
	tween.tween_property(_hint, "modulate:a", 1.0, 0.4)
	tween.tween_property(_hint, "modulate:a", 0.45, 0.9)
	tween.tween_property(_hint, "modulate:a", 1.0, 0.9)
	tween.set_loops()


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_for_input or _busy:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_enter()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_enter()
	elif event.is_action_pressed("ui_accept"):
		_enter()


func _enter() -> void:
	if _busy:
		return
	_busy = true
	UI.play_sfx("click")
	if get_tree() != null:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


## 读取纹理：优先资源导入结果；未导入时直接读 PNG（桌面/自测可用），避免空白。
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# ==================================================================
# 极简星空（内联绘制）
# ==================================================================

class StarField extends Control:
	var _stars: Array = []
	var _time := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260410
		for i in 60:
			_stars.append({
				"pos": Vector2(rng.randf_range(8.0, 1272.0),
						rng.randf_range(8.0, 712.0)),
				"size": 2.0 if rng.randf() < 0.12 else 1.0,
				"alpha": rng.randf_range(0.10, 0.45),
				"speed": rng.randf_range(0.5, 1.8),
				"phase": rng.randf_range(0.0, TAU),
			})
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		for entry in _stars:
			var p: Vector2 = entry["pos"]
			var size: float = entry["size"]
			var twinkle := 0.55 + 0.45 * sin(_time * float(entry["speed"])
					+ float(entry["phase"]))
			var c := Color(0.78, 0.74, 0.92, float(entry["alpha"]) * twinkle)
			draw_rect(Rect2(p, Vector2(size, size)), c, true)

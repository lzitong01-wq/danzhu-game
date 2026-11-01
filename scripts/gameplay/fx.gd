extends Node2D
## 玩法层视觉特效（像素风）：命中粒子（小方块）、飘字、镜头轻震、全屏闪色。
## 全部使用程序化绘制，不依赖任何美术资源；缺失资源时同样可以工作。

const PX := preload("res://scripts/gameplay/px.gd")

## 主相机（震屏用，可为 null）
var camera: Camera2D = null

## 粒子列表，每项：{pos, vel, life, max_life, color, radius, gravity}
var _particles: Array = []
## 飘字用的随机数
var _rng := RandomNumberGenerator.new()
## 闪屏层
var _flash_layer: CanvasLayer = null
var _flash_rect: ColorRect = null
var _shake_tween: Tween = null
var _ui_font: Font = null

func _ready() -> void:
	z_index = 50
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	_ui_font = _load_ui_font()
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 5
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_layer.add_child(_flash_rect)

## 绑定主相机，用于屏幕震动
func setup(cam: Camera2D) -> void:
	camera = cam

# ---------------- 字体 ----------------

func _load_ui_font() -> Font:
	var candidates: Array = [
		"res://assets/fonts/FateBody.ttf",
		"res://assets/fonts/FateTitle.ttf",
	]
	for p in candidates:
		var path := String(p)
		if not ResourceLoader.exists(path):
			continue
		var res = load(path)
		if res is Font:
			return res
	return ThemeDB.fallback_font

## UI/飘字使用的字体（其它玩法脚本也复用这里）
func ui_font() -> Font:
	if _ui_font == null:
		_ui_font = _load_ui_font()
	return _ui_font

# ---------------- 粒子 ----------------

## 在 pos 处爆一簇粒子
func burst(pos: Vector2, color: Color, count: int = 12, speed: float = 220.0, radius: float = 3.0, gravity: float = 520.0) -> void:
	for i in count:
		var ang := _rng.randf_range(0.0, TAU)
		var sp := _rng.randf_range(speed * 0.3, speed)
		var life := _rng.randf_range(0.25, 0.6)
		_particles.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * sp,
			"life": life,
			"max_life": life,
			"color": color,
			"radius": radius * _rng.randf_range(0.6, 1.35),
			"gravity": gravity,
		})
	queue_redraw()

func _process(delta: float) -> void:
	if _particles.is_empty():
		return
	var alive: Array = []
	for p in _particles:
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			continue
		var vel: Vector2 = p["vel"]
		vel.y += float(p["gravity"]) * delta
		p["vel"] = vel
		p["pos"] = Vector2(p["pos"]) + vel * delta
		alive.append(p)
	_particles = alive
	queue_redraw()

func _draw() -> void:
	for p in _particles:
		var life := float(p["life"])
		var max_life := maxf(float(p["max_life"]), 0.001)
		var alpha := clampf(life / max_life, 0.0, 1.0)
		var col: Color = p["color"]
		var pos: Vector2 = p["pos"]
		# 像素小方块粒子（4px）+ 低透明外发光方块
		PX.rect(self, Rect2(pos - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color(col.r, col.g, col.b, alpha * 0.12))
		PX.rect(self, Rect2(pos, Vector2(4.0, 4.0)), Color(col.r, col.g, col.b, alpha * 0.9))
		PX.rect(self, Rect2(pos, Vector2(2.0, 2.0)), Color(1.0, 1.0, 1.0, alpha * 0.8))

# ---------------- 飘字 ----------------

## 在世界坐标 pos 处生成一段上浮淡出的文字
func popup(text: String, pos: Vector2, color: Color = Color(1.0, 1.0, 1.0), size: int = 28) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", ui_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(320.0, 52.0)
	label.position = pos - Vector2(160.0, 26.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0.0, -72.0), 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.4)
	tween.finished.connect(label.queue_free)

# ---------------- 震屏 / 闪屏 ----------------

## 短促屏幕震动
func shake(strength: float = 6.0, duration: float = 0.22) -> void:
	if camera == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := 5
	var step_time := duration / float(steps + 1)
	for i in steps:
		var decay := 1.0 - float(i) / float(steps + 1)
		var off := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength * decay
		_shake_tween.tween_property(camera, "offset", off, step_time)
	_shake_tween.tween_property(camera, "offset", Vector2.ZERO, step_time)

## 全屏闪色（命中高倍槽位/虚空时使用）
func flash(color: Color, alpha: float = 0.3, duration: float = 0.45) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", alpha, duration * 0.25)
	tween.tween_property(_flash_rect, "color:a", 0.0, duration * 0.75)

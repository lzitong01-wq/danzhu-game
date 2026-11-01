extends Node2D
## 右侧弹簧发射器（v1.3，像素风）：安装在轨道底部 (1244,676)。
## 蓄力改为 0→1→0→1 的三角波来回摆动（单程约 CHARGE_TIME），松手取当前力度。
## 蓄力时在 ⑥ 区域绘制虚线轨迹预判（像素点）：沿轨道上行 + 出导流口后的抛物线落点。

signal launch_requested(power_t: float)

const PX := preload("res://scripts/gameplay/px.gd")

## 是否禁止蓄力（球在场上 / 准备阶段 / 结算阶段）
var locked: bool = true

var _charging: bool = false
var _charge: float = 0.0
var _charge_dir: float = 1.0
var _fx = null
var _font: Font = null

const HIT_RADIUS := 90.0
const BAR_X := 18.0
const BAR_BOTTOM := -18.0
const BAR_LENGTH := 190.0
const EXIT_LOCAL := Vector2(-34.0, -516.0)
const RAIL_RISE := 508.0

func _ready() -> void:
	position = FateConfig.LAUNCH_POS
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = _resolve_font()
	set_process(false)
	queue_redraw()

func setup(fx_node) -> void:
	_fx = fx_node

func _resolve_font() -> Font:
	if _fx != null and _fx.has_method("ui_font"):
		return _fx.ui_font()
	var candidates: Array = ["res://assets/fonts/FateBody.ttf", "res://assets/fonts/FateTitle.ttf"]
	for p in candidates:
		var path := String(p)
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Font:
				return res
	return ThemeDB.fallback_font

func set_locked(value: bool) -> void:
	locked = value
	if locked:
		_charging = false
		_charge = 0.0
		_charge_dir = 1.0
		set_process(false)
	queue_redraw()

## 当前力度（0..1，测试/轨迹预览可读）
func get_charge() -> float:
	return _charge

func _process(delta: float) -> void:
	if not _charging:
		return
	# 三角波来回摆动：0 → 1 → 0 → 1……
	_charge += _charge_dir * delta / FateConfig.CHARGE_TIME
	if _charge >= 1.0:
		_charge = 1.0
		_charge_dir = -1.0
	elif _charge <= 0.0:
		_charge = 0.0
		_charge_dir = 1.0
	queue_redraw()

# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_try_start_charge(_event_world(mb.position))
		else:
			_release_charge()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_try_start_charge(_event_world(touch.position))
		else:
			_release_charge()

func _event_world(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return screen_pos
	return vp.get_canvas_transform().affine_inverse() * screen_pos

func _try_start_charge(world_pos: Vector2) -> void:
	if locked or _charging:
		return
	if world_pos.distance_to(global_position) > HIT_RADIUS:
		return
	_charging = true
	_charge = 0.0
	_charge_dir = 1.0
	set_process(true)
	queue_redraw()

func _release_charge() -> void:
	if not _charging:
		return
	_charging = false
	set_process(false)
	var t := clampf(_charge, 0.0, 1.0)
	_charge = 0.0
	_charge_dir = 1.0
	queue_redraw()
	if locked:
		return
	launch_requested.emit(t)

# ---------------- 像素风绘制 ----------------

func _draw() -> void:
	var font := _font
	if font == null:
		font = ThemeDB.fallback_font
	# 弹簧底座
	PX.disc(self, Vector2(0.0, 6.0), 22.0, Color(0.07, 0.05, 0.12, 0.95))
	PX.disc(self, Vector2(0.0, 4.0), 16.0, Color(0.14, 0.11, 0.22, 0.98))
	PX.ring(self, Vector2(0.0, 4.0), 20.0, Color(0.36, 0.30, 0.55, 0.9), 1)
	# 弹簧线圈：4px 方块横杆
	for i in 3:
		var y := -8.0 - float(i) * 8.0
		PX.rect(self, Rect2(-16.0, y, 32.0, 4.0), Color(0.55, 0.50, 0.70, 0.55))
	var head_color := FateConfig.COLOR_GOLD
	if locked:
		head_color = FateConfig.COLOR_TEXT_DIM
	elif _charging:
		head_color = FateConfig.COLOR_GOLD.lerp(FateConfig.COLOR_CRIMSON, _charge)
	PX.disc(self, Vector2(0.0, -38.0), 12.0, Color(head_color.r, head_color.g, head_color.b, 0.25))
	PX.rect(self, Rect2(-8.0, -46.0, 16.0, 16.0), head_color)
	PX.rect(self, Rect2(-8.0, -46.0, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.85))
	# 力度条
	PX.rect(self, Rect2(BAR_X - 3.0, BAR_BOTTOM - BAR_LENGTH, 6.0, BAR_LENGTH), Color(0.08, 0.06, 0.12, 0.9))
	PX.rect(self, Rect2(BAR_X - 4.0, BAR_BOTTOM - BAR_LENGTH - 4.0, 8.0, 4.0), Color(0.42, 0.34, 0.66, 0.7))
	if _charge > 0.001:
		var fill_h := BAR_LENGTH * _charge
		var fill_color := FateConfig.COLOR_GOLD.lerp(FateConfig.COLOR_CRIMSON, _charge)
		PX.rect(self, Rect2(BAR_X - 3.0, BAR_BOTTOM - fill_h, 6.0, fill_h), fill_color)
	if _charging and _charge > 0.001:
		_draw_prediction(_charge)
	# 提示文字
	var text := "按住右下弹簧蓄力 · 松手发射"
	var text_color := FateConfig.COLOR_TEXT_DIM
	if locked:
		text = "弹珠运行中…"
	elif _charging:
		text = "力度 %d%%" % int(round(_charge * 100.0))
		text_color = FateConfig.COLOR_GOLD
	draw_string(font, Vector2(-584.0, -536.0), text, HORIZONTAL_ALIGNMENT_LEFT, 420.0, 20, text_color)

## 像素点虚线轨迹：竖直上行段 + 出导流口后的抛物线 + 落点标记
func _draw_prediction(charge: float) -> void:
	var speed := lerpf(FateConfig.LAUNCH_POWER_MIN, FateConfig.LAUNCH_POWER_MAX, charge)
	var next_index := GameState.balls_total - GameState.balls_left
	var pred_color := FateConfig.COLOR_GOLD
	if next_index >= 0 and next_index < GameState.ball_slots.size():
		var card := GameState.get_ball_card(next_index)
		if card == "powercard":
			speed *= 1.3
		elif card == "shrinkcard":
			speed *= FateConfig.SHRINK_SPEED_MULT
		if card != "":
			pred_color = Color(1.0, 0.45, 0.48)
	# 上行段
	var y := -24.0
	while y > -RAIL_RISE:
		PX.rect(self, Rect2(-2.0, y, 4.0, 4.0), Color(pred_color.r, pred_color.g, pred_color.b, 0.55))
		y -= 26.0
	# 抛物线
	var gravity := 980.0 * FateConfig.BALL_GRAVITY_SCALE
	var residual := maxf(speed * speed - 2.0 * gravity * RAIL_RISE, 0.0)
	var vx := FateConfig.BALL_BOUNCE * sqrt(residual)
	var pos := EXIT_LOCAL
	var vel := Vector2(-vx, 0.0)
	var step_dt := 1.0 / 60.0
	var steps := 0
	var last := pos
	while steps < 240:
		vel.y += gravity * step_dt
		pos += vel * step_dt
		steps += 1
		if steps % 3 == 0:
			PX.rect(self, Rect2(pos.x - 2.0, pos.y - 2.0, 4.0, 4.0), Color(pred_color.r, pred_color.g, pred_color.b, 0.42))
		last = pos
		if pos.y >= -60.0 or pos.x <= -588.0:
			break
	# 落点十字
	PX.rect(self, Rect2(last.x - 8.0, last.y - 2.0, 16.0, 4.0), Color(pred_color.r, pred_color.g, pred_color.b, 0.85))
	PX.rect(self, Rect2(last.x - 2.0, last.y - 8.0, 4.0, 16.0), Color(pred_color.r, pred_color.g, pred_color.b, 0.85))

extends Control
## 虚拟摇杆（P1 走廊左下，像素风）：固定圆盘 JOYSTICK_CENTER / JOYSTICK_RADIUS。
## 触摸拖动（多点触控取第一根手指），桌面鼠标拖动同样可用；键盘移动由 corridor.gd 读取。
## 对外只暴露 `vector`（-1..1 的二维方向）与 `active`。

const PX := preload("res://scripts/gameplay/px.gd")

## 当前方向（长度 0..1）
var vector := Vector2.ZERO
var active: bool = false

var _knob := Vector2.ZERO
var _touch_index := -1
var _mouse_active := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index == -1 and _within_activate(touch.position):
				_touch_index = touch.index
				active = true
				_update_knob(touch.position)
		else:
			if touch.index == _touch_index:
				_release()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if active and drag.index == _touch_index:
			_update_knob(drag.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not active and _within_activate(mb.position):
					_mouse_active = true
					active = true
					_update_knob(mb.position)
			elif _mouse_active:
				_release()
	elif event is InputEventMouseMotion:
		if active and _mouse_active:
			_update_knob((event as InputEventMouseMotion).position)

func _within_activate(screen_pos: Vector2) -> bool:
	return screen_pos.distance_to(FateConfig.JOYSTICK_CENTER) <= FateConfig.JOYSTICK_RADIUS * 1.8

func _update_knob(screen_pos: Vector2) -> void:
	var offset := screen_pos - FateConfig.JOYSTICK_CENTER
	if offset.length() > FateConfig.JOYSTICK_RADIUS:
		offset = offset.normalized() * FateConfig.JOYSTICK_RADIUS
	_knob = offset
	vector = offset / FateConfig.JOYSTICK_RADIUS
	queue_redraw()

func _release() -> void:
	active = false
	vector = Vector2.ZERO
	_knob = Vector2.ZERO
	_touch_index = -1
	_mouse_active = false
	queue_redraw()

func _draw() -> void:
	var center := FateConfig.JOYSTICK_CENTER
	var radius := FateConfig.JOYSTICK_RADIUS
	# 像素底盘
	PX.disc(self, center, radius, Color(0.06, 0.04, 0.10, 0.55))
	PX.ring(self, center, radius, Color(0.42, 0.34, 0.66, 0.6), 1)
	PX.ring(self, center, radius * 0.55, Color(0.42, 0.34, 0.66, 0.25), 1)
	# 摇杆头（像素方块）
	var knob := center + _knob
	var color := FateConfig.COLOR_GOLD if active else FateConfig.COLOR_TEXT_DIM
	PX.disc(self, knob, 30.0, Color(0.10, 0.07, 0.17, 0.92))
	PX.disc(self, knob, 24.0, Color(0.18, 0.13, 0.28, 0.95))
	PX.ring(self, knob, 30.0, color, 1)
	PX.rect(self, Rect2(knob + Vector2(-6.0, -7.0), Vector2(8.0, 8.0)), Color(1.0, 1.0, 1.0, 0.18))
	# 方向刻度
	for i in 4:
		var ang := float(i) * PI * 0.5
		var p0 := center + Vector2(cos(ang), sin(ang)) * (radius - 10.0)
		var p1 := center + Vector2(cos(ang), sin(ang)) * (radius - 2.0)
		draw_line(p0, p1, Color(0.42, 0.34, 0.66, 0.45), 2.0)

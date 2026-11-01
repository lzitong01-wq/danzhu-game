extends Area2D
## 槽位（随机框）：球落入即结算。绘制框底色、×倍率与随机奖励小字。
## v1.2 倍率/奖励来自 GameState.get_slot_config(i)；视觉由 board.gd 注入。

signal ball_entered(ball: Node)

## 槽位序号（0..5，自左向右）
var slot_index: int = 0
## 槽位倍率（用于显示；实际结算由 game 读 GameState.get_pocket_mult）
var multiplier: float = 1.0
## 框奖励文字（如「金币+2」「再射一球」，空串表示无）
var bonus_text: String = ""
## 槽位矩形（世界坐标，用于绘制与默认碰撞）
var slot_rect: Rect2 = Rect2()
## 碰撞矩形（可选）：最外侧槽位向挡墙方向延伸，避免贴墙落球从边缝坠空
var collision_rect: Rect2 = Rect2()
## 特效节点引用（可为 null）
var fx = null

var _font: Font = null

func _ready() -> void:
	add_to_group("slot")
	set_meta("slot_index", slot_index)
	set_meta("multiplier", multiplier)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = true
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	var hit_rect := collision_rect if collision_rect.size.x > 0.0 else slot_rect
	rect_shape.size = hit_rect.size
	shape.shape = rect_shape
	shape.position = hit_rect.position + hit_rect.size * 0.5 - position
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_font = _resolve_font()
	queue_redraw()

func _resolve_font() -> Font:
	if fx != null and fx.has_method("ui_font"):
		return fx.ui_font()
	var candidates: Array = ["res://assets/fonts/FateBody.ttf", "res://assets/fonts/FateTitle.ttf"]
	for p in candidates:
		var path := String(p)
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Font:
				return res
	return ThemeDB.fallback_font

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group("ball"):
		return
	ball_entered.emit(body)

func _mult_text() -> String:
	if absf(multiplier - round(multiplier)) < 0.01:
		return "×%d" % int(round(multiplier))
	return "×%.1f" % multiplier

func _draw() -> void:
	var size := slot_rect.size
	var half := size * 0.5
	var local := Rect2(-half, size)
	var fill := Color(0.18, 0.13, 0.30, 0.22)
	var edge := Color(0.36, 0.30, 0.55, 0.55)
	var text_color := FateConfig.COLOR_TEXT_DIM
	if multiplier >= 3.0:
		fill = Color(0.90, 0.76, 0.40, 0.30)
		edge = FateConfig.COLOR_GOLD
		text_color = FateConfig.COLOR_GOLD
	elif multiplier >= 1.5:
		fill = Color(0.43, 0.88, 0.69, 0.20)
		edge = FateConfig.COLOR_JADE
		text_color = FateConfig.COLOR_JADE
	elif multiplier <= 0.0:
		fill = Color(0.02, 0.01, 0.05, 0.85)
		edge = FateConfig.COLOR_VIOLET_DIM
		text_color = FateConfig.COLOR_VIOLET
	# 框底（像素方框）
	draw_rect(local, fill)
	# 顶边高光（4px 像素边）
	draw_rect(Rect2(-half.x, -half.y, size.x, 4.0), edge)
	draw_rect(Rect2(-half.x, -half.y, 4.0, size.y), Color(edge.r, edge.g, edge.b, 0.45))
	draw_rect(Rect2(half.x - 4.0, -half.y, 4.0, size.y), Color(edge.r, edge.g, edge.b, 0.45))
	# 随机奖励的小字（金币+2 / 再射一球）
	if bonus_text != "":
		draw_rect(Rect2(-half.x + 6.0, half.y - 30.0, size.x - 12.0, 24.0), Color(0.05, 0.03, 0.09, 0.55))
	var font := _font
	if font == null:
		font = ThemeDB.fallback_font
	var baseline := -half.y + size.y * 0.40
	draw_string(font, Vector2(-half.x, baseline), _mult_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, text_color)
	var name := FateConfig.SLOT_NAMES[clampi(slot_index, 0, FateConfig.SLOT_NAMES.size() - 1)]
	draw_string(font, Vector2(-half.x, baseline + 22.0), name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(edge.r, edge.g, edge.b, 0.75))
	if bonus_text != "":
		draw_string(font, Vector2(-half.x, half.y - 10.0), bonus_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, FateConfig.COLOR_GOLD)

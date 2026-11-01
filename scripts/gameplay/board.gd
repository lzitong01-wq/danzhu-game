extends Node2D
## 弹珠台 v1.3（P1 布局，像素风，程序化构建）：
## - 台面右半屏：左墙 x=640、顶 y=112、右边界为发射轨道 x=1216
## - 右侧弹簧轨道 1216..1272（y 140..704），顶部导流斜面 A(1216,140)→B(1272,196)
## - ⑤ 错落立柱阵 6×7（奇数行横移半列距），6 种区域 / 黑柱白柱 / 绿柱真实碰撞连线
## - ⑥ 运动改变区：球进台面后关闭轨道缺口（GATE_RECT）
## 所有节点运行时生成，game.tscn 不需要手写子节点。

signal slot_hit(ball: Node, slot_index: int, mult: float, world_pos: Vector2)

const PEG_SCRIPT := preload("res://scripts/gameplay/peg.gd")
const SLOT_SCRIPT := preload("res://scripts/gameplay/slot.gd")
const GUARDIAN_SCRIPT := preload("res://scripts/gameplay/guardian.gd")
const PX := preload("res://scripts/gameplay/px.gd")

## 特效节点（game.gd 注入）
var fx = null

var pegs: Array = []
var slots: Array = []
## 绿色相邻连线：[[Vector2, Vector2], ...]
var links: Array = []
var guardian = null

var _stars: Array = []
var _bg_texture: Texture2D = null
var _gate_body: StaticBody2D = null
var _gate_shape: CollisionShape2D = null
var _gate_closed := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prepare_backdrop()

## 注入特效节点（add_child 之前调用）
func setup(fx_node) -> void:
	fx = fx_node

# ================= 构建 =================

## 清空台面（重进房间时使用），背景保留
func clear_board() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	pegs.clear()
	slots.clear()
	links.clear()
	guardian = null
	_gate_body = null
	_gate_shape = null
	_gate_closed = false
	queue_redraw()

## 生成整张台面（关卡规则从 GameState 读取）
func build() -> void:
	clear_board()
	_build_walls()
	_build_gate()
	_build_pegs()
	_build_slots()
	_build_guardian()
	queue_redraw()

func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 1
	# 台面左墙（内表面 x=640，y 112..704）
	_add_box_shape(walls, Vector2(632.0, 408.0), Vector2(16.0, 592.0))
	# 顶墙（内表面 y=112，覆盖到轨道右侧）
	_add_box_shape(walls, Vector2(962.0, 104.0), Vector2(644.0, 16.0))
	# 右侧轨道左墙（内表面 x=1216，y 250..704；y<250 是进入台面的缺口）
	_add_box_shape(walls, Vector2(1210.0, 477.0), Vector2(12.0, 454.0))
	# 右侧轨道右墙（内表面 x=1272，y 196..704）
	_add_box_shape(walls, Vector2(1278.0, 450.0), Vector2(12.0, 508.0))
	# 轨道底部弹簧挡板（内表面 y=704）：回落的球会被弹起而不是掉出屏幕
	_add_box_shape(walls, Vector2(1244.0, 710.0), Vector2(56.0, 12.0))
	# 顶部导流斜面：旋转矩形，A(1216,140) → B(1272,196)
	var deflector := StaticBody2D.new()
	deflector.name = "Deflector"
	deflector.collision_layer = 1
	deflector.collision_mask = 1
	deflector.position = (FateConfig.DEFLECTOR_A + FateConfig.DEFLECTOR_B) * 0.5
	deflector.rotation = deg_to_rad(45.0)
	_add_box_shape(deflector, Vector2.ZERO, Vector2(96.0, 14.0))
	add_child(deflector)
	add_child(walls)
	_build_slot_dividers()

## ⑥ 运动改变区：轨道缺口 Gate（默认打开，球进台面后关闭）
func _build_gate() -> void:
	_gate_body = StaticBody2D.new()
	_gate_body.name = "Gate"
	_gate_body.collision_layer = 1
	_gate_body.collision_mask = 1
	var rect := FateConfig.GATE_RECT
	_gate_shape = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	_gate_shape.shape = shape
	_gate_shape.position = rect.position + rect.size * 0.5
	_gate_shape.disabled = true
	_gate_body.add_child(_gate_shape)
	add_child(_gate_body)
	_gate_closed = false

## 关闭/打开轨道缺口（关闭后球无法从台面反弹回轨道）
func set_gate_closed(closed: bool) -> void:
	_gate_closed = closed
	if _gate_shape != null and is_instance_valid(_gate_shape):
		_gate_shape.set_deferred("disabled", not closed)
	queue_redraw()

func is_gate_closed() -> bool:
	return _gate_closed

func _build_slot_dividers() -> void:
	var dividers := StaticBody2D.new()
	dividers.name = "SlotDividers"
	dividers.collision_layer = 1
	dividers.collision_mask = 1
	for x in _slot_boundaries():
		_add_box_shape(dividers, Vector2(x, 656.0), Vector2(8.0, 80.0))
	add_child(dividers)

func _add_box_shape(body: StaticBody2D, center: Vector2, box_size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = box_size
	collision.shape = rect_shape
	collision.position = center
	body.add_child(collision)

## 6 槽位的 x 分界点（7 个值，自左向右，来自 SLOT_RECT + SLOT_WEIGHTS）
func _slot_boundaries() -> Array:
	var rect := FateConfig.SLOT_RECT
	var x := rect.position.x
	var out: Array = [x]
	for weight in FateConfig.SLOT_WEIGHTS:
		x += rect.size.x * float(weight)
		out.append(x)
	return out

func _build_pegs() -> void:
	var area := FateConfig.PEG_AREA
	var cell := Vector2(area.size.x / float(FateConfig.PEG_COLS), area.size.y / float(FateConfig.PEG_ROWS))
	var types: Array = []
	for row in FateConfig.PEG_ROWS:
		# 奇数行整体横移半个列距 → 六列七行错落排布
		var offset_x := cell.x * FateConfig.PEG_ROW_OFFSET_RATIO if row % 2 == 1 else 0.0
		for col in FateConfig.PEG_COLS:
			var pos := Vector2(
				area.position.x + (float(col) + 0.5) * cell.x + offset_x,
				area.position.y + (float(row) + 0.5) * cell.y)
			pos += Vector2(randf_range(-FateConfig.PEG_JITTER, FateConfig.PEG_JITTER),
				randf_range(-FateConfig.PEG_JITTER, FateConfig.PEG_JITTER))
			# 限制在立柱区内：右侧要给轨道墙留出厚度，避免立柱嵌进墙里
			var max_x := minf(area.end.x - FateConfig.PEG_RADIUS, FateConfig.RAIL_LEFT - 12.0 - FateConfig.PEG_RADIUS)
			pos.x = clampf(pos.x, area.position.x + FateConfig.PEG_RADIUS, max_x)
			var peg_type := _roll_peg_type()
			types.append(peg_type)
			var peg = PEG_SCRIPT.new()
			peg.peg_type = peg_type
			peg.position = pos
			add_child(peg)
			pegs.append(peg)
	# 绿色立柱相邻（横/竖/斜 8 邻接）：记录辉光连线 + 生成真实线段碰撞体
	for row in FateConfig.PEG_ROWS:
		for col in FateConfig.PEG_COLS:
			var idx: int = row * FateConfig.PEG_COLS + col
			if int(types[idx]) != FateConfig.PEG_TYPE_GREEN:
				continue
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nr: int = row + dr
					var nc: int = col + dc
					if nr < 0 or nr >= FateConfig.PEG_ROWS or nc < 0 or nc >= FateConfig.PEG_COLS:
						continue
					var nidx: int = nr * FateConfig.PEG_COLS + nc
					if nidx <= idx:
						continue
					if int(types[nidx]) != FateConfig.PEG_TYPE_GREEN:
						continue
					var pa: Vector2 = pegs[idx].position
					var pb: Vector2 = pegs[nidx].position
					links.append([pa, pb])
					_add_link_segment(pa, pb)

## 绿色连线：StaticBody2D + SegmentShape2D，弹珠撞线会被再次反弹
func _add_link_segment(a: Vector2, b: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "GreenLink"
	body.collision_layer = 1
	body.collision_mask = 1
	var collision := CollisionShape2D.new()
	var segment := SegmentShape2D.new()
	segment.a = a
	segment.b = b
	collision.shape = segment
	body.add_child(collision)
	add_child(body)

## 按权重抽取立柱类型；第 3 关普通柱消失，其余权重重新归一化
func _roll_peg_type() -> int:
	var weights := FateConfig.PEG_WEIGHTS
	var allowed: Array = []
	if GameState.is_normal_pegs_removed():
		for i in range(1, weights.size()):
			allowed.append(i)
	else:
		for i in weights.size():
			allowed.append(i)
	var total := 0
	for i in allowed:
		total += int(weights[i])
	if total <= 0:
		return FateConfig.PEG_TYPE_YELLOW
	var roll := randi() % total
	var acc := 0
	for i in allowed:
		acc += int(weights[i])
		if roll < acc:
			return i
	return FateConfig.PEG_TYPE_NORMAL

func _build_slots() -> void:
	var rect := FateConfig.SLOT_RECT
	var x := rect.position.x
	for i in FateConfig.SLOT_WEIGHTS.size():
		var width: float = rect.size.x * float(FateConfig.SLOT_WEIGHTS[i])
		var slot_rect := Rect2(x, rect.position.y, width, rect.size.y)
		x += width
		var slot = SLOT_SCRIPT.new()
		slot.slot_index = i
		slot.multiplier = GameState.get_pocket_mult(i)
		slot.bonus_text = _bonus_text(GameState.get_pocket_bonus(i))
		slot.slot_rect = slot_rect
		slot.fx = fx
		slot.position = slot_rect.position + slot_rect.size * 0.5
		# 最外侧槽位的碰撞区延伸到左右挡墙，避免贴墙落下时从 16px 边缝坠空
		if i == 0:
			slot.collision_rect = Rect2(FateConfig.BOARD_LEFT, slot_rect.position.y, slot_rect.position.x + slot_rect.size.x - FateConfig.BOARD_LEFT, slot_rect.size.y)
		elif i == FateConfig.SLOT_WEIGHTS.size() - 1:
			slot.collision_rect = Rect2(slot_rect.position.x, slot_rect.position.y, FateConfig.RAIL_LEFT - slot_rect.position.x, slot_rect.size.y)
		add_child(slot)
		slots.append(slot)
		slot.connect("ball_entered", Callable(self, "_on_slot_ball_entered").bind(slot))

func _bonus_text(bonus_id: String) -> String:
	if bonus_id == "":
		return ""
	for entry in FateConfig.POCKET_BONUS_POOL:
		if String(entry.get("id", "")) == bonus_id:
			return String(entry.get("name", bonus_id))
	return bonus_id

func _on_slot_ball_entered(ball: Node, slot) -> void:
	if ball == null or slot == null:
		return
	var index := int(slot.get_meta("slot_index", 0))
	var mult := float(slot.get_meta("multiplier", 1.0))
	slot_hit.emit(ball, index, mult, slot.global_position)

func _build_guardian() -> void:
	guardian = GUARDIAN_SCRIPT.new()
	guardian.fx = fx
	add_child(guardian)

# ================= 装备落点 =================

## 把装备应用到离 world_pos 最近的立柱（40px 内）；成功返回 true
func equip_at(world_pos: Vector2, item_id: String) -> bool:
	if not FateConfig.ITEMS.has(item_id):
		return false
	if String(FateConfig.ITEMS[item_id].get("kind", "")) != "equipment":
		return false
	var best = null
	var best_dist := 40.0
	for peg in pegs:
		if peg == null or not is_instance_valid(peg):
			continue
		if String(peg.equipped) != "":
			continue
		var dist: float = peg.position.distance_to(world_pos)
		if dist < best_dist:
			best_dist = dist
			best = peg
	if best == null:
		return false
	best.equip(item_id)
	if fx != null:
		fx.burst(best.position, FateConfig.COLOR_GOLD if item_id == "reflector" else FateConfig.COLOR_JADE, 14, 220.0)
		fx.shake(2.0)
	return true

# ================= 背景 / 绘制 =================

func _prepare_backdrop() -> void:
	var path := "res://assets/art/bg_board.png"
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_bg_texture = tex
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for i in 90:
		var star_color := FateConfig.COLOR_TEXT.lerp(FateConfig.COLOR_VIOLET, rng.randf())
		_stars.append({
			"pos": Vector2(rng.randf_range(0.0, 1280.0), rng.randf_range(0.0, 720.0)),
			"radius": rng.randf_range(0.8, 2.0),
			"alpha": rng.randf_range(0.06, 0.3),
			"color": star_color,
		})
	queue_redraw()

func _draw() -> void:
	var view := FateConfig.VIEW_SIZE
	# 全屏背景（像素色带）
	if _bg_texture != null:
		draw_texture_rect(_bg_texture, Rect2(Vector2.ZERO, view), false)
	else:
		PX.gradient(self, Rect2(Vector2.ZERO, view), FateConfig.COLOR_BG_DEEP, FateConfig.COLOR_BG_LOW, 14)
		for star in _stars:
			var c: Color = star["color"]
			var p: Vector2 = star["pos"]
			PX.rect(self, Rect2(p, Vector2(4.0, 4.0)), Color(c.r, c.g, c.b, float(star["alpha"])))
	# 台面面板（方角像素框）
	var board_rect := Rect2(FateConfig.BOARD_LEFT, FateConfig.BOARD_TOP, FateConfig.RAIL_RIGHT - FateConfig.BOARD_LEFT, FateConfig.RAIL_BOTTOM - FateConfig.BOARD_TOP)
	PX.rect(self, board_rect, Color(0.55, 0.45, 0.85, 0.03))
	PX.rect(self, Rect2(board_rect.position, Vector2(board_rect.size.x, 4.0)), Color(0.42, 0.34, 0.66, 0.45))
	PX.rect(self, Rect2(board_rect.position + Vector2(0.0, board_rect.size.y - 4.0), Vector2(board_rect.size.x, 4.0)), Color(0.42, 0.34, 0.66, 0.45))
	PX.rect(self, Rect2(board_rect.position, Vector2(4.0, board_rect.size.y)), Color(0.42, 0.34, 0.66, 0.45))
	PX.rect(self, Rect2(board_rect.position + Vector2(board_rect.size.x - 4.0, 0.0), Vector2(4.0, board_rect.size.y)), Color(0.42, 0.34, 0.66, 0.45))
	# 右侧发射轨道
	var rail_rect := Rect2(FateConfig.RAIL_LEFT, FateConfig.RAIL_TOP, FateConfig.RAIL_RIGHT - FateConfig.RAIL_LEFT, FateConfig.RAIL_BOTTOM - FateConfig.RAIL_TOP)
	PX.rect(self, rail_rect, Color(0.04, 0.02, 0.08, 0.92))
	PX.stair_line(self, Vector2(FateConfig.RAIL_LEFT, FateConfig.RAIL_TOP), Vector2(FateConfig.RAIL_LEFT, FateConfig.RAIL_BOTTOM), Color(0.55, 0.45, 0.85, 0.35), 4.0)
	PX.stair_line(self, Vector2(FateConfig.RAIL_RIGHT, FateConfig.RAIL_TOP), Vector2(FateConfig.RAIL_RIGHT, FateConfig.RAIL_BOTTOM), Color(0.55, 0.45, 0.85, 0.35), 4.0)
	PX.stair_line(self, Vector2(FateConfig.RAIL_LEFT, FateConfig.RAIL_BOTTOM), Vector2(FateConfig.RAIL_RIGHT, FateConfig.RAIL_BOTTOM), Color(0.55, 0.45, 0.85, 0.55), 4.0)
	# 弹簧区域装饰（像素环）
	PX.ring(self, FateConfig.LAUNCH_POS, 32.0, Color(0.55, 0.45, 0.85, 0.28), 1)
	# 顶部导流斜面（像素粗线）
	var a := FateConfig.DEFLECTOR_A
	var b := FateConfig.DEFLECTOR_B
	PX.stair_line(self, a, b, Color(0.43, 0.88, 0.69, 0.20), 12.0)
	PX.stair_line(self, a, b, Color(0.43, 0.88, 0.69, 0.85), 4.0)
	# ⑥ Gate：关闭时画金色像素虚线框
	var gate := FateConfig.GATE_RECT
	if _gate_closed:
		var dash_y := gate.position.y
		while dash_y < gate.end.y:
			PX.rect(self, Rect2(gate.position.x, dash_y, gate.size.x, 4.0), Color(0.91, 0.76, 0.42, 0.55))
			dash_y += 12.0
		PX.rect(self, gate, Color(0.91, 0.76, 0.42, 0.16))
	else:
		draw_rect(gate, Color(0.43, 0.88, 0.69, 0.10), false, 2.0)
	# 导流方向提示（阶梯弧）
	PX.band(self, Vector2(1150.0, 210.0), 70.0, -PI * 0.55, -PI * 0.05, Color(0.90, 0.76, 0.40, 0.25), 1, 18)
	# 台面左墙 / 顶墙描边
	PX.stair_line(self, Vector2(FateConfig.BOARD_LEFT, FateConfig.BOARD_TOP), Vector2(FateConfig.BOARD_LEFT, FateConfig.RAIL_BOTTOM), Color(0.42, 0.34, 0.66, 0.7), 4.0)
	PX.stair_line(self, Vector2(FateConfig.BOARD_LEFT, FateConfig.BOARD_TOP), Vector2(FateConfig.RAIL_RIGHT, FateConfig.BOARD_TOP), Color(0.42, 0.34, 0.66, 0.7), 4.0)
	# 绿色立柱辉光连线（像素粗线）
	for pair in links:
		var pa: Vector2 = pair[0]
		var pb: Vector2 = pair[1]
		PX.stair_line(self, pa, pb, Color(0.43, 0.88, 0.69, 0.16), 8.0)
		PX.stair_line(self, pa, pb, Color(0.43, 0.88, 0.69, 0.55), 4.0)
	# 槽位分界
	for x in _slot_boundaries():
		PX.stair_line(self, Vector2(x, FateConfig.SLOT_TOP), Vector2(x, FateConfig.SLOT_TOP + 84.0), Color(0.42, 0.34, 0.66, 0.7), 4.0)

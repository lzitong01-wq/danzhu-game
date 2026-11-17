extends RigidBody2D
## 弹珠 v1.4（像素风）：右侧弹簧 → 轨道 → 导流斜面 → 错落立柱阵 → 随机框。
##
## 三种琉璃珠：type 0 命运(5) / 1 命核(10) / 2 命源(20)，基础分由 GameState.get_ball_base(type) 结算。
## 关卡 buff：重力×1.15（命运重压）、反弹+10%（回廊之风）、撞柱 30% 随机转向（因果回响）、
##           绿柱/绿线累计 N 次自毁（裂隙侵蚀）、万流归宗破命期间不灭。
## 卡牌：powercard/splitcard/masscard/shrinkcard（与 v1.3 相同）；分裂副球继承 type。
## 物理兜底：去超时虚空；卡住救援（低速 1.2s → 冲量，最多 4 次 → 传送台面中央）。

signal peg_hit(peg_type: int, world_pos: Vector2, equipped: String)
signal fell_out(world_pos: Vector2)
signal white_coin(world_pos: Vector2)
signal stuck_at(world_pos: Vector2)
signal split_requested(world_pos: Vector2, velocity: Vector2)
signal eroded(world_pos: Vector2)
signal recalled(world_pos: Vector2, ball_type: int)

const PX := preload("res://scripts/gameplay/px.gd")

const MAX_SPEED := 1800.0
const STUCK_SPEED := 35.0
const STUCK_TIME := 1.2
const STUCK_MAX_RESCUES := 4
const TELEPORT_POS := Vector2(900.0, 260.0)

## 0=命运 / 1=命核 / 2=命源
var type: int = 0
var advanced: bool = false
var card: String = ""
var buffed: bool = false
var radius_scale: float = 1.0
var yellow_hits: int = 0
var black_hits: int = 0
var green_hits: int = 0
var settled: bool = false
var stuck: bool = false
var is_masscard: bool = false
## 万流归宗：破命期间弹珠不灭
var immortal: bool = false

var _stuck_rescues: int = 0
var _split_done: bool = false
var _stick_timer: float = 0.0
var _stuck_time: float = 0.0
var _out_emitted: bool = false
var _trail: Line2D = null
var _sprite: Sprite2D = null
var _green_flash: float = 0.0
var _flash_timer: float = 0.0
var _chaos_flash: float = 0.0
var _eroded: bool = false

func _ready() -> void:
	add_to_group("ball")
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mass = 0.8
	gravity_scale = FateConfig.BALL_GRAVITY_SCALE * GameState.get_gravity_mult()
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.02
	angular_damp = 0.1
	if type >= FateConfig.BALL_TYPE_CORE:
		advanced = true
	is_masscard = card == "masscard"
	buffed = card != ""
	var mat := PhysicsMaterial.new()
	var bounce := FateConfig.BALL_BOUNCE + GameState.get_bounce_bonus()
	mat.bounce = clampf(FateConfig.MASS_BOUNCE if is_masscard else bounce, 0.05, 0.95)
	mat.friction = 0.1
	physics_material_override = mat
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _radius()
	shape.shape = circle
	add_child(shape)
	_sprite = _make_sprite()
	if _sprite != null:
		add_child(_sprite)
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = 4.0
	_trail.default_color = _trail_color()
	_trail.begin_cap_mode = Line2D.LINE_CAP_BOX
	_trail.end_cap_mode = Line2D.LINE_CAP_BOX
	_trail.joint_mode = Line2D.LINE_JOINT_SHARP
	_trail.z_index = -1
	add_child(_trail)
	body_entered.connect(_on_body_entered)
	queue_redraw()

func _radius() -> float:
	return FateConfig.BALL_RADIUS * radius_scale

func _trail_color() -> Color:
	if card != "":
		return Color(1.0, 0.40, 0.42, 0.62)
	match type:
		FateConfig.BALL_TYPE_SOURCE:
			return Color(1.0, 0.85, 0.40, 0.65)
		FateConfig.BALL_TYPE_CORE:
			return Color(0.70, 0.55, 1.0, 0.6)
		_:
			return Color(0.95, 0.80, 0.40, 0.55)

func _ball_color() -> Color:
	if card != "":
		return Color(1.0, 0.45, 0.48)
	match type:
		FateConfig.BALL_TYPE_SOURCE:
			return Color(1.0, 0.86, 0.38)
		FateConfig.BALL_TYPE_CORE:
			return Color(0.72, 0.60, 1.0)
		_:
			return Color(0.95, 0.82, 0.45)

func _make_sprite() -> Sprite2D:
	var path := "res://assets/art/ball_advanced.png" if advanced else "res://assets/art/ball_normal.png"
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not (tex is Texture2D):
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * (_radius() * 2.6 / float(maxi(tex.get_width(), 1)))
	if type == FateConfig.BALL_TYPE_SOURCE:
		sprite.modulate = Color(1.2, 1.05, 0.55)
	return sprite

func _process(delta: float) -> void:
	if _trail != null:
		_trail.add_point(global_position)
		while _trail.get_point_count() > FateConfig.BALL_TRAIL_LENGTH:
			_trail.remove_point(0)
	var dirty := false
	if _green_flash > 0.0:
		_green_flash = maxf(_green_flash - delta * 3.0, 0.0)
		dirty = true
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta * 2.5, 0.0)
		dirty = true
	if _chaos_flash > 0.0:
		_chaos_flash = maxf(_chaos_flash - delta * 3.0, 0.0)
		dirty = true
	if dirty:
		queue_redraw()

func _physics_process(delta: float) -> void:
	if _eroded:
		return
	if stuck:
		_stick_timer -= delta
		if _stick_timer <= 0.0:
			release_stick()
		return
	var vel := linear_velocity
	if vel.length() > MAX_SPEED:
		linear_velocity = vel.normalized() * MAX_SPEED
	_stuck_check(delta)
	if global_position.y > 760.0 or global_position.x < -40.0 or global_position.x > 1320.0:
		_emit_fell_out()

## 卡住救援：低速持续 1.2s → 冲量（最多 4 次）→ 传送台面中央
func _stuck_check(delta: float) -> void:
	if settled or stuck:
		return
	if linear_velocity.length() < STUCK_SPEED:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time < STUCK_TIME:
		return
	_stuck_time = 0.0
	if _stuck_rescues < STUCK_MAX_RESCUES:
		_stuck_rescues += 1
		if global_position.x > FateConfig.RAIL_LEFT:
			linear_velocity = Vector2(0.0, -1500.0)
		else:
			var direction := (Vector2(900.0, 300.0) - global_position).normalized()
			linear_velocity = (direction * 520.0 + Vector2(0.0, -560.0)).limit_length(1100.0)
		_green_flash = 1.0
		_flash_timer = 1.0
		queue_redraw()
	else:
		global_position = TELEPORT_POS
		linear_velocity = Vector2(0.0, 360.0)
		_stuck_rescues = 0
		_flash_timer = 1.0
		queue_redraw()

func _emit_fell_out() -> void:
	if settled or _out_emitted:
		return
	# 万流归宗：破命期间弹珠不灭，直接送回台面中央
	if immortal:
		global_position = TELEPORT_POS
		linear_velocity = Vector2(0.0, 360.0)
		_flash_timer = 1.0
		queue_redraw()
		return
	_out_emitted = true
	fell_out.emit(global_position)

func stick() -> void:
	if settled or stuck or is_masscard:
		return
	stuck = true
	_stick_timer = FateConfig.STICK_SECONDS
	linear_velocity = Vector2.ZERO
	set_deferred("freeze", true)
	stuck_at.emit(global_position)
	queue_redraw()

func release_stick() -> void:
	if not stuck:
		return
	stuck = false
	set_deferred("freeze", false)
	_stick_timer = 0.0
	linear_velocity = Vector2(randf_range(-90.0, 90.0), -240.0)
	queue_redraw()

func is_stuck() -> bool:
	return stuck

## 绿柱/绿线接触：累计达到关卡上限（裂隙侵蚀）时自毁
func _on_green_contact() -> void:
	if immortal or _eroded:
		return
	green_hits += 1
	var limit := GameState.get_green_limit()
	_green_flash = 1.0
	queue_redraw()
	if limit > 0 and green_hits >= limit:
		_eroded = true
		settled = true
		eroded.emit(global_position)

func _on_body_entered(body: Node) -> void:
	if settled or _eroded or body == null:
		return
	if body.is_in_group("ball"):
		if is_masscard and body.has_method("release_stick") and bool(body.get("stuck")):
			body.call("release_stick")
		return
	# 绿色连线碰撞体：算作撞绿
	if String(body.name).begins_with("GreenLink"):
		_on_green_contact()
		return
	if not body.is_in_group("peg"):
		return
	var peg_type := int(body.get_meta("peg_type", FateConfig.PEG_TYPE_NORMAL))
	var equipped := String(body.get_meta("equipped", ""))
	peg_hit.emit(peg_type, global_position, equipped)
	if body.has_method("flash"):
		if peg_type == FateConfig.PEG_TYPE_BLACK:
			body.call("flash", Color(0.55, 0.32, 0.95))
		elif peg_type == FateConfig.PEG_TYPE_WHITE:
			body.call("flash", Color(1.0, 1.0, 1.0))
		else:
			body.call("flash")
	match peg_type:
		FateConfig.PEG_TYPE_YELLOW:
			yellow_hits += 1
		FateConfig.PEG_TYPE_GREEN:
			apply_central_impulse(Vector2(0.0, -mass * 300.0))
			_on_green_contact()
		FateConfig.PEG_TYPE_BLACK:
			black_hits += 1
		FateConfig.PEG_TYPE_WHITE:
			if body.has_method("try_white_coin") and bool(body.call("try_white_coin")):
				white_coin.emit(global_position)
	trigger_split()
	# 因果回响：撞柱后 30% 概率随机改变方向
	if not _eroded:
		var chaos := GameState.get_chaos_chance()
		if chaos > 0.0 and randf() < chaos:
			var speed := maxf(linear_velocity.length(), 300.0)
			linear_velocity = linear_velocity.rotated(randf_range(-1.6, 1.6))
			if linear_velocity.length() < 1.0:
				linear_velocity = Vector2(randf_range(-1.0, 1.0), -1.0).normalized() * speed
			_chaos_flash = 1.0
			queue_redraw()
	if equipped == "reflector":
		var v := linear_velocity
		var sp := v.length()
		if sp > 1.0:
			linear_velocity = v.normalized() * minf(sp * 1.3, 1700.0)
	elif equipped == "sticky" and not is_masscard:
		stick()
	elif equipped == "pass_chisel":
		# 穿命透障凿：穿过该柱（不再反弹）
		pass
	elif equipped == "spindle_nail":
		pass
	elif equipped == "rift_note":
		# 歧路回廊帖：随机传送到另一根立柱附近
		global_position = Vector2(randf_range(700.0, 1150.0), randf_range(220.0, 520.0))
		_flash_timer = 1.0
	elif equipped == "recall_pouch":
		# 归命拾珠囊：弹珠被收回（由 game 处理额外弹珠/60% 同型珠）
		if not _eroded:
			_eroded = true
			settled = true
			recalled.emit(global_position, type)

func trigger_split() -> void:
	if card != "splitcard" or _split_done:
		return
	_split_done = true
	split_requested.emit(global_position, linear_velocity)

func bounce_from(source: Vector2) -> void:
	if settled or stuck:
		return
	var away := global_position - source
	if away.length() < 0.001:
		away = Vector2(0.0, -1.0)
	away = away.normalized()
	var speed := maxf(linear_velocity.length(), 560.0)
	linear_velocity = (away * 0.72 + Vector2(0.0, -0.7)).normalized() * minf(speed * 1.12, MAX_SPEED)
	_green_flash = 1.0
	queue_redraw()

# ---------------- 像素风绘制 ----------------

func _draw() -> void:
	var radius := _radius()
	var color := _ball_color()
	# 命源珠：更大的金色光环
	var glow_extra := 4.0 if type == FateConfig.BALL_TYPE_SOURCE else 0.0
	PX.disc(self, Vector2.ZERO, radius + 6.0 + glow_extra, Color(color.r, color.g, color.b, 0.10))
	PX.disc(self, Vector2.ZERO, radius + 2.0, Color(color.r, color.g, color.b, 0.22))
	if _sprite == null:
		PX.disc(self, Vector2.ZERO, radius, Color(0.11, 0.08, 0.18, 1.0))
		PX.disc(self, Vector2(-2.0, -3.0), radius * 0.62, Color(color.r, color.g, color.b, 0.9))
		PX.rect(self, Rect2(-6.0, -7.0, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.85))
		PX.ring(self, Vector2.ZERO, radius + 1.0, Color(color.r, color.g, color.b, 0.8), 1)
	if type == FateConfig.BALL_TYPE_SOURCE:
		PX.ring(self, Vector2.ZERO, radius + 5.0, Color(1.0, 0.88, 0.45, 0.75), 1)
	if card != "":
		PX.ring(self, Vector2.ZERO, radius + 4.0, Color(1.0, 0.30, 0.32, 0.75), 1)
	if stuck:
		PX.ring(self, Vector2.ZERO, radius + 6.0, Color(0.43, 0.88, 0.69, 0.8), 1)
		for i in 4:
			var ang := float(i) * TAU / 4.0
			PX.stair_line(self, Vector2.ZERO, Vector2(cos(ang), sin(ang)) * (radius + 7.0), Color(0.43, 0.88, 0.69, 0.45), 2.0)
	if _green_flash > 0.0:
		PX.ring(self, Vector2.ZERO, radius + 5.0, Color(0.43, 0.88, 0.69, _green_flash), 1)
	if _flash_timer > 0.0:
		PX.ring(self, Vector2.ZERO, radius + 8.0, Color(1.0, 0.85, 0.35, _flash_timer * 0.9), 1)
	if _chaos_flash > 0.0:
		PX.ring(self, Vector2.ZERO, radius + 10.0, Color(0.9, 0.35, 1.0, _chaos_flash * 0.9), 1)

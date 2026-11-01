extends AnimatableBody2D
## 守命者（像素风）：命运回廊中的守护者。
## 在 y=566、x∈[260,1030] 之间匀速往返巡逻，撞到弹珠会把它弹开，
## 播放 guardian 音效并闪红光。绘制为“命运之眼”，guardian.png 存在时叠加贴图。

## 特效节点引用（由 board.gd 注入）
var fx = null

const PX := preload("res://scripts/gameplay/px.gd")

var _dir: float = 1.0
var _cooldown: float = 0.0
var _flash: float = 0.0
var _sprite: Sprite2D = null
var _area: Area2D = null

func _ready() -> void:
	add_to_group("guardian")
	collision_layer = 1
	collision_mask = 1
	sync_to_physics = true
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = Vector2((FateConfig.GUARDIAN_MIN_X + FateConfig.GUARDIAN_MAX_X) * 0.5, FateConfig.GUARDIAN_Y)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FateConfig.GUARDIAN_RADIUS
	shape.shape = circle
	add_child(shape)
	# 用一个略大的 Area2D 检测弹珠，AnimatableBody2D 本身不提供 body_entered 信号
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	_area.monitoring = true
	_area.monitorable = true
	var area_shape := CollisionShape2D.new()
	var area_circle := CircleShape2D.new()
	area_circle.radius = FateConfig.GUARDIAN_RADIUS + 8.0
	area_shape.shape = area_circle
	_area.add_child(area_shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)
	_sprite = _make_sprite()
	if _sprite != null:
		add_child(_sprite)
	queue_redraw()

func _make_sprite() -> Sprite2D:
	var path := "res://assets/art/guardian.png"
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not (tex is Texture2D):
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * (FateConfig.GUARDIAN_RADIUS * 3.4 / float(maxi(tex.get_width(), 1)))
	return sprite

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	position.x += _dir * FateConfig.GUARDIAN_SPEED * delta
	if position.x >= FateConfig.GUARDIAN_MAX_X:
		position.x = FateConfig.GUARDIAN_MAX_X
		_dir = -1.0
	elif position.x <= FateConfig.GUARDIAN_MIN_X:
		position.x = FateConfig.GUARDIAN_MIN_X
		_dir = 1.0

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()

func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("ball"):
		return
	if _cooldown > 0.0:
		return
	_cooldown = 0.35
	_flash = 1.0
	# 把球从守命者圆心向外弹开（并略微上挑），bounce_from 由 ball.gd 提供
	if body.has_method("bounce_from"):
		body.call("bounce_from", global_position)
	Audio.play_sfx("guardian")
	if fx != null:
		fx.burst(global_position, FateConfig.COLOR_CRIMSON, 12, 220.0)
		fx.flash(FateConfig.COLOR_CRIMSON, 0.10, 0.35)
		fx.shake(3.0)
	queue_redraw()

func _draw() -> void:
	var glow := 0.35 + _flash * 0.65
	var r := FateConfig.GUARDIAN_RADIUS
	# 命运之眼的红光（像素盘）
	PX.disc(self, Vector2.ZERO, r * 1.9, Color(1.0, 0.2, 0.3, 0.04 * glow))
	PX.disc(self, Vector2.ZERO, r * 1.35, Color(1.0, 0.25, 0.35, 0.09 * glow))
	PX.disc(self, Vector2.ZERO, r, Color(0.05, 0.02, 0.09, 0.95))
	PX.ring(self, Vector2.ZERO, r, Color(1.0, 0.28, 0.36, 0.55 + _flash * 0.4), 1)
	# 眼白与竖瞳（像素块）
	PX.disc(self, Vector2(0.0, -2.0), 12.0, Color(1.0, 0.30, 0.40, 0.9))
	PX.rect(self, Rect2(-4.0, -10.0, 8.0, 20.0), Color(0.03, 0.0, 0.04, 1.0))
	PX.rect(self, Rect2(-6.0, -10.0, 4.0, 4.0), Color(1.0, 0.92, 0.92, 0.9))
	# 底部阴影（阶梯弧）
	PX.band(self, Vector2.ZERO, r - 4.0, PI * 0.15, PI * 0.85, Color(0.5, 0.2, 0.9, 0.25), 1, 12)

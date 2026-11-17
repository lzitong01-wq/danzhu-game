extends Node2D
## 走廊主角 v1.6：用户 P1 抠图角色（ui-dev 生成 walk/idle 帧，72×222，6/4 帧，0.85x）。
## 不再重画人物；仅当贴图缺失时用程序化像素小人兜底。移动带加速度/摩擦、朝向翻转、帧动画与落地浮尘。

const PX := preload("res://scripts/gameplay/px.gd")

## 当前水平速度（由 corridor.gd 读取并推进位置）
var velocity_x: float = 0.0
var facing: float = 1.0

var _sprite: Sprite2D = null
var _walk_tex: Texture2D = null
var _idle_tex: Texture2D = null
var _frame_h := FateConfig.PLAYER_FRAME_SIZE.y
var _moving := false
var _anim_t := 0.0
var _t := 0.0
var _bob := 0.0
var _dust: Array = []
var _dust_timer := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	_load_textures()
	if _walk_tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = _walk_tex
		_sprite.hframes = FateConfig.PLAYER_WALK_FRAMES
		_sprite.vframes = 1
		_sprite.frame = 0
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.scale = Vector2.ONE * FateConfig.PLAYER_SCALE
		_sprite.z_index = 6
		# 精灵帧以中心为原点，脚底对齐到节点原点（用贴图实际帧高，兼容 ui 迭代尺寸）
		_frame_h = float(_walk_tex.get_height())
		_sprite.position = Vector2(0.0, -_frame_h * FateConfig.PLAYER_SCALE * 0.5)
		add_child(_sprite)
	queue_redraw()

func _load_textures() -> void:
	if ResourceLoader.exists(FateConfig.PLAYER_WALK_SPRITE):
		var tex = load(FateConfig.PLAYER_WALK_SPRITE)
		if tex is Texture2D:
			_walk_tex = tex
	if ResourceLoader.exists(FateConfig.PLAYER_IDLE_SPRITE):
		var tex2 = load(FateConfig.PLAYER_IDLE_SPRITE)
		if tex2 is Texture2D:
			_idle_tex = tex2

## 每帧由 corridor.gd 调用：dir ∈ [-1,1]，内部做加速度/摩擦与动画
func update_motion(dir: float, delta: float) -> void:
	var target := clampf(dir, -1.0, 1.0) * FateConfig.CORRIDOR_PLAYER_SPEED
	var accel := 2600.0 if absf(dir) > 0.01 else 2200.0
	velocity_x = move_toward(velocity_x, target, accel * delta)
	if absf(velocity_x) > 10.0:
		facing = signf(velocity_x)
	_moving = absf(velocity_x) > 15.0
	_t += delta
	if _sprite != null:
		_animate(delta)
	_spawn_dust(delta)

func _animate(delta: float) -> void:
	var walk := _moving and _walk_tex != null
	if walk:
		_sprite.texture = _walk_tex
		_sprite.hframes = FateConfig.PLAYER_WALK_FRAMES
	elif _idle_tex != null:
		_sprite.texture = _idle_tex
		_sprite.hframes = FateConfig.PLAYER_IDLE_FRAMES
	var frames := _sprite.hframes
	var speed_ratio := clampf(absf(velocity_x) / maxf(FateConfig.CORRIDOR_PLAYER_SPEED, 1.0), 0.0, 1.0)
	var fps := lerpf(8.0, 12.0, speed_ratio) if _moving else 4.0
	_anim_t += delta * fps
	_sprite.frame = int(_anim_t) % maxi(frames, 1)
	_sprite.flip_h = facing < 0.0
	# 行走时上下浮动，待机轻微呼吸
	_bob = sin(_t * 12.0) * 1.5 if _moving else sin(_t * 3.0) * 1.0
	_sprite.position.y = -_frame_h * FateConfig.PLAYER_SCALE * 0.5 + _bob

func _spawn_dust(delta: float) -> void:
	if not _moving:
		return
	_dust_timer -= delta
	if _dust_timer > 0.0:
		return
	_dust_timer = 0.12
	_dust.append({
		"pos": position + Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-2.0, 2.0)),
		"vel": Vector2(-signf(velocity_x) * _rng.randf_range(20.0, 70.0), _rng.randf_range(-30.0, -8.0)),
		"life": 0.4,
		"max_life": 0.4,
	})

func _process(delta: float) -> void:
	if _sprite == null:
		queue_redraw()
	if _dust.is_empty():
		return
	var alive: Array = []
	for p in _dust:
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			continue
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		alive.append(p)
	_dust = alive
	queue_redraw()

func get_speed() -> float:
	return velocity_x

func _draw() -> void:
	# 浮尘粒子（像素方块）
	for p in _dust:
		var alpha := clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0) * 0.5
		PX.rect(self, Rect2(Vector2(p["pos"]) - position, Vector2(4.0, 4.0)), Color(0.62, 0.55, 0.45, alpha))
	# 贴图缺失时的程序化像素小人兜底
	if _sprite != null:
		return
	var bob := sin(_t * 3.6) * 2.0
	PX.disc(self, Vector2(0.0, 2.0), 20.0, Color(0.02, 0.0, 0.05, 0.35))
	var cloak := PackedVector2Array([
		Vector2(-20.0, bob), Vector2(-18.0, -34.0 + bob), Vector2(-10.0, -58.0 + bob),
		Vector2(0.0, -66.0 + bob), Vector2(10.0, -58.0 + bob), Vector2(18.0, -34.0 + bob),
		Vector2(20.0, bob),
	])
	draw_colored_polygon(cloak, Color(0.14, 0.09, 0.24))
	draw_polyline(cloak, Color(0.55, 0.45, 0.85, 0.45), 2.0)
	PX.disc(self, Vector2(0.0, -56.0 + bob), 14.0, Color(0.10, 0.06, 0.17))
	PX.ring(self, Vector2(0.0, -56.0 + bob), 14.0, Color(0.55, 0.45, 0.85, 0.7), 1)
	var glow := 0.55 + 0.35 * sin(_t * 4.0)
	PX.disc(self, Vector2(0.0, -30.0 + bob), 8.0, Color(0.55, 0.75, 1.0, 0.14 * glow))
	PX.rect(self, Rect2(-4.0, -34.0 + bob, 8.0, 8.0), Color(0.65, 0.82, 1.0, 0.95))
	PX.rect(self, Rect2(-4.0, -34.0 + bob, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.9))
	draw_line(Vector2(-6.0, -2.0), Vector2(-8.0, bob), Color(0.14, 0.09, 0.24), 4.0)
	draw_line(Vector2(6.0, -2.0), Vector2(8.0, bob), Color(0.14, 0.09, 0.24), 4.0)

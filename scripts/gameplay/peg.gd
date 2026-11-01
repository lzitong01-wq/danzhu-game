extends StaticBody2D
## 立柱（P1 ⑤ 区，v1.3 五种，像素风）：
##   普通（灰）/ 黄色（金）/ 绿色（玉）/ 黑色（暗紫，撞到扣分）/ 白色（亮白，撞到概率给金币）
## 可被装备改造：reflector → 金色描边、反弹增强；sticky → 玉色描边、把球黏住 0.9s。
## 用 StaticBody2D + CircleShape2D，外观 _draw 程序化像素绘制；peg_*.png 存在则叠加贴图。

const PX := preload("res://scripts/gameplay/px.gd")

## 立柱类型，见 FateConfig.PEG_TYPE_*
var peg_type: int = 0
## 被装备改造的类型："" / "reflector" / "sticky"
var equipped: String = ""
## 白色立柱的“本关已撞次数”（跨球累计，每关重建时归零）
var white_hits: int = 0

var _flash: float = 0.0
var _flash_color := Color(1.0, 1.0, 1.0)
var _equip_flash: float = 0.0
var _sprite: Sprite2D = null

func _ready() -> void:
	add_to_group("peg")
	set_meta("peg_type", peg_type)
	set_meta("equipped", equipped)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = FateConfig.PEG_RADIUS
	shape.shape = circle
	add_child(shape)
	z_index = 2
	_sprite = _make_sprite()
	if _sprite != null:
		add_child(_sprite)
	set_process(false)
	queue_redraw()

func _make_sprite() -> Sprite2D:
	var path := "res://assets/art/peg_normal.png"
	match peg_type:
		FateConfig.PEG_TYPE_YELLOW:
			path = "res://assets/art/peg_yellow.png"
		FateConfig.PEG_TYPE_GREEN:
			path = "res://assets/art/peg_green.png"
		FateConfig.PEG_TYPE_BLACK:
			path = "res://assets/art/peg_black.png"
		FateConfig.PEG_TYPE_WHITE:
			path = "res://assets/art/peg_white.png"
	if not ResourceLoader.exists(path):
		return null
	var tex = load(path)
	if not (tex is Texture2D):
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * (FateConfig.PEG_RADIUS * 3.0 / float(maxi(tex.get_width(), 1)))
	return sprite

## 被装备改造（由 board.equip_at 调用）
func equip(item_id: String) -> void:
	equipped = item_id
	set_meta("equipped", item_id)
	_equip_flash = 1.0
	set_process(true)
	queue_redraw()

## 被弹珠撞击时闪一下；color 可指定闪光颜色（黑柱暗闪/白柱亮闪）
func flash(color: Color = Color(1.0, 1.0, 1.0)) -> void:
	_flash = 1.0
	_flash_color = color
	set_process(true)
	queue_redraw()

## 白色立柱：按 0.20 + 0.10*已撞次数 概率给 1 金币；返回是否命中
func try_white_coin() -> bool:
	var chance := FateConfig.WHITE_BASE_COIN_CHANCE + FateConfig.WHITE_CHANCE_STEP * float(white_hits)
	white_hits += 1
	return randf() < chance

func _process(delta: float) -> void:
	var dirty := false
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 5.0, 0.0)
		dirty = true
	if _equip_flash > 0.0:
		_equip_flash = maxf(_equip_flash - delta * 2.5, 0.0)
		dirty = true
	if dirty:
		queue_redraw()
	if _flash <= 0.0 and _equip_flash <= 0.0:
		set_process(false)

func _base_color() -> Color:
	match peg_type:
		FateConfig.PEG_TYPE_YELLOW:
			return FateConfig.COLOR_GOLD
		FateConfig.PEG_TYPE_GREEN:
			return FateConfig.COLOR_JADE
		FateConfig.PEG_TYPE_BLACK:
			return FateConfig.COLOR_BLACK_PEG
		FateConfig.PEG_TYPE_WHITE:
			return FateConfig.COLOR_WHITE_PEG
		_:
			return Color(0.66, 0.63, 0.76)

func _equip_color() -> Color:
	if equipped == "reflector":
		return FateConfig.COLOR_GOLD
	if equipped == "sticky":
		return FateConfig.COLOR_JADE
	return Color(0, 0, 0, 0)

func _draw() -> void:
	var base := _base_color()
	var hot := base.lerp(_flash_color, _flash * 0.85)
	var radius := FateConfig.PEG_RADIUS + _flash * 3.0
	# 像素外发光
	PX.disc(self, Vector2.ZERO, radius * 2.4, Color(base.r, base.g, base.b, 0.05 + _flash * 0.10))
	PX.disc(self, Vector2.ZERO, radius * 1.6, Color(base.r, base.g, base.b, 0.12 + _flash * 0.18))
	# 柱体（方角像素块）
	PX.disc(self, Vector2.ZERO, radius, Color(0.10, 0.08, 0.16, 0.98))
	PX.disc(self, Vector2.ZERO, radius - 2.0, Color(hot.r * 0.55, hot.g * 0.55, hot.b * 0.55, 1.0))
	PX.ring(self, Vector2.ZERO, radius, Color(hot.r, hot.g, hot.b, 0.85), 1)
	# 玻璃高光（2 个像素块）
	PX.rect(self, Rect2(-6.0, -8.0, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.28 + _flash * 0.4))
	PX.rect(self, Rect2(-2.0, -8.0, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.20 + _flash * 0.3))
	# 黑/白立柱额外标识
	if peg_type == FateConfig.PEG_TYPE_BLACK:
		PX.ring(self, Vector2.ZERO, radius, Color(0.62, 0.42, 0.95, 0.55), 1)
		PX.stair_line(self, Vector2(-6.0, -6.0), Vector2(6.0, 6.0), Color(0.45, 0.30, 0.70, 0.55), 2.0)
	elif peg_type == FateConfig.PEG_TYPE_WHITE:
		PX.ring(self, Vector2.ZERO, radius, Color(0.85, 0.95, 1.0, 0.9), 1)
		PX.rect(self, Rect2(-2.0, -2.0, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.35))
	# 装备改造描边
	if equipped != "":
		var ec := _equip_color()
		var pulse := 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
		PX.ring(self, Vector2.ZERO, radius + 5.0, Color(ec.r, ec.g, ec.b, pulse), 2)
		PX.disc(self, Vector2.ZERO, radius + 6.0, Color(ec.r, ec.g, ec.b, 0.06 + _equip_flash * 0.15))

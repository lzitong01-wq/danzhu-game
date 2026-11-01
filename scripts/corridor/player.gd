extends Node2D
## 走廊角色（像素风）：斗篷剪影 + 胸口命运琉璃光点，全部程序化绘制（不依赖美术资源）。

const PX := preload("res://scripts/gameplay/px.gd")

var facing: float = 1.0
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	var bob := sin(_t * 3.6) * 2.0
	# 地面影子（像素扁盘）
	PX.disc(self, Vector2(0.0, 2.0), 20.0, Color(0.02, 0.0, 0.05, 0.35))
	# 斗篷剪影（保持多边形，方角像素感）
	var cloak := PackedVector2Array([
		Vector2(-20.0, bob),
		Vector2(-18.0, -34.0 + bob),
		Vector2(-10.0, -58.0 + bob),
		Vector2(0.0, -66.0 + bob),
		Vector2(10.0, -58.0 + bob),
		Vector2(18.0, -34.0 + bob),
		Vector2(20.0, bob),
	])
	draw_colored_polygon(cloak, Color(0.14, 0.09, 0.24))
	draw_polyline(cloak, Color(0.55, 0.45, 0.85, 0.45), 2.0)
	# 兜帽（像素盘）
	PX.disc(self, Vector2(0.0, -56.0 + bob), 14.0, Color(0.10, 0.06, 0.17))
	PX.ring(self, Vector2(0.0, -56.0 + bob), 14.0, Color(0.55, 0.45, 0.85, 0.7), 1)
	# 胸口命运琉璃光点（像素块）
	var glow := 0.55 + 0.35 * sin(_t * 4.0)
	PX.disc(self, Vector2(0.0, -30.0 + bob), 8.0, Color(0.91, 0.76, 0.42, 0.12 * glow))
	PX.rect(self, Rect2(-4.0, -34.0 + bob, 8.0, 8.0), Color(0.95, 0.82, 0.50, 0.9))
	PX.rect(self, Rect2(-4.0, -34.0 + bob, 4.0, 4.0), Color(1.0, 1.0, 1.0, 0.9))
	# 双脚
	draw_line(Vector2(-6.0, -2.0), Vector2(-8.0, bob), Color(0.14, 0.09, 0.24), 4.0)
	draw_line(Vector2(6.0, -2.0), Vector2(8.0, bob), Color(0.14, 0.09, 0.24), 4.0)

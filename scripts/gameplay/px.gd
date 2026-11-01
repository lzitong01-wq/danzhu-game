extends RefCounted
## 像素风绘制工具（gameplay 层共用）：4px 对齐、方角、阶梯圆弧、像素方块粒子。
## 用法：const PX := preload("res://scripts/gameplay/px.gd")，然后 PX.disc(self, pos, r, color)。

const BLOCK := 4.0

## 把坐标向下对齐到 4px 网格
static func snap_vec(v: Vector2) -> Vector2:
	return Vector2(floor(v.x / BLOCK) * BLOCK, floor(v.y / BLOCK) * BLOCK)

## 对齐的方块矩形
static func rect(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var x: float = floor(r.position.x / BLOCK) * BLOCK
	var y: float = floor(r.position.y / BLOCK) * BLOCK
	var w := maxf(BLOCK, floor(r.size.x / BLOCK) * BLOCK)
	var h := maxf(BLOCK, floor(r.size.y / BLOCK) * BLOCK)
	ci.draw_rect(Rect2(x, y, w, h), color)

## 阶梯近似圆盘（像素块填充）
static func disc(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var cx: float = floor(center.x / BLOCK) * BLOCK
	var cy: float = floor(center.y / BLOCK) * BLOCK
	var blocks := int(floor(radius / BLOCK))
	for by in range(-blocks, blocks + 1):
		for bx in range(-blocks, blocks + 1):
			if bx * bx + by * by <= blocks * blocks:
				ci.draw_rect(Rect2(cx + float(bx) * BLOCK, cy + float(by) * BLOCK, BLOCK, BLOCK), color)

## 阶梯近似圆环
static func ring(ci: CanvasItem, center: Vector2, radius: float, color: Color, thickness_blocks: int = 1) -> void:
	var cx: float = floor(center.x / BLOCK) * BLOCK
	var cy: float = floor(center.y / BLOCK) * BLOCK
	var blocks := int(floor(radius / BLOCK))
	var inner := maxi(blocks - thickness_blocks, 0)
	for by in range(-blocks, blocks + 1):
		for bx in range(-blocks, blocks + 1):
			var d2 := bx * bx + by * by
			if d2 <= blocks * blocks and d2 > inner * inner:
				ci.draw_rect(Rect2(cx + float(bx) * BLOCK, cy + float(by) * BLOCK, BLOCK, BLOCK), color)

## 4px 步进的直线（端点对齐、宽度取 2 的倍数）
static func stair_line(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float = 4.0) -> void:
	var length := a.distance_to(b)
	var steps := maxi(int(ceil(length / BLOCK)), 1)
	var w := maxf(width, 2.0)
	w = ceil(w / 2.0) * 2.0
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		rect(ci, Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w)), color)

## 阶梯圆弧：角度采样后画小块（不做抗锯齿）
static func band(ci: CanvasItem, center: Vector2, radius: float, start_ang: float, end_ang: float, color: Color, width_blocks: int = 1, segments: int = 18) -> void:
	var r: float = floor(radius / BLOCK) * BLOCK
	var inner := maxf(r - BLOCK * float(width_blocks), 0.0)
	for i in segments + 1:
		var ang := lerpf(start_ang, end_ang, float(i) / float(segments))
		var dir := Vector2(cos(ang), sin(ang))
		rect(ci, Rect2(center + dir * r - Vector2(BLOCK, BLOCK) * 0.5, Vector2(BLOCK, BLOCK)), color)
		if width_blocks > 1:
			rect(ci, Rect2(center + dir * inner - Vector2(BLOCK, BLOCK) * 0.5, Vector2(BLOCK, BLOCK)), color)

## 像素渐变横带
static func gradient(ci: CanvasItem, r: Rect2, top: Color, bottom: Color, bands: int = 12) -> void:
	var width := maxf(floor(r.size.x / BLOCK) * BLOCK, BLOCK)
	var band_h := maxf(floor(r.size.y / float(bands) / BLOCK) * BLOCK, BLOCK)
	var x: float = floor(r.position.x / BLOCK) * BLOCK
	var y: float = floor(r.position.y / BLOCK) * BLOCK
	for i in bands:
		var t := float(i) / float(maxi(bands - 1, 1))
		ci.draw_rect(Rect2(x, y + float(i) * band_h, width, band_h + 1.0), top.lerp(bottom, t))

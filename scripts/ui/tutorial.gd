extends Control
## 《！？珠珠？！》v1.3 新手引导（像素风）。
##
## 半透明遮罩 + 高亮 ⑦ 道具区 / ⑤ 立柱阵 / ③ 弹珠灯，
## 小手动画从道具区分别指向立柱与弹珠灯。
## 接口见 docs/CONTRACT_V4.md 第 4 节：
##   func show_tutorial() -> void
##   signal closed

signal closed

const UI := preload("res://scripts/ui/ui_theme.gd")

var _built := false
var _hand: TextureRect = null
var _hand_tween: Tween = null


func _ready() -> void:
	_ensure_built()
	visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)
	_build_ui()


# ==================================================================
# 公共接口
# ==================================================================

func show_tutorial() -> void:
	if not _built:
		_ensure_built()
	visible = true
	_start_hand_animation()


# ==================================================================
# 构建
# ==================================================================

func _build_ui() -> void:
	add_child(UI.dim_overlay(0.74))

	# 高亮三块区域
	_add_highlight(FateConfig.ITEM_AREA, FateConfig.COLOR_GOLD, "1")
	_add_highlight(FateConfig.PEG_AREA, FateConfig.COLOR_JADE, "2")
	_add_highlight(FateConfig.HUD_CELL_BALL, FateConfig.COLOR_VIOLET, "2")

	# 三行说明
	var panel := PanelContainer.new()
	panel.position = Vector2(300.0, 462.0)
	panel.size = Vector2(680.0, 140.0)
	panel.custom_minimum_size = Vector2(680.0, 140.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.08, 0.06, 0.14, 0.96),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.85), 0, 3))
	add_child(panel)
	var box := UI.vbox(6)
	panel.add_child(box)
	box.add_child(UI.title("新手引导 · 拖动道具", 24, FateConfig.COLOR_GOLD))
	box.add_child(UI.label("① " + FateConfig.TUTORIAL_TEXT_1, 16,
			FateConfig.COLOR_TEXT))
	box.add_child(UI.label("② " + FateConfig.TUTORIAL_TEXT_2, 16,
			FateConfig.COLOR_TEXT))
	box.add_child(UI.label("③ " + FateConfig.TUTORIAL_TEXT_3, 16,
			FateConfig.COLOR_JADE))

	# 「知道了」
	var center := CenterContainer.new()
	center.position = Vector2(300.0, 616.0)
	center.size = Vector2(680.0, 70.0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var ok_btn := UI.button("知道了", 26, 64.0)
	ok_btn.custom_minimum_size = Vector2(240.0, 64.0)
	ok_btn.pressed.connect(_on_confirm)
	center.add_child(ok_btn)

	# 像素小手
	_hand = TextureRect.new()
	_hand.texture = UI.load_texture("res://assets/art/ui_hand.png")
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand.custom_minimum_size = Vector2(48.0, 48.0)
	_hand.size = Vector2(48.0, 48.0)
	_hand.position = Vector2(296.0, 300.0)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand)


func _add_highlight(rect: Rect2, color: Color, number: String) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_border_width_all(4)
	style.border_color = color
	style.bg_color = Color(color.r, color.g, color.b, 0.10)
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var badge := Panel.new()
	badge.position = rect.position + Vector2(rect.size.x - 36.0, 6.0)
	badge.size = Vector2(30.0, 30.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := StyleBoxFlat.new()
	badge_style.set_corner_radius_all(0)
	badge_style.set_border_width_all(2)
	badge_style.bg_color = Color(0.06, 0.045, 0.10, 0.98)
	badge_style.border_color = color
	badge.add_theme_stylebox_override("panel", badge_style)
	add_child(badge)

	var num := UI.label(number, 15, color, HORIZONTAL_ALIGNMENT_CENTER)
	num.position = Vector2.ZERO
	num.size = badge.size
	badge.add_child(num)


func _start_hand_animation() -> void:
	if _hand == null or not is_inside_tree():
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand.position = Vector2(296.0, 300.0)
	_hand_tween = create_tween()
	_hand_tween.set_loops()
	# ⑦ 道具区 -> ⑤ 立柱
	_hand_tween.tween_property(_hand, "position", Vector2(900.0, 330.0), 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hand_tween.tween_interval(0.45)
	# ⑤ 立柱 -> ③ 弹珠灯
	_hand_tween.tween_property(_hand, "position", Vector2(1000.0, 92.0), 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hand_tween.tween_interval(0.45)
	# 回到道具区
	_hand_tween.tween_property(_hand, "position", Vector2(296.0, 300.0), 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_hand_tween.tween_interval(0.35)


func _on_confirm() -> void:
	UI.play_sfx("click")
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	visible = false
	closed.emit()

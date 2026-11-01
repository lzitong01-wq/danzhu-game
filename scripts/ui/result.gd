extends Control
## 《？！珠珠！？》结算界面（由 gameplay 实例化并调用 show_result）。
##
## 接口见 docs/CONTRACT.md 5.3 / CONTRACT_V3 第 5 节：
##   show_result(victory, summary) / signal retry_pressed / signal menu_pressed
## summary: {"total_score":int,"shards":int,"is_new_best":bool,"best":int,"level":int,
##           "carried":{"balls_normal":int,"balls_advanced":int,"cards":Array}}
## 胜负音效由 gameplay 播放，本界面不重复播放。

signal retry_pressed
signal menu_pressed

const UI := preload("res://scripts/ui/ui_theme.gd")

const PANEL_SIZE := Vector2(800.0, 600.0)

var _gs := UI.game_state()
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _level_label: Label = null
var _score_value: Label = null
var _shards_value: Label = null
var _best_value: Label = null
var _carried_box: HBoxContainer = null
var _badge: Label = null
var _badge_tween: Tween = null
var _retry_btn: Button = null
var _built := false


func _ready() -> void:
	_ensure_built()
	visible = false


## 幂等构建：既支持正常的 _ready 流程，也支持接口在加入场景树前被提前调用。
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_gs = UI.game_state()
	theme = UI.build_theme()
	UI.set_full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


# ================= 构建界面 =================

func _build_ui() -> void:
	add_child(UI.dim_overlay(0.82))

	var glow := TextureRect.new()
	glow.texture = UI.load_texture("res://assets/art/particle_dot.png")
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2(390.0, 60.0)
	glow.size = Vector2(500.0, 360.0)
	glow.modulate = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.10)
	add_child(glow)

	_panel = PanelContainer.new()
	_panel.name = "ResultPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_SIZE.x * 0.5
	_panel.offset_top = -PANEL_SIZE.y * 0.5
	_panel.offset_right = PANEL_SIZE.x * 0.5
	_panel.offset_bottom = PANEL_SIZE.y * 0.5
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_panel_style(true))
	add_child(_panel)

	var root_box := UI.vbox(12)
	root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(root_box)

	_title = UI.title("胜 利", 70, FateConfig.COLOR_GOLD)
	root_box.add_child(_title)

	_subtitle = UI.label("", 20, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size = Vector2(620.0, 54.0)
	root_box.add_child(_subtitle)

	_level_label = UI.label("", 18, FateConfig.COLOR_VIOLET,
			HORIZONTAL_ALIGNMENT_CENTER)
	root_box.add_child(_level_label)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.38)
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(divider)

	# 三项数据
	var stats_row := UI.hbox(18)
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var score_panel := _make_stat_panel("本局总分")
	_score_value = score_panel.get_meta("value_label")
	stats_row.add_child(score_panel)
	var shards_panel := _make_stat_panel("获得命运碎片")
	_shards_value = shards_panel.get_meta("value_label")
	stats_row.add_child(shards_panel)
	var best_panel := _make_stat_panel("历史最高分")
	_best_value = best_panel.get_meta("value_label")
	stats_row.add_child(best_panel)
	root_box.add_child(stats_row)

	# 带出局外（v1.2）
	_carried_box = UI.hbox(8)
	_carried_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_carried_box.custom_minimum_size = Vector2(0.0, 34.0)
	root_box.add_child(_carried_box)

	_badge = UI.label("★ 新 纪 录 ★", 24, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	_badge.visible = false
	root_box.add_child(_badge)

	# 按钮
	var buttons := UI.hbox(24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var retry_btn := UI.button("再来一局", 28, 76.0)
	retry_btn.custom_minimum_size = Vector2(280.0, 76.0)
	retry_btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	retry_btn.pressed.connect(_on_retry_pressed)
	buttons.add_child(retry_btn)
	_retry_btn = retry_btn
	var menu_btn := UI.button("返回标题", 26, 76.0)
	menu_btn.custom_minimum_size = Vector2(220.0, 76.0)
	menu_btn.pressed.connect(_on_menu_pressed)
	buttons.add_child(menu_btn)
	root_box.add_child(buttons)


func _make_panel_style(victory: bool) -> StyleBoxFlat:
	var edge := FateConfig.COLOR_GOLD if victory else FateConfig.COLOR_CRIMSON
	return UI.panel_style(Color(0.10, 0.07, 0.17, 0.96),
			Color(edge.r, edge.g, edge.b, 0.72), 26, 2)


func _make_stat_panel(heading: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200.0, 112.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.14, 0.10, 0.23, 0.85),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.85), 16, 1))
	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(UI.label(heading, 17, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	var value := UI.label("0", 42, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value)
	panel.add_child(box)
	panel.set_meta("value_label", value)
	return panel


# ================= 公共接口 =================

## 显示结算。victory 为 true 时展示胜利样式，summary 见文件头注释。
func show_result(victory: bool, summary: Dictionary) -> void:
	if not _built:
		_ensure_built()
	var total_score := int(summary.get("total_score", 0))
	var shards := int(summary.get("shards", 0))
	var is_new_best := bool(summary.get("is_new_best", false))
	var best := int(summary.get("best", 0))
	if best <= 0 and _gs != null:
		best = _gs.best_score
	var level := int(summary.get("level", 1))

	_panel.add_theme_stylebox_override("panel", _make_panel_style(victory))
	_title.text = "胜 利" if victory else "失 败"
	_title.add_theme_color_override("font_color",
			FateConfig.COLOR_GOLD if victory else FateConfig.COLOR_CRIMSON)
	_title.add_theme_color_override("font_outline_color",
			Color(0.91, 0.76, 0.42, 0.30) if victory
			else Color(1.0, 0.36, 0.42, 0.30))

	if victory:
		_subtitle.text = "命运琉璃重归完整，回廊为你敞开。"
		_level_label.text = "三间命运房间全部通过 · 命运改写"
	else:
		_subtitle.text = "命运琉璃碎裂，但碎片已被你握在手中。"
		_level_label.text = "止步于第 %d 间 · %s" % [level,
				FateConfig.LEVEL_NAMES[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]]

	if _retry_btn != null:
		_retry_btn.text = "再来一局" if victory else "重试本关"

	_score_value.text = str(total_score)
	_shards_value.text = "+%d" % shards
	_shards_value.add_theme_color_override("font_color", FateConfig.COLOR_VIOLET)
	_best_value.text = str(best)

	_update_carried(summary)

	_badge.visible = is_new_best and victory
	if is_new_best:
		_start_badge_pulse()
	elif _badge_tween != null and _badge_tween.is_valid():
		_badge_tween.kill()

	visible = true
	_play_open_animation()


func _update_carried(summary: Dictionary) -> void:
	if _carried_box == null:
		return
	for child in _carried_box.get_children():
		_carried_box.remove_child(child)
		child.queue_free()
	var carried = summary.get("carried", {})
	if typeof(carried) != TYPE_DICTIONARY:
		carried = {}
	var normal := int(carried.get("balls_normal", 0))
	var advanced := int(carried.get("balls_advanced", 0))
	var cards: Array = carried.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		cards = []

	_carried_box.add_child(UI.label("带出局外", 13, FateConfig.COLOR_TEXT_DIM))
	var any := false
	if normal > 0:
		_carried_box.add_child(_make_carried_chip("ball_normal", "×%d" % normal))
		any = true
	if advanced > 0:
		_carried_box.add_child(_make_carried_chip("ball_advanced", "×%d" % advanced))
		any = true
	for id in cards:
		var card_id := String(id)
		var name := String(FateConfig.ITEMS.get(card_id, {}).get("name", card_id))
		_carried_box.add_child(_make_carried_chip(card_id, name))
		any = true
	if not any:
		_carried_box.add_child(UI.label("无（未带出任何弹珠或卡牌）", 12,
				FateConfig.COLOR_TEXT_DIM))


func _make_carried_chip(icon_name: String, text: String) -> Control:
	var chip := UI.hbox(4)
	if icon_name == "ball_normal" or icon_name == "ball_advanced":
		var ball_icon := TextureRect.new()
		ball_icon.texture = UI.load_texture(
				"res://assets/art/%s.png" % icon_name)
		ball_icon.custom_minimum_size = Vector2(24.0, 24.0)
		ball_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ball_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ball_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(ball_icon)
	else:
		chip.add_child(UI.item_icon(icon_name, 24.0))
	chip.add_child(UI.label(text, 13, FateConfig.COLOR_TEXT))
	return chip


# ================= 动画 / 按钮 =================

func _play_open_animation() -> void:
	if _panel == null or not is_inside_tree():
		return
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _start_badge_pulse() -> void:
	if _badge == null or not is_inside_tree():
		return
	if _badge_tween != null and _badge_tween.is_valid():
		_badge_tween.kill()
	_badge.modulate = Color.WHITE
	_badge_tween = create_tween()
	_badge_tween.set_loops()
	_badge_tween.tween_property(_badge, "modulate:a", 0.55, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_badge_tween.tween_property(_badge, "modulate:a", 1.0, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_retry_pressed() -> void:
	UI.play_sfx("click")
	retry_pressed.emit()


func _on_menu_pressed() -> void:
	UI.play_sfx("click")
	menu_pressed.emit()

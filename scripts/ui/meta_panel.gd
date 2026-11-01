extends Control
## 《？！珠珠！？》v1.2 局外行囊面板（跨局公共变量）。
##
## 展示 meta 弹珠/卡牌，勾选要带入下一局的内容（弹珠 ≤3、卡牌 ≤2）。
## 接口见 docs/CONTRACT_V3.md 第 5 节：
##   signal closed
##   func open_panel() -> void

signal closed

const UI := preload("res://scripts/ui/ui_theme.gd")

var _gs := UI.game_state()
var _built := false

var _panel: PanelContainer = null
var _ball_normal_label: Label = null
var _ball_advanced_label: Label = null
var _ball_normal_value: Label = null
var _ball_advanced_value: Label = null
var _normal_plus: Button = null
var _normal_minus: Button = null
var _advanced_plus: Button = null
var _advanced_minus: Button = null
var _ball_total_label: Label = null
var _cards_row: HBoxContainer = null
var _selected_label: Label = null
var _hint_label: Label = null
var _empty_label: Label = null
var _card_refs: Dictionary = {}


func _ready() -> void:
	_ensure_built()
	visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_gs = UI.game_state()
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)
	_build_ui()
	_connect_signals()


# ==================================================================
# 公共接口
# ==================================================================

func open_panel() -> void:
	if not _built:
		_ensure_built()
	visible = true
	refresh()
	_play_open_animation()


# ==================================================================
# 构建
# ==================================================================

func _build_ui() -> void:
	add_child(UI.dim_overlay(0.86))

	_panel = PanelContainer.new()
	_panel.name = "MetaPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -520.0
	_panel.offset_top = -310.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 310.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.09, 0.065, 0.16, 0.98),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.72), 24, 2))
	add_child(_panel)

	var root := UI.vbox(12)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(root)
	root.add_child(_build_header())
	root.add_child(_build_balls_section())
	root.add_child(_build_cards_section())
	root.add_child(_build_footer())


func _build_header() -> Control:
	var row := UI.hbox(14)
	var title := UI.title("行囊 · 局外", 42, FateConfig.COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(title)
	var sub := UI.vbox(0)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_child(UI.label("一局结束带出的弹珠与卡牌，勾选后带入下一局", 14,
			FateConfig.COLOR_TEXT_DIM))
	sub.add_child(UI.label("弹珠最多带入 3 颗 · 卡牌最多带入 2 张", 12,
			FateConfig.COLOR_VIOLET))
	row.add_child(sub)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	var close_btn := UI.button("✕", 26, 52.0)
	close_btn.custom_minimum_size = Vector2(52.0, 52.0)
	close_btn.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
	close_btn.pressed.connect(_on_close)
	row.add_child(close_btn)
	return row


func _build_balls_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.13, 0.095, 0.21, 0.9),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.85), 14, 1))
	var box := UI.vbox(4)
	panel.add_child(box)

	var head := UI.hbox(10)
	head.add_child(UI.label("弹珠", 19, FateConfig.COLOR_GOLD))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(fill)
	_ball_total_label = UI.label("", 13, FateConfig.COLOR_JADE)
	head.add_child(_ball_total_label)
	box.add_child(head)

	box.add_child(_make_ball_row(false))
	box.add_child(_make_ball_row(true))
	return panel


func _make_ball_row(advanced: bool) -> Control:
	var row := UI.hbox(10)
	row.add_child(UI.ball_icon(advanced, 34.0))

	var name_label: Label = null
	if advanced:
		name_label = UI.label("进阶弹珠", 16, FateConfig.COLOR_GOLD)
		_ball_advanced_label = UI.label("", 13, FateConfig.COLOR_TEXT_DIM)
	else:
		name_label = UI.label("普通弹珠", 16, FateConfig.COLOR_TEXT)
		_ball_normal_label = UI.label("", 13, FateConfig.COLOR_TEXT_DIM)
	name_label.custom_minimum_size = Vector2(78.0, 0.0)
	row.add_child(name_label)
	row.add_child(_ball_normal_label if not advanced else _ball_advanced_label)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	var minus := UI.button("－", 20, 42.0)
	minus.custom_minimum_size = Vector2(56.0, 42.0)
	minus.pressed.connect(_on_ball_plus.bind(advanced, -1))
	row.add_child(minus)

	var value := UI.label("0", 20, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	value.custom_minimum_size = Vector2(40.0, 0.0)
	row.add_child(value)

	var plus := UI.button("＋", 20, 42.0)
	plus.custom_minimum_size = Vector2(56.0, 42.0)
	plus.pressed.connect(_on_ball_plus.bind(advanced, 1))
	row.add_child(plus)

	if advanced:
		_advanced_minus = minus
		_advanced_plus = plus
		_ball_advanced_value = value
	else:
		_normal_minus = minus
		_normal_plus = plus
		_ball_normal_value = value
	return row


func _build_cards_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.13, 0.095, 0.21, 0.9),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.85), 14, 1))
	var box := UI.vbox(4)
	panel.add_child(box)

	var head := UI.hbox(10)
	head.add_child(UI.label("卡牌 / 装备", 19, FateConfig.COLOR_GOLD))
	head.add_child(UI.label("点击选择，金框为已勾选", 11, FateConfig.COLOR_TEXT_DIM))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(fill)
	_hint_label = UI.label("", 12, FateConfig.COLOR_VIOLET)
	head.add_child(_hint_label)
	box.add_child(head)

	var scroll := HBoxContainer.new()
	scroll.add_theme_constant_override("separation", 10)
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_row = scroll
	box.add_child(scroll)

	_empty_label = UI.label("行囊空空如也 · 完成一局后会有弹珠与卡牌带出", 13,
			FateConfig.COLOR_TEXT_DIM)
	_empty_label.visible = false
	box.add_child(_empty_label)
	return panel


func _build_footer() -> Control:
	var box := UI.vbox(4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_selected_label = UI.label("", 15, FateConfig.COLOR_JADE,
			HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_selected_label)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var confirm := UI.button("确认带入下一局", 28, 72.0)
	confirm.custom_minimum_size = Vector2(360.0, 72.0)
	confirm.pressed.connect(_on_close)
	center.add_child(confirm)
	box.add_child(center)
	return box


# ==================================================================
# 卡牌堆
# ==================================================================

func _make_card_stack(id: String, count: int) -> PanelContainer:
	var info: Dictionary = FateConfig.ITEMS.get(id, {})
	var item_name := String(info.get("name", id))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(104.0, 96.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.gui_input.connect(_on_card_gui_input.bind(id, card))
	_card_refs[id] = card

	var box := UI.vbox(1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(UI.item_icon(id, 40.0))
	box.add_child(icon_center)

	box.add_child(UI.label(item_name, 12, FateConfig.COLOR_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER))

	var count_label := UI.label("×%d" % count, 11,
			FateConfig.COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(count_label)
	return card


func _card_style(selected: bool) -> StyleBoxFlat:
	if selected:
		return UI.panel_style(
				Color(0.22, 0.16, 0.10, 0.96),
				FateConfig.COLOR_GOLD, 0, 3, false)
	return UI.panel_style(Color(0.16, 0.11, 0.26, 0.94),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.8), 12, 1, false)


func _on_card_gui_input(event: InputEvent, id: String, card: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _gs == null:
		return
	var ok := _gs.toggle_selected_card(id)
	if not ok:
		if _gs.is_card_selected(id):
			return
		_flash_hint("最多只能带入 %d 张卡牌" % FateConfig.META_MAX_SELECT_CARDS)
		return
	UI.play_sfx("click")
	refresh()


func _flash_hint(text: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.2).timeout
	if _hint_label != null and is_instance_valid(_hint_label):
		_hint_label.add_theme_color_override("font_color",
				FateConfig.COLOR_VIOLET)
		_hint_label.text = ""


# ==================================================================
# 刷新
# ==================================================================

func refresh() -> void:
	if not _built:
		_ensure_built()
		return
	if _gs == null:
		_gs = UI.game_state()
		if _gs == null:
			return
	var total_cards := _gs.meta_cards.size()
	_ball_normal_label.text = "拥有 %d" % _gs.meta_balls_normal
	_ball_advanced_label.text = "拥有 %d" % _gs.meta_balls_advanced
	_ball_normal_value.text = "已选 %d" % _gs.selected_balls_normal
	_ball_advanced_value.text = "已选 %d" % _gs.selected_balls_advanced
	_ball_total_label.text = "已选弹珠 %d / %d" % [
			_gs.get_selected_ball_total(), FateConfig.META_MAX_SELECT_BALLS]

	_normal_minus.disabled = _gs.selected_balls_normal <= 0
	_advanced_minus.disabled = _gs.selected_balls_advanced <= 0
	var total := _gs.get_selected_ball_total()
	_normal_plus.disabled = _gs.selected_balls_normal >= _gs.meta_balls_normal \
			or total >= FateConfig.META_MAX_SELECT_BALLS
	_advanced_plus.disabled = _gs.selected_balls_advanced >= _gs.meta_balls_advanced \
			or total >= FateConfig.META_MAX_SELECT_BALLS

	_rebuild_cards(total_cards)
	_selected_label.text = "带入下一局：%d 颗弹珠 · %d 张卡牌" % [
			_gs.get_selected_ball_total(), _gs.selected_cards.size()]
	_hint_label.text = "已选卡牌 %d / %d" % [_gs.selected_cards.size(),
			FateConfig.META_MAX_SELECT_CARDS]


func _rebuild_cards(total_cards: int) -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	_card_refs.clear()
	var stacks: Array = _gs.get_meta_card_stacks()
	_empty_label.visible = total_cards <= 0
	if total_cards <= 0:
		return
	for entry in stacks:
		var id := String(entry.get("id", ""))
		var count := int(entry.get("count", 0))
		var card := _make_card_stack(id, count)
		var selected_count := 0
		for sel in _gs.selected_cards:
			if String(sel) == id:
				selected_count += 1
		card.add_theme_stylebox_override("panel",
				_card_style(selected_count > 0))
		_cards_row.add_child(card)


func _on_ball_plus(advanced: bool, delta: int) -> void:
	if _gs == null:
		return
	_gs.select_meta_balls(advanced, delta)
	UI.play_sfx("click")
	refresh()


func _on_close() -> void:
	UI.play_sfx("click")
	visible = false
	closed.emit()


func _play_open_animation() -> void:
	if _panel == null or not is_inside_tree():
		return
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.96, 0.96)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _connect_signals() -> void:
	if _gs == null:
		push_warning("[MetaPanel] 未找到 GameState")
		return
	if not _gs.meta_changed.is_connected(_on_meta_changed):
		_gs.meta_changed.connect(_on_meta_changed)


func _on_meta_changed() -> void:
	refresh()

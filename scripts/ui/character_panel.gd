extends Control
## 《！？珠珠？！》v1.5 角色 / 行囊面板（替代走廊里的 meta_panel）。
##
## 左半：主角像素立绘 + 名字 + Lv / 经验条；
## 右半：顶部目录（FateConfig.PANEL_TABS：角色信息 / 弹珠 / 卡牌），
##      下方内容随 tab 切换；底部「确认 / 关闭」。
## 接口：signal closed / func open_panel() -> void

signal closed

const UI := preload("res://scripts/ui/ui_theme.gd")
const DetailPopup := preload("res://scripts/ui/detail_popup.gd")

const TAB_INFO := 0
const TAB_BALLS := 1
const TAB_CARDS := 2

var _gs := UI.game_state()
var _built := false
var _active_tab: int = TAB_INFO

var _panel: PanelContainer = null
var _portrait: TextureRect = null
var _name_label: Label = null
var _lv_label: Label = null
var _exp_label: Label = null
var _exp_bar: ProgressBar = null
var _tab_buttons: Array[Button] = []
var _content_root: VBoxContainer = null
var _hint_label: Label = null
var _detail_popup: Control = null


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

func open_panel(tab_index: int = -1) -> void:
	if not _built:
		_ensure_built()
	if tab_index >= 0:
		_active_tab = clampi(tab_index, 0, FateConfig.PANEL_TABS.size() - 1)
	else:
		_active_tab = TAB_INFO
	visible = true
	refresh()
	_play_open_animation()


## 兼容入口：打开并定位到指定页（0 角色信息 / 1 弹珠 / 2 卡牌）。
func open_to_tab(tab_index: int) -> void:
	open_panel(tab_index)


# ==================================================================
# 构建
# ==================================================================

func _build_ui() -> void:
	add_child(UI.dim_overlay(0.84))

	_panel = PanelContainer.new()
	_panel.name = "CharacterPanel"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 36.0
	_panel.offset_top = 22.0
	_panel.offset_right = -36.0
	_panel.offset_bottom = -22.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.075, 0.055, 0.12, 0.98),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.75), 0, 3))
	add_child(_panel)

	var row := UI.hbox(16)
	_panel.add_child(row)
	row.add_child(_build_left_column())
	row.add_child(_build_right_column())


func _build_left_column() -> Control:
	var left := UI.vbox(6)
	left.custom_minimum_size = Vector2(440.0, 0.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 45.0

	# 立绘框
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.05, 0.04, 0.09, 0.95),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.9), 0, 2))
	left.add_child(frame)

	_portrait = TextureRect.new()
	_portrait.texture = UI.load_texture("res://assets/art/player_portrait.png")
	if _portrait.texture == null:
		_portrait.texture = UI.load_texture("res://assets/art/ref_astrologer.png")
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.custom_minimum_size = Vector2(320.0, 400.0)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_portrait)

	_name_label = UI.label("持星辉法球的流浪占星师", 20, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_name_label)

	var lv_row := UI.hbox(10)
	lv_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_lv_label = UI.label("Lv.1", 22, FateConfig.COLOR_JADE)
	lv_row.add_child(_lv_label)
	_exp_label = UI.label("经验 0 / 100", 14, FateConfig.COLOR_TEXT_DIM)
	lv_row.add_child(_exp_label)
	left.add_child(lv_row)

	_exp_bar = ProgressBar.new()
	_exp_bar.custom_minimum_size = Vector2(0.0, 16.0)
	_exp_bar.show_percentage = false
	_exp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_exp_bar)

	var tip := UI.label("经验来源：每通过一间命运房间 +40", 11,
			FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(tip)

	var exit_to_menu := UI.label("", 10, FateConfig.COLOR_VOID,
			HORIZONTAL_ALIGNMENT_CENTER)
	exit_to_menu.visible = false
	left.add_child(exit_to_menu)
	return left


func _build_right_column() -> Control:
	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 55.0

	# 顶部目录 tabs
	var tabs := UI.hbox(8)
	for i in FateConfig.PANEL_TABS.size():
		var btn := UI.button(FateConfig.PANEL_TABS[i], 18, 44.0)
		btn.custom_minimum_size = Vector2(132.0, 44.0)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		tabs.add_child(btn)
		_tab_buttons.append(btn)
	right.add_child(tabs)

	# 内容区
	var content := PanelContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.055, 0.04, 0.095, 0.96),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.85), 0, 2))
	right.add_child(content)
	_content_root = UI.vbox(8)
	content.add_child(_content_root)

	# 底部确认
	var footer := UI.hbox(12)
	_hint_label = UI.label("", 11, FateConfig.COLOR_TEXT_DIM)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_hint_label)
	var confirm := UI.button("确认 / 关闭", 20, 58.0)
	confirm.custom_minimum_size = Vector2(200.0, 58.0)
	confirm.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	confirm.pressed.connect(_on_close_pressed)
	footer.add_child(confirm)
	right.add_child(footer)
	return right


# ==================================================================
# Tabs / 内容
# ==================================================================

func _on_tab_pressed(index: int) -> void:
	if index == _active_tab:
		return
	UI.play_sfx("click")
	_active_tab = clampi(index, 0, FateConfig.PANEL_TABS.size() - 1)
	refresh()


func _active_tab_style(active: bool) -> StyleBoxFlat:
	if active:
		var style := UI.panel_style(Color(0.91, 0.76, 0.42, 0.96),
				FateConfig.COLOR_GOLD, 0, 2)
		return style
	return UI.panel_style(Color(0.10, 0.075, 0.17, 0.96),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.9), 0, 2)


func _refresh_tabs() -> void:
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i]
		var active := i == _active_tab
		btn.add_theme_stylebox_override("normal", _active_tab_style(active))
		btn.add_theme_stylebox_override("hover", _active_tab_style(active))
		btn.add_theme_stylebox_override("pressed", _active_tab_style(active))
		btn.add_theme_color_override("font_color",
				FateConfig.COLOR_VOID if active else FateConfig.COLOR_TEXT_DIM)
		btn.add_theme_color_override("font_hover_color",
				FateConfig.COLOR_VOID if active else FateConfig.COLOR_GOLD)


func _clear_content() -> void:
	for child in _content_root.get_children():
		_content_root.remove_child(child)
		child.queue_free()


func _rebuild_content() -> void:
	_clear_content()
	match _active_tab:
		TAB_INFO:
			_build_info_tab()
		TAB_BALLS:
			_build_balls_tab()
		TAB_CARDS:
			_build_cards_tab()


func _build_info_tab() -> void:
	_content_root.add_child(UI.label("角色信息", 22, FateConfig.COLOR_GOLD))
	_content_root.add_child(_make_divider())

	if _gs == null:
		return
	var level := int(_gs.character_level)
	var exp := int(_gs.character_exp)
	var needed := int(_gs.exp_needed())
	_content_root.add_child(_stat_row("等级", "Lv.%d" % level, FateConfig.COLOR_GOLD))
	var exp_row := UI.hbox(10)
	exp_row.add_child(UI.label("经验", 15, FateConfig.COLOR_TEXT_DIM))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240.0, 14.0)
	bar.show_percentage = false
	bar.max_value = maxi(needed, 1)
	bar.value = clampi(exp, 0, maxi(needed, 1))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exp_row.add_child(bar)
	exp_row.add_child(UI.label("%d / %d" % [exp, needed], 14,
			FateConfig.COLOR_TEXT))
	_content_root.add_child(exp_row)

	var progress_text := "尚未开始"
	if _gs.has_resumable_run():
		progress_text = "%s · %s" % [_gs.level_display(), _gs.get_level_name()]
	_content_root.add_child(_stat_row("本局进度", progress_text,
			FateConfig.COLOR_VIOLET))
	_content_root.add_child(_stat_row("命运碎片", str(int(_gs.total_shards)),
			FateConfig.COLOR_VIOLET))
	_content_root.add_child(_stat_row("历史最高分", str(int(_gs.best_score)),
			FateConfig.COLOR_GOLD))
	_content_root.add_child(_stat_row("已通关局数", str(int(_gs.runs_played)),
			FateConfig.COLOR_TEXT))
	_content_root.add_child(UI.spacer(1.0))
	_content_root.add_child(UI.label("等级目前暂无额外效果，仅记录旅人的命运刻痕。",
			11, FateConfig.COLOR_TEXT_DIM))


func _build_balls_tab() -> void:
	_content_root.add_child(UI.label("三种琉璃珠", 22, FateConfig.COLOR_GOLD))
	_content_root.add_child(UI.label("勾选后带入下一局（弹珠合计最多 3 颗）",
			11, FateConfig.COLOR_TEXT_DIM))
	_content_root.add_child(_make_divider())
	if _gs == null:
		return
	var total := int(_gs.get_selected_ball_total())
	_content_root.add_child(_make_ball_manage_row(FateConfig.BALL_TYPE_FATE,
			"命运琉璃珠", int(_gs.meta_balls_normal),
			int(_gs.selected_balls_normal)))
	_content_root.add_child(_make_ball_manage_row(FateConfig.BALL_TYPE_CORE,
			"命核琉璃珠", int(_gs.meta_balls_advanced),
			int(_gs.selected_balls_advanced)))
	_content_root.add_child(_make_ball_manage_row(FateConfig.BALL_TYPE_SOURCE,
			"命源琉璃珠", int(_gs.meta_balls_high),
			int(_gs.selected_balls_high)))
	_content_root.add_child(_make_divider())
	_content_root.add_child(UI.label("已选弹珠：%d / %d" % [
			total, FateConfig.META_MAX_SELECT_BALLS], 14, FateConfig.COLOR_JADE))


func _make_ball_manage_row(ball_type: int, ball_name: String, owned: int,
		selected: int) -> Control:
	var manage_row := UI.hbox(10)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(38.0, 38.0)
	icon_box.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_box.gui_input.connect(_on_ball_icon_input.bind(ball_type))
	var ball_icon := UI.ball_icon_type(ball_type, 36.0)
	ball_icon.position = Vector2(1.0, 1.0)
	icon_box.add_child(ball_icon)
	manage_row.add_child(icon_box)
	var name_label := UI.label(ball_name, 16,
			FateConfig.COLOR_GOLD if ball_type > 0 else FateConfig.COLOR_TEXT)
	name_label.custom_minimum_size = Vector2(96.0, 0.0)
	manage_row.add_child(name_label)
	manage_row.add_child(UI.label("拥有 %d" % owned, 13,
			FateConfig.COLOR_TEXT_DIM))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manage_row.add_child(fill)

	var minus := UI.button("－", 18, 40.0)
	minus.custom_minimum_size = Vector2(50.0, 40.0)
	minus.disabled = selected <= 0
	minus.pressed.connect(_on_ball_adjust.bind(ball_type, -1))
	manage_row.add_child(minus)

	var sel_label := UI.label("已选 %d" % selected, 14, FateConfig.COLOR_JADE,
			HORIZONTAL_ALIGNMENT_CENTER)
	sel_label.custom_minimum_size = Vector2(64.0, 0.0)
	manage_row.add_child(sel_label)

	var plus := UI.button("＋", 18, 40.0)
	plus.custom_minimum_size = Vector2(50.0, 40.0)
	plus.disabled = owned <= selected \
			or int(_gs.get_selected_ball_total()) >= FateConfig.META_MAX_SELECT_BALLS
	plus.pressed.connect(_on_ball_adjust.bind(ball_type, 1))
	manage_row.add_child(plus)
	return manage_row


func _build_cards_tab() -> void:
	_content_root.add_child(UI.label("卡牌 / 装备", 22, FateConfig.COLOR_GOLD))
	_content_root.add_child(UI.label("点击卡牌勾选带入下一局（最多 2 张）", 11,
			FateConfig.COLOR_TEXT_DIM))
	_content_root.add_child(_make_divider())
	if _gs == null:
		return
	var stacks: Array = _gs.get_meta_card_stacks()
	if stacks.is_empty():
		_content_root.add_child(UI.label("行囊里还没有卡牌 · 完成关卡后会带出部分道具",
				13, FateConfig.COLOR_TEXT_DIM))
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_root.add_child(flow)
	for entry in stacks:
		var id := String(entry.get("id", ""))
		var count := int(entry.get("count", 0))
		flow.add_child(_make_card_stack(id, count))
	_content_root.add_child(UI.spacer(1.0))
	_content_root.add_child(UI.label("已选卡牌：%d / %d" % [
			_gs.selected_cards.size(), FateConfig.META_MAX_SELECT_CARDS], 14,
			FateConfig.COLOR_JADE))


func _make_card_stack(id: String, count: int) -> Control:
	var info: Dictionary = FateConfig.ITEMS.get(id, {})
	var item_name := String(info.get("name", id))
	var selected_count := 0
	for sel in _gs.selected_cards:
		if String(sel) == id:
			selected_count += 1
	var selected := selected_count > 0
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(112.0, 100.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(selected))
	card.gui_input.connect(_on_card_gui_input.bind(id))
	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(40.0, 40.0)
	icon_box.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_box.gui_input.connect(_on_card_icon_input.bind(id))
	var item_icon := UI.item_icon(id, 38.0)
	item_icon.position = Vector2(1.0, 1.0)
	icon_box.add_child(item_icon)
	icon_center.add_child(icon_box)
	box.add_child(icon_center)
	box.add_child(UI.label(item_name, 11, FateConfig.COLOR_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UI.label("×%d" % count, 11, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _card_style(selected: bool) -> StyleBoxFlat:
	if selected:
		return UI.panel_style(Color(0.22, 0.16, 0.10, 0.96),
				FateConfig.COLOR_GOLD, 0, 3, false)
	return UI.panel_style(Color(0.13, 0.095, 0.21, 0.95),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.85), 0, 2, false)


func _make_divider() -> Control:
	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.28)
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _stat_row(heading: String, value: String, color: Color) -> Control:
	var row := UI.hbox(10)
	var heading_label := UI.label(heading, 15, FateConfig.COLOR_TEXT_DIM)
	heading_label.custom_minimum_size = Vector2(120.0, 0.0)
	row.add_child(heading_label)
	row.add_child(UI.label(value, 17, color))
	return row


# ==================================================================
# 交互
# ==================================================================

func _on_ball_adjust(ball_type: int, delta: int) -> void:
	if _gs == null:
		return
	_gs.select_meta_ball_type(ball_type, delta)
	UI.play_sfx("click")
	refresh()


func _show_item_detail(item_id: String) -> void:
	if not FateConfig.ITEMS.has(item_id):
		return
	if _detail_popup == null or not is_instance_valid(_detail_popup):
		_detail_popup = DetailPopup.new()
		add_child(_detail_popup)
	_detail_popup.call("open_item", item_id)


func _show_ball_detail(ball_type: int) -> void:
	if _detail_popup == null or not is_instance_valid(_detail_popup):
		_detail_popup = DetailPopup.new()
		add_child(_detail_popup)
	_detail_popup.call("open_ball", ball_type)


func _on_ball_icon_input(event: InputEvent, ball_type: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_show_ball_detail(ball_type)


func _on_card_icon_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_show_item_detail(item_id)


func _on_card_gui_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _gs == null:
		return
	if _gs.selected_cards.size() >= FateConfig.META_MAX_SELECT_CARDS \
			and not _gs.is_card_selected(id):
		UI.play_sfx("click")
		return
	_gs.toggle_selected_card(id)
	UI.play_sfx("click")
	refresh()


func _on_close_pressed() -> void:
	UI.play_sfx("click")
	visible = false
	closed.emit()


# ==================================================================
# 刷新 / 数据
# ==================================================================

func refresh() -> void:
	if not _built:
		_ensure_built()
		return
	if _gs == null:
		_gs = UI.game_state()
		if _gs == null:
			return
	var level := int(_gs.character_level)
	var exp := int(_gs.character_exp)
	var needed := maxi(int(_gs.exp_needed()), 1)
	_lv_label.text = "Lv.%d" % level
	_exp_label.text = "经验 %d / %d" % [exp, needed]
	_exp_bar.max_value = needed
	_exp_bar.value = clampi(exp, 0, needed)
	_exp_bar.tooltip_text = ""
	_refresh_tabs()
	_rebuild_content()
	_hint_label.text = "提升等级可记录旅人的命运刻痕（暂无额外效果）"


func _meta_high_count() -> int:
	if _gs == null:
		return 0
	for prop in _gs.get_property_list():
		if String(prop.get("name", "")) == "meta_balls_high":
			return int(_gs.get("meta_balls_high"))
	return 0


func _play_open_animation() -> void:
	if _panel == null or not is_inside_tree():
		return
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _connect_signals() -> void:
	if _gs == null:
		push_warning("[CharacterPanel] 未找到 GameState")
		return
	if not _gs.meta_changed.is_connected(_on_state_changed):
		_gs.meta_changed.connect(_on_state_changed)
	if not _gs.character_changed.is_connected(_on_character_changed):
		_gs.character_changed.connect(_on_character_changed)


func _on_state_changed() -> void:
	refresh()


func _on_character_changed(_level: int, _exp: int, _needed: int) -> void:
	refresh()

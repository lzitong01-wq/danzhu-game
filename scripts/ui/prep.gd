extends Control
## 《？！珠珠！？》v1.2 准备阶段（PREP）界面。
##
## 上半屏 = 命运商店（3 件货品、金币、关卡法则、命运事件、目标）；
## 下半屏 = 查看牌组（待用卡牌/装备、弹珠库、本关弹珠槽与已绑卡牌）。
## 接口见 docs/CONTRACT_V4.md 第 4 节：
##   signal start_pressed(double_mode: bool)
##   func open_prep(level: int, offers: Array[String]) -> void

signal start_pressed(double_mode: bool)

const UI := preload("res://scripts/ui/ui_theme.gd")

var _gs := UI.game_state()
var _built := false
var _level: int = 1
var _offers: Array[String] = []
var _bought_ids: Dictionary = {}
var _offer_cards: Dictionary = {}

var _panel: PanelContainer = null
var _level_label: Label = null
var _target_label: Label = null
var _coins_label: Label = null
var _buff_label: Label = null
var _event_label: Label = null
var _cards_row: HBoxContainer = null
var _pending_row: HBoxContainer = null
var _library_label: Label = null
var _slots_row: HBoxContainer = null
var _status_label: Label = null
var _status_tween: Tween = null
var _double_dialog: Control = null
var _dialog_panel: PanelContainer = null


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

func open_prep(level: int, offers: Array[String]) -> void:
	if not _built:
		_ensure_built()
	_level = clampi(level, 1, FateConfig.MAX_LEVEL)
	_offers.clear()
	for id in offers:
		if FateConfig.ITEMS.has(id):
			_offers.append(id)
	_bought_ids.clear()
	if _double_dialog != null:
		_double_dialog.visible = false
	visible = true
	refresh()
	_play_open_animation()


# ==================================================================
# 构建
# ==================================================================

func _build_ui() -> void:
	add_child(UI.dim_overlay(0.84))

	var glow := TextureRect.new()
	glow.texture = UI.load_texture("res://assets/art/particle_dot.png")
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.position = Vector2(300.0, -80.0)
	glow.size = Vector2(680.0, 400.0)
	glow.modulate = Color(FateConfig.COLOR_VIOLET.r, FateConfig.COLOR_VIOLET.g,
			FateConfig.COLOR_VIOLET.b, 0.10)
	add_child(glow)

	_panel = PanelContainer.new()
	_panel.name = "PrepPanel"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 28.0
	_panel.offset_top = 16.0
	_panel.offset_right = -28.0
	_panel.offset_bottom = -16.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.09, 0.065, 0.16, 0.97),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.70), 24, 2))
	add_child(_panel)

	var root := UI.vbox(10)
	_panel.add_child(root)
	root.add_child(_build_header())

	var info_row := UI.hbox(14)
	info_row.add_child(_build_info_panel("关卡法则", true))
	info_row.add_child(_build_info_panel("命运事件", false))
	root.add_child(info_row)

	_cards_row = UI.hbox(14)
	_cards_row.custom_minimum_size = Vector2(0.0, 220.0)
	root.add_child(_cards_row)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.30)
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(divider)

	root.add_child(_build_deck_section())
	root.add_child(_build_footer())
	_build_double_dialog()


func _build_header() -> Control:
	var row := UI.hbox(14)
	var title := UI.title("准备阶段 · 命运商店", 32, FateConfig.COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(title)
	_level_label = UI.label("第 1 间 · 裂纹初现", 18, FateConfig.COLOR_TEXT_DIM)
	row.add_child(_level_label)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)

	_target_label = UI.label("目标 25 分", 24, FateConfig.COLOR_JADE)
	row.add_child(_target_label)

	var coin_chip := UI.hbox(8)
	coin_chip.add_child(UI.icon("coin", 32.0))
	_coins_label = UI.label("9", 28, FateConfig.COLOR_GOLD)
	_coins_label.custom_minimum_size = Vector2(34.0, 0.0)
	coin_chip.add_child(_coins_label)
	coin_chip.add_child(UI.label("金币", 15, FateConfig.COLOR_TEXT_DIM))
	row.add_child(coin_chip)

	var close_btn := UI.button("✕", 26, 52.0)
	close_btn.custom_minimum_size = Vector2(52.0, 52.0)
	close_btn.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
	close_btn.pressed.connect(_on_start_requested)
	row.add_child(close_btn)
	return row


func _build_info_panel(heading: String, is_buff: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0.0, 58.0)
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.14, 0.10, 0.23, 0.85),
			Color(FateConfig.COLOR_VIOLET_DIM.r, FateConfig.COLOR_VIOLET_DIM.g,
			FateConfig.COLOR_VIOLET_DIM.b, 0.85), 12, 1))
	var box := UI.vbox(1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(UI.label(heading, 13,
			FateConfig.COLOR_GOLD_DIM if is_buff else FateConfig.COLOR_VIOLET))
	if is_buff:
		_buff_label = UI.label("—", 16, FateConfig.COLOR_TEXT)
		box.add_child(_buff_label)
	else:
		_event_label = UI.label("—", 16, FateConfig.COLOR_TEXT)
		box.add_child(_event_label)
	panel.add_child(box)
	return panel


func _build_deck_section() -> VBoxContainer:
	var section := UI.vbox(6)

	var head := UI.hbox(10)
	head.add_child(UI.label("查看牌组", 20, FateConfig.COLOR_GOLD))
	head.add_child(UI.label("本关携带的卡牌 / 装备与本关弹珠概览", 11,
			FateConfig.COLOR_TEXT_DIM))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(fill)
	_library_label = UI.label("弹珠库 普通 ×0 · 进阶 ×0", 13,
			FateConfig.COLOR_TEXT_DIM)
	head.add_child(_library_label)
	section.add_child(head)

	var pending_row := UI.hbox(8)
	pending_row.custom_minimum_size = Vector2(0.0, 54.0)
	pending_row.add_child(UI.label("待用卡牌 / 装备", 13,
			FateConfig.COLOR_TEXT_DIM))
	_pending_row = UI.hbox(8)
	_pending_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	pending_row.add_child(_pending_row)
	var pending_fill := Control.new()
	pending_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pending_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pending_row.add_child(pending_fill)
	section.add_child(pending_row)

	var slot_line := UI.hbox(8)
	slot_line.custom_minimum_size = Vector2(0.0, 58.0)
	slot_line.add_child(UI.label("本关弹珠", 13, FateConfig.COLOR_TEXT_DIM))
	_slots_row = UI.hbox(10)
	_slots_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_slots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_line.add_child(_slots_row)
	section.add_child(slot_line)

	return section


func _build_footer() -> Control:
	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	_status_label = UI.label("", 14, FateConfig.COLOR_CRIMSON,
			HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.visible = false
	box.add_child(_status_label)
	box.add_child(UI.label("购买 / 整理完毕后点击「开始试炼」，进入发射阶段",
			13, FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start_btn := UI.button("开始试炼", 30, 72.0)
	start_btn.custom_minimum_size = Vector2(360.0, 72.0)
	start_btn.pressed.connect(_on_start_requested)
	center.add_child(start_btn)
	box.add_child(center)
	return box


## 点击开始/❌ 后先弹「命运双倍注？」对话框。
func _build_double_dialog() -> void:
	_double_dialog = Control.new()
	_double_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(_double_dialog)
	_double_dialog.visible = false
	add_child(_double_dialog)
	_double_dialog.add_child(UI.dim_overlay(0.74))

	_dialog_panel = PanelContainer.new()
	_dialog_panel.anchor_left = 0.5
	_dialog_panel.anchor_top = 0.5
	_dialog_panel.anchor_right = 0.5
	_dialog_panel.anchor_bottom = 0.5
	_dialog_panel.offset_left = -370.0
	_dialog_panel.offset_top = -232.0
	_dialog_panel.offset_right = 370.0
	_dialog_panel.offset_bottom = 232.0
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialog_panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.08, 0.06, 0.14, 0.99), FateConfig.COLOR_GOLD, 0, 4))
	_double_dialog.add_child(_dialog_panel)

	var box := UI.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_dialog_panel.add_child(box)
	box.add_child(UI.title("命运双倍注？", 38, FateConfig.COLOR_GOLD))
	box.add_child(UI.label("要在这场试炼里押上双倍注吗？", 16,
			FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var lines := UI.vbox(6)
	for text in ["得分 ×2 · 金币 ×2", "黑色立柱扣分 ×2", "失败时命运碎片减半",
			"风险与回报，皆随此注翻倍"]:
		var color := FateConfig.COLOR_CRIMSON if text.contains("失败") \
				else FateConfig.COLOR_TEXT
		lines.add_child(UI.label(text, 17, color, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(lines)

	var buttons := UI.hbox(24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var double_btn := UI.button("双倍押注", 24, 64.0)
	double_btn.custom_minimum_size = Vector2(220.0, 64.0)
	double_btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	double_btn.pressed.connect(_on_double_choice.bind(true))
	buttons.add_child(double_btn)
	var safe_btn := UI.button("稳妥开局", 24, 64.0)
	safe_btn.custom_minimum_size = Vector2(220.0, 64.0)
	safe_btn.pressed.connect(_on_double_choice.bind(false))
	buttons.add_child(safe_btn)
	box.add_child(buttons)


# ==================================================================
# 数据刷新
# ==================================================================

func refresh() -> void:
	if not _built:
		_ensure_built()
		return
	if _gs == null:
		_gs = UI.game_state()
		if _gs == null:
			return
	_level_label.text = "第 %d 间 · %s" % [_level,
			FateConfig.LEVEL_NAMES[_level - 1]]
	if _gs.level == _level:
		_target_label.text = "目标 %d 分" % _gs.get_target()
	else:
		_target_label.text = "目标 %d 分" % FateConfig.LEVEL_TARGETS[_level - 1]
	_coins_label.text = str(_gs.coins)
	_buff_label.text = FateConfig.LEVEL_BUFFS[_level - 1]
	var event: Dictionary = _gs.fate_event
	if event.is_empty():
		_event_label.text = "本关没有命运事件"
	else:
		_event_label.text = "%s：%s" % [String(event.get("name", "")),
				String(event.get("desc", ""))]
	_rebuild_cards()
	_update_deck()


func _rebuild_cards() -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	_offer_cards.clear()
	for id in _offers:
		_cards_row.add_child(_make_offer_card(id))


func _make_offer_card(id: String) -> PanelContainer:
	var info: Dictionary = FateConfig.ITEMS.get(id, {})
	var item_name := String(info.get("name", id))
	var desc := String(info.get("desc", ""))
	var cost := int(info.get("cost", 0))
	var tag := String(info.get("tag", ""))
	var kind := String(info.get("kind", "equipment"))
	var owned_passive := kind == "passive" and _gs != null and _gs.has_item(id)
	var can_buy := _gs != null and _gs.can_buy_item(id)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.16, 0.11, 0.26, 0.95),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.8), 16, 1))
	_offer_cards[id] = card

	var box := UI.vbox(3)
	card.add_child(box)

	var top := UI.hbox(8)
	top.add_child(UI.item_icon(id, 44.0))
	var name_label := UI.label(item_name, 20, FateConfig.COLOR_GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	box.add_child(top)

	box.add_child(UI.label("%s · %s" % [tag, _kind_label(kind)], 11,
			FateConfig.COLOR_VIOLET))

	var desc_label := UI.label(desc, 12, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(0.0, 34.0)
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc_label)

	var price_row := UI.hbox(5)
	price_row.add_child(UI.icon("coin", 16.0))
	price_row.add_child(UI.label(str(cost), 16, FateConfig.COLOR_GOLD))
	price_row.add_child(UI.label("金币", 11, FateConfig.COLOR_TEXT_DIM))
	box.add_child(price_row)

	var buy_btn := UI.button("购买", 18, 52.0)
	if _bought_ids.has(id):
		buy_btn.text = "已购 ✓"
	if owned_passive:
		buy_btn.text = "已获得"
		buy_btn.disabled = true
	elif not can_buy:
		buy_btn.modulate = Color(0.62, 0.62, 0.68)
	buy_btn.pressed.connect(_on_buy.bind(id))
	box.add_child(buy_btn)
	return card


func _kind_label(kind: String) -> String:
	match kind:
		"equipment":
			return "拖到立柱"
		"card":
			return "拖到弹珠"
		"passive":
			return "立即生效"
		"library":
			return "进弹珠库"
		_:
			return kind


func _update_deck() -> void:
	for child in _pending_row.get_children():
		_pending_row.remove_child(child)
		child.queue_free()
	var pending: Array[String] = []
	if _gs != null:
		pending = _gs.get_pending_items()
	if pending.is_empty():
		var empty := UI.label("（空）商店购买的卡牌 / 装备会出现在这里", 12,
				FateConfig.COLOR_TEXT_DIM)
		empty.set_meta("pending_icon", true)
		_pending_row.add_child(empty)
	else:
		var counts: Dictionary = {}
		var order: Array[String] = []
		for id in pending:
			if not counts.has(id):
				counts[id] = 0
				order.append(id)
			counts[id] = int(counts[id]) + 1
		for id in order:
			_pending_row.add_child(_make_pending_chip(id, int(counts[id])))

	if _gs != null:
		_library_label.text = "弹珠库 普通 ×%d · 进阶 ×%d" % [
				_gs.library_normal, _gs.library_advanced]
		_update_slots()


func _make_pending_chip(id: String, count: int) -> Control:
	var chip := UI.hbox(4)
	chip.set_meta("pending_icon", true)
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(44.0, 44.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.20, 0.14, 0.31, 0.95), FateConfig.COLOR_GOLD_DIM, 10, 1, false))
	chip.add_child(holder)
	var tex := UI.item_icon(id, 34.0)
	tex.position = Vector2(5.0, 5.0)
	holder.add_child(tex)
	var info: Dictionary = FateConfig.ITEMS.get(id, {})
	var display_name := String(info.get("name", id))
	var label := UI.label("%s×%d" % [display_name, count], 12,
			FateConfig.COLOR_TEXT)
	chip.add_child(label)
	return chip


func _update_slots() -> void:
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	if _gs == null:
		return
	for i in range(_gs.balls_total):
		var slot: Dictionary = _gs.get_ball_slot(i)
		var advanced := int(slot.get("type", 0)) == 1
		var card := String(slot.get("card", ""))
		var chip := UI.vbox(0)
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		var icon_center := CenterContainer.new()
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(UI.ball_icon(advanced, 34.0))
		chip.add_child(icon_center)
		var card_label := UI.label("", 9,
				FateConfig.COLOR_CRIMSON, HORIZONTAL_ALIGNMENT_CENTER)
		card_label.custom_minimum_size = Vector2(44.0, 12.0)
		card_label.clip_text = true
		if card != "":
			card_label.text = _short_card_name(card)
		chip.add_child(card_label)
		_slots_row.add_child(chip)


func _short_card_name(card_id: String) -> String:
	var full := ""
	if _gs != null:
		full = _gs.get_card_name(card_id)
	if full == "":
		full = card_id
	return full.trim_suffix("卡")


# ==================================================================
# 交互 / 动画
# ==================================================================

func _on_buy(id: String) -> void:
	if _gs == null:
		return
	if not _gs.can_buy_item(id):
		var info: Dictionary = FateConfig.ITEMS.get(id, {})
		if String(info.get("kind", "")) == "passive" and _gs.has_item(id):
			_flash("这件遗物已经生效了")
		else:
			_flash("金币不足")
		return
	if _gs.buy_item(id):
		UI.play_sfx("buy")
		_bought_ids[id] = true
		refresh()
	else:
		_flash("无法购买")


func _on_start_requested() -> void:
	UI.play_sfx("click")
	if _double_dialog == null:
		visible = false
		start_pressed.emit(false)
		return
	_double_dialog.visible = true
	_dialog_panel.modulate.a = 0.0
	_dialog_panel.pivot_offset = _dialog_panel.size * 0.5
	_dialog_panel.scale = Vector2(0.96, 0.96)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dialog_panel, "modulate:a", 1.0, 0.12)
	tween.tween_property(_dialog_panel, "scale", Vector2.ONE, 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_double_choice(double_mode: bool) -> void:
	UI.play_sfx("click")
	if _double_dialog != null:
		_double_dialog.visible = false
	visible = false
	start_pressed.emit(double_mode)


func _flash(text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = true
	_status_label.modulate.a = 1.0
	if not is_inside_tree():
		return
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(1.0)
	_status_tween.tween_property(_status_label, "modulate:a", 0.0, 0.4)
	_status_tween.tween_callback(func() -> void:
		_status_label.visible = false
	)


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
		push_warning("[Prep] 未找到 GameState")
		return
	if not _gs.coins_changed.is_connected(_on_state_changed):
		_gs.coins_changed.connect(_on_state_changed)
	if not _gs.items_changed.is_connected(_on_items_changed):
		_gs.items_changed.connect(_on_items_changed)
	if not _gs.library_changed.is_connected(_on_library_changed):
		_gs.library_changed.connect(_on_library_changed)
	if not _gs.balls_changed.is_connected(_on_balls_changed):
		_gs.balls_changed.connect(_on_balls_changed)


func _on_state_changed(_value: int) -> void:
	refresh()


func _on_items_changed() -> void:
	refresh()


func _on_library_changed(_normal_count: int, _advanced_count: int) -> void:
	refresh()


func _on_balls_changed(_balls_left: int, _balls_total: int) -> void:
	refresh()

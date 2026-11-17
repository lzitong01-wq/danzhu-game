extends Control
## 《？！珠珠！？》v1.2 准备阶段（PREP）界面。
##
## 上半屏 = 命运商店（3 件货品、金币、关卡法则、命运事件、目标）；
## 下半屏 = 商店 P2 三行（携带道具 / 新购道具 / 携带弹珠，均可点击进入个人信息配置）。
## 接口见 docs/CONTRACT_V4.md 第 4 节：
##   signal start_pressed(double_mode: bool)
##   func open_prep(level: int, offers: Array[String]) -> void

signal start_pressed(double_mode: bool)

const UI := preload("res://scripts/ui/ui_theme.gd")
const DetailPopup := preload("res://scripts/ui/detail_popup.gd")

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
var _new_row: HBoxContainer = null
var _slots_row: HBoxContainer = null
var _char_panel: Control = null
var _status_label: Label = null
var _status_tween: Tween = null
var _double_dialog: Control = null
var _dialog_panel: PanelContainer = null
var _refresh_btn: Button = null
var _refresh_hint: Label = null
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

func open_prep(level: int, offers: Array[String]) -> void:
	if not _built:
		_ensure_built()
	_level = clampi(level, 1, FateConfig.MAX_LEVEL)
	_offers.clear()
	for id in offers:
		if FateConfig.ITEMS.has(id):
			_offers.append(id)
	# 契约：商店货品使用 GameState.roll_shop_offers()（守命低语权重已在 GameState 生效）
	if _offers.is_empty() and _gs != null:
		for id in _gs.roll_shop_offers():
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

	# 刷新货架（消耗命核碎片，费用随刷新次数 +1）
	var refresh_row := UI.hbox(10)
	var refresh_tip := UI.label("每关可刷新货架，费用随刷新次数递增", 11,
			FateConfig.COLOR_TEXT_DIM)
	refresh_row.add_child(refresh_tip)
	var refresh_fill := Control.new()
	refresh_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_row.add_child(refresh_fill)
	_refresh_hint = UI.label("", 11, FateConfig.COLOR_TEXT_DIM)
	refresh_row.add_child(_refresh_hint)
	_refresh_btn = UI.button("刷新货架（1 命核碎片）", 13, 40.0)
	_refresh_btn.custom_minimum_size = Vector2(230.0, 40.0)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	refresh_row.add_child(_refresh_btn)
	root.add_child(refresh_row)

	_cards_row = UI.hbox(14)
	_cards_row.custom_minimum_size = Vector2(0.0, 204.0)
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
	coin_chip.add_child(UI.label("命核碎片", 15, FateConfig.COLOR_TEXT_DIM))
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
		_buff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_buff_label.custom_minimum_size = Vector2(0.0, 24.0)
		box.add_child(_buff_label)
	else:
		_event_label = UI.label("—", 16, FateConfig.COLOR_TEXT)
		box.add_child(_event_label)
	panel.add_child(box)
	return panel


func _build_deck_section() -> VBoxContainer:
	# v1.7 商店 P2：三行 —— 携带道具（可点击改配置）/ 新购道具 / 携带弹珠（可点击改配置）
	var section := UI.vbox(4)

	var carried_row := UI.hbox(8)
	carried_row.custom_minimum_size = Vector2(0.0, 54.0)
	carried_row.add_child(_make_section_button("携带道具",
			_on_open_items_pressed))
	_pending_row = UI.hbox(8)
	_pending_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	carried_row.add_child(_pending_row)
	var carried_fill := Control.new()
	carried_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carried_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carried_row.add_child(carried_fill)
	section.add_child(carried_row)

	var new_row := UI.hbox(8)
	new_row.custom_minimum_size = Vector2(0.0, 54.0)
	var new_title := UI.label("新购道具", 20, FateConfig.COLOR_GOLD)
	new_title.custom_minimum_size = Vector2(112.0, 0.0)
	new_row.add_child(new_title)
	_new_row = UI.hbox(8)
	_new_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	new_row.add_child(_new_row)
	var new_fill := Control.new()
	new_fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_row.add_child(new_fill)
	section.add_child(new_row)

	var slot_line := UI.hbox(8)
	slot_line.custom_minimum_size = Vector2(0.0, 62.0)
	slot_line.add_child(_make_section_button("携带弹珠",
			_on_open_balls_pressed))
	_slots_row = UI.hbox(10)
	_slots_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_slots_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_line.add_child(_slots_row)
	section.add_child(slot_line)

	return section


## 行首黄色可点击标题（无边框，触屏按钮）。
func _make_section_button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.custom_minimum_size = Vector2(112.0, 40.0)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	btn.add_theme_color_override("font_hover_color", FateConfig.COLOR_JADE)
	btn.add_theme_color_override("font_pressed_color", FateConfig.COLOR_JADE)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, empty)
	btn.pressed.connect(handler)
	return btn


func _build_footer() -> Control:
	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	_status_label = UI.label("", 14, FateConfig.COLOR_CRIMSON,
			HORIZONTAL_ALIGNMENT_CENTER)
	_status_label.visible = false
	box.add_child(_status_label)

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
	for text in ["得分 ×2 · 命核碎片 ×2", "黑色立柱扣分 ×2", "失败时命运碎片减半",
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
	# v1.8：隐藏关（第 10 间/命源）未解锁前只显示「第 X 间」，不泄露总关数
	var level_display := ""
	if _gs.level == _level:
		level_display = _gs.level_display()
	elif _gs.has_source_ball():
		level_display = "第 %d / %d 间" % [_level, FateConfig.MAX_LEVEL]
	else:
		level_display = "第 %d 间" % _level
	_level_label.text = "%s · %s" % [level_display,
			FateConfig.LEVEL_NAMES[_level - 1]]
	if _gs.level == _level:
		_target_label.text = "目标 %d 分" % _gs.get_target()
	else:
		_target_label.text = "目标 %d 分" % FateConfig.LEVEL_TARGETS[_level - 1]
	_coins_label.text = str(_gs.coins)
	var buff: Dictionary = FateConfig.LEVEL_BUFFS[_level - 1]
	_buff_label.text = "%s：%s" % [String(buff.get("name", "")),
			String(buff.get("desc", ""))]
	var event: Dictionary = _gs.fate_event
	if event.is_empty():
		_event_label.text = "本关没有命运事件"
	else:
		_event_label.text = "%s：%s" % [String(event.get("name", "")),
				String(event.get("desc", ""))]
	_update_refresh_btn()
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
	var owned_passive := kind == "passive" and _gs != null \
			and _gs.run_items.has(id)
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
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(44.0, 44.0)
	icon_box.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_box.gui_input.connect(_on_detail_icon_input.bind(id))
	icon_box.add_child(UI.item_icon(id, 44.0))
	top.add_child(icon_box)
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
	price_row.add_child(UI.label("命核碎片", 11, FateConfig.COLOR_TEXT_DIM))
	box.add_child(price_row)

	var buy_btn := UI.button("购买", 18, 52.0)
	var bought_this_room := _gs != null and _gs.is_item_bought(id)
	if bought_this_room:
		buy_btn.text = "已购买"
		buy_btn.disabled = true
		buy_btn.modulate = Color(0.62, 0.62, 0.68)
	elif owned_passive:
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
		"instant":
			return "购买即生效"
		"library":
			return "进弹珠库"
		_:
			return kind


func _update_deck() -> void:
	# 携带道具（pending items，逐个不堆叠）
	for child in _pending_row.get_children():
		_pending_row.remove_child(child)
		child.queue_free()
	var pending: Array[String] = []
	var bought: Array[String] = []
	if _gs != null:
		pending = _gs.get_pending_items()
		bought = _gs.bought_items_this_room.duplicate()
	if pending.is_empty():
		_pending_row.add_child(UI.label("（空）", 12, FateConfig.COLOR_TEXT_DIM))
	else:
		for id in pending:
			_pending_row.add_child(_make_pending_chip(id))

	# 新购道具（本关已购买，逐个不堆叠）
	for child in _new_row.get_children():
		_new_row.remove_child(child)
		child.queue_free()
	if bought.is_empty():
		_new_row.add_child(UI.label("（本关尚未购买）", 12,
				FateConfig.COLOR_TEXT_DIM))
	else:
		for id in bought:
			_new_row.add_child(_make_pending_chip(id))

	_update_slots()


func _make_pending_chip(id: String) -> Control:
	# v1.6/1.7：相同道具不堆叠，逐个图标
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(44.0, 44.0)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.20, 0.14, 0.31, 0.95), FateConfig.COLOR_GOLD_DIM, 10, 1, false))
	holder.gui_input.connect(_on_detail_icon_input.bind(id))
	var tex := UI.item_icon(id, 34.0)
	tex.position = Vector2(5.0, 5.0)
	holder.add_child(tex)
	return holder


func _update_slots() -> void:
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	if _gs == null:
		return
	for i in range(_gs.balls_total):
		var slot: Dictionary = _gs.get_ball_slot(i)
		var ball_type := clampi(int(slot.get("type", 0)), 0, 2)
		var card := String(slot.get("card", ""))
		var chip := UI.vbox(0)
		chip.alignment = BoxContainer.ALIGNMENT_CENTER
		var icon_center := Control.new()
		icon_center.custom_minimum_size = Vector2(38.0, 38.0)
		icon_center.mouse_filter = Control.MOUSE_FILTER_STOP
		icon_center.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		icon_center.gui_input.connect(_on_ball_icon_input.bind(ball_type))
		var ball_icon := UI.ball_icon_type(ball_type, 34.0)
		ball_icon.position = Vector2(2.0, 2.0)
		icon_center.add_child(ball_icon)
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
	var full := card_id
	if FateConfig.ITEMS.has(card_id):
		full = String(FateConfig.ITEMS[card_id].get("name", card_id))
	return full.trim_suffix("卡")


# ==================================================================
# 交互 / 动画
# ==================================================================

func _update_refresh_btn() -> void:
	if _refresh_btn == null or _gs == null:
		return
	var cost := _gs.get_refresh_cost()
	_refresh_btn.text = "刷新货架（%d 命核碎片）" % cost
	_refresh_btn.disabled = _gs.coins < cost
	if _refresh_hint != null:
		_refresh_hint.text = "已刷新 %d 次" % int(_gs.refresh_count)


func _on_refresh_pressed() -> void:
	if _gs == null:
		return
	var cost := _gs.get_refresh_cost()
	if _gs.coins < cost:
		_flash("命核碎片不足，无法刷新")
		return
	var offers := _gs.refresh_shop_offers()
	if offers.is_empty():
		_flash("命核碎片不足，无法刷新")
		return
	_offers.clear()
	for id in offers:
		_offers.append(id)
	UI.play_sfx("click")
	refresh()


func _on_buy(id: String) -> void:
	if _gs == null:
		return
	if _gs.is_item_bought(id):
		_flash("本轮已经购买过这件道具了")
		return
	if not _gs.can_buy_item(id):
		var info: Dictionary = FateConfig.ITEMS.get(id, {})
		if String(info.get("kind", "")) == "passive" \
				and _gs.run_items.has(id):
			_flash("这件遗物已经生效了")
		else:
			_flash("命核碎片不足")
		return
	if _gs.buy_item(id):
		UI.play_sfx("success")
		_bought_ids[id] = true
		refresh()
	else:
		_flash("无法购买")


# ==================================================================
# 道具 / 弹珠详情弹窗
# ==================================================================

func _ensure_detail_popup() -> Control:
	if _detail_popup == null or not is_instance_valid(_detail_popup):
		_detail_popup = DetailPopup.new()
		add_child(_detail_popup)
	return _detail_popup


func _show_item_detail(item_id: String) -> void:
	if FateConfig.ITEMS.has(item_id):
		_ensure_detail_popup().call("open_item", item_id)


func _show_ball_detail(ball_type: int) -> void:
	_ensure_detail_popup().call("open_ball", ball_type)


func _on_detail_icon_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_show_item_detail(item_id)


func _on_ball_icon_input(event: InputEvent, ball_type: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_show_ball_detail(ball_type)


func _on_open_items_pressed() -> void:
	_open_character_tab(2)


func _on_open_balls_pressed() -> void:
	_open_character_tab(1)


## 从商店打开个人信息面板并定位到指定 tab（0 角色信息 / 1 弹珠 / 2 卡牌）。
func _open_character_tab(tab_index: int) -> void:
	UI.play_sfx("click")
	if _char_panel != null and is_instance_valid(_char_panel):
		if _char_panel.has_method("open_to_tab"):
			_char_panel.call("open_to_tab", tab_index)
		elif _char_panel.has_method("open_panel"):
			_char_panel.call("open_panel", tab_index)
		return
	var path := "res://scenes/ui/character_panel.tscn"
	if not ResourceLoader.exists(path):
		_flash("个人信息面板缺失")
		return
	var packed := load(path)
	if not (packed is PackedScene):
		_flash("个人信息面板加载失败")
		return
	_char_panel = (packed as PackedScene).instantiate()
	add_child(_char_panel)
	if _char_panel.has_signal("closed"):
		_char_panel.connect("closed", Callable(self, "_on_char_panel_closed"))
	if _char_panel.has_method("open_to_tab"):
		_char_panel.call("open_to_tab", tab_index)
	elif _char_panel.has_method("open_panel"):
		_char_panel.call("open_panel", tab_index)


func _on_char_panel_closed() -> void:
	if _char_panel != null and is_instance_valid(_char_panel):
		_char_panel.queue_free()
	_char_panel = null
	refresh()


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


func _on_library_changed(_normal_count: int, _advanced_count: int,
		_high_count: int) -> void:
	refresh()


func _on_balls_changed(_balls_left: int, _balls_total: int) -> void:
	refresh()

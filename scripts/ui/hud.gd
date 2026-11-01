extends Control
## 《？！珠珠！？》P1 布局 HUD（v1.1，由 gameplay 实例化）。
##
## 布局严格取自 FateConfig 常量：
##   ① HUD_CELL_SCORE  目标/当前分 + 关卡名/命运事件
##   ② HUD_CELL_COIN   金币
##   ③ HUD_CELL_BALL   可用弹珠灯（数量 = balls_total，buffed 变红，进阶金框）
##   ⑦ ITEM_AREA       商店货品 + 已购待用道具（长按拖拽使用）
##   ⑧ LIBRARY_AREA    弹珠库（合成 / 拖珠替换弹珠灯）
##   ⑥ CLOSE_RECT      关闭商店（SHOP 阶段）
##
## 接口见 docs/CONTRACT_V2.md 第 5 节。

signal shop_closed
signal exit_pressed
signal equip_requested(item_id: String, screen_pos: Vector2)

const UI := preload("res://scripts/ui/ui_theme.gd")

const LONG_PRESS_SEC := 0.25
const LAMP_SIZE := 48.0
const GHOST_SIZE := 64.0

const PHASE_SHOP := 0
const PHASE_PLAY := 1
const PHASE_RESULT := 2

var _gs := UI.game_state()
var _game: Node = null
var _phase: int = PHASE_SHOP
var _offers: Array[String] = []
var _built := false

# ---- 顶栏 ----
var _score_level_label: Label = null
var _score_event_label: Label = null
var _score_current: Label = null
var _score_target: Label = null
var _coin_label: Label = null
var _ball_left_label: Label = null
var _phase_hint_panel: PanelContainer = null
var _phase_hint_label: Label = null
var _phase_hint_text: String = ""

# ---- 弹珠灯 ----
var _lamps_box: HBoxContainer = null
var _lamps: Array[Control] = []
var _lamp_icons: Array[TextureRect] = []
var _lamp_glows: Array[Panel] = []
var _lamp_borders: Array[Panel] = []
var _lamp_highlights: Array[Panel] = []
var _lamp_dots: Array[Panel] = []
var _lamp_names: Array[Label] = []
var _lamp_glow_normal: StyleBoxFlat = null
var _lamp_glow_buffed: StyleBoxFlat = null
var _lamp_adv_border: StyleBoxFlat = null
var _lamp_hilite: StyleBoxFlat = null
var _lamp_count: int = -1

# ---- ⑦ 道具区 ----
var _item_panel: PanelContainer = null
var _item_root: VBoxContainer = null
var _offer_cards: Dictionary = {}
var _item_sig: String = ""
var _item_dirty := false
var _bought_ids: Dictionary = {}

# ---- ⑧ 弹珠库 ----
var _lib_normal_holder: Control = null
var _lib_advanced_holder: Control = null
var _lib_normal_hl: Panel = null
var _lib_advanced_hl: Panel = null
var _lib_normal_count: Label = null
var _lib_advanced_count: Label = null
var _lib_merge_btn: Button = null
var _lib_sel_label: Label = null
var _lib_sel_dots: Array[Panel] = []
var _selection_active := false
var _selection_count := 0

# ---- ⑥ ----
var _close_btn: Button = null

# ---- 横幅 / 提示 ----
var _banner: PanelContainer = null
var _banner_title: Label = null
var _banner_desc: Label = null
var _banner_tween: Tween = null
var _flash_label: Label = null
var _flash_tween: Tween = null
var _score_overlay: Control = null

# ---- 拖拽 ----
var _drag_layer: Control = null
var _ghost: Control = null
var _press_active := false
var _drag_active := false
var _press_kind: String = ""
var _press_item: String = ""
var _press_source: Control = null
var _press_time: int = 0
var _press_start_view: Vector2 = Vector2.ZERO
var _pointer_view: Vector2 = Vector2.ZERO

# ---- 卡牌详情（短按 ⑦ 待使用道具）----
var _detail_root: Control = null
var _detail_body: VBoxContainer = null


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_gs = UI.game_state()
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(self)
	set_process(true)

	_lamp_glow_normal = _make_glow_style(false)
	_lamp_glow_buffed = _make_glow_style(true)
	_lamp_adv_border = _make_border_style(FateConfig.COLOR_GOLD, 2)
	_lamp_hilite = _make_border_style(FateConfig.COLOR_JADE, 2)

	_build_score_cell()
	_build_coin_cell()
	_build_ball_cell()
	_build_item_area()
	_build_library_area()
	_build_phase_hint()
	_build_close_button()
	_build_banner()
	_build_flash()
	_build_drag_layer()
	_build_detail()

	_score_overlay = Control.new()
	_score_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(_score_overlay)
	add_child(_score_overlay)

	_connect_signals()
	refresh()


# ==================================================================
# 公共接口
# ==================================================================

func set_game(game: Node) -> void:
	_game = game


## 0=SHOP 1=PLAY 2=RESULT
func set_phase(phase: int) -> void:
	if not _built:
		_ensure_built()
	_phase = clampi(phase, PHASE_SHOP, PHASE_RESULT)
	if _close_btn != null:
		_close_btn.visible = _phase == PHASE_SHOP
	# 每个阶段一条默认提示，set_phase_hint 可再覆盖（如“本间通过”）
	_phase_hint_text = _default_hint_for_phase(_phase)
	_apply_phase_hint()
	_item_sig = ""
	_update_item_area()


## 商店阶段打开 ⑦ 区货架（3 件货品）。
func open_shop(level: int, offers: Array[String]) -> void:
	if not _built:
		_ensure_built()
	_phase = PHASE_SHOP
	if _close_btn != null:
		_close_btn.visible = true
	_offers.clear()
	for id in offers:
		if FateConfig.ITEMS.has(id):
			_offers.append(id)
	_bought_ids.clear()
	_item_sig = ""
	_update_item_area()


## 手动刷新全部区域（gameplay 在状态变化后调用；信号也会触发自动刷新）。
func refresh() -> void:
	if not _built:
		_ensure_built()
		return
	if _gs == null:
		_gs = UI.game_state()
		if _gs == null:
			return
	_update_score_cell()
	_update_coin_cell()
	_ensure_lamps()
	_update_lamps()
	_update_item_area()
	_update_library()


func set_phase_hint(text: String) -> void:
	if not _built:
		_ensure_built()
	if _phase_hint_label == null:
		return
	# gameplay 的提示可能是“关卡信息\n操作说明”两行；底部窄条只显示操作说明那一行
	var display := text.strip_edges()
	if display.contains("\n"):
		var lines := display.split("\n")
		for i in range(lines.size() - 1, -1, -1):
			var line := String(lines[i]).strip_edges()
			if line != "":
				display = line
				break
	_phase_hint_text = display
	_apply_phase_hint()


func _default_hint_for_phase(phase: int) -> String:
	match phase:
		PHASE_SHOP:
			return "拖动装备到立柱、增益卡到弹珠灯，点 ❌ 开始"
		PHASE_PLAY:
			return "按住右下弹簧蓄力 · 松手发射"
		_:
			return ""


func _apply_phase_hint() -> void:
	if _phase_hint_label == null or _phase_hint_panel == null:
		return
	_phase_hint_label.text = _phase_hint_text
	_phase_hint_panel.visible = _phase_hint_text != ""


## 顶部横幅：命运事件名 + 描述，停留 1.8s 后淡出。
func show_fate_event(event: Dictionary) -> void:
	if not _built:
		_ensure_built()
	if _banner == null:
		return
	if event.is_empty():
		_banner.visible = false
		return
	_banner_title.text = "命运事件 · " + String(event.get("name", "未知命运"))
	_banner_desc.text = String(event.get("desc", ""))
	_banner.visible = true
	if not is_inside_tree():
		_banner.modulate.a = 1.0
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.45)
	_banner_tween.tween_callback(func() -> void:
		_banner.visible = false
	)


## 飘分：world_pos 为世界坐标，换算到 HUD 本地后上浮淡出。
func popup_score(value: int, world_pos: Vector2) -> void:
	if not _built:
		_ensure_built()
	if _score_overlay == null or not is_inside_tree():
		return
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var local_pos: Vector2 = _viewport_to_local(screen_pos)
	var text := "+%d" % value if value >= 0 else "-%d" % absi(value)
	var color := FateConfig.COLOR_GOLD if value > 0 else FateConfig.COLOR_TEXT_DIM
	var lbl := UI.label(text, 32, color, HORIZONTAL_ALIGNMENT_CENTER)
	lbl.size = Vector2(240.0, 44.0)
	lbl.position = local_pos - Vector2(120.0, 22.0)
	lbl.add_theme_color_override("font_outline_color",
			Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, 0.9))
	lbl.add_theme_constant_override("outline_size", 8)
	_score_overlay.add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 76.0, 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(lbl.queue_free)


## 操作无效 / 金币不足的红色浮动提示。
func flash_error(text: String) -> void:
	if not _built:
		_ensure_built()
	if _flash_label == null:
		return
	_flash_label.text = text
	_flash_label.visible = true
	_flash_label.modulate.a = 1.0
	if not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(1.0)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 0.45)
	_flash_tween.tween_callback(func() -> void:
		_flash_label.visible = false
	)


# ==================================================================
# 顶栏三格
# ==================================================================

func _build_score_cell() -> void:
	var cell := _make_cell(FateConfig.HUD_CELL_SCORE, 16)
	var row := UI.hbox(8)
	cell.add_child(row)

	var left := UI.vbox(0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_level_label = UI.label("第 1 间 · 裂纹初现", 17, FateConfig.COLOR_GOLD)
	left.add_child(_score_level_label)
	_score_event_label = UI.label("命运事件 · —", 11, FateConfig.COLOR_VIOLET)
	left.add_child(_score_event_label)
	row.add_child(left)

	var right := UI.vbox(0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var score_line := UI.hbox(5)
	score_line.alignment = BoxContainer.ALIGNMENT_END
	_score_current = UI.label("0", 30, FateConfig.COLOR_JADE)
	score_line.add_child(_score_current)
	score_line.add_child(UI.label("/", 15, FateConfig.COLOR_TEXT_DIM))
	_score_target = UI.label("25", 18, FateConfig.COLOR_TEXT_DIM)
	score_line.add_child(_score_target)
	right.add_child(score_line)
	right.add_child(UI.label("当前 / 目标", 10, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(right)


func _build_coin_cell() -> void:
	var cell := _make_cell(FateConfig.HUD_CELL_COIN, 16)
	var row := UI.hbox(10)
	cell.add_child(row)
	row.add_child(UI.icon("coin", 38.0))
	_coin_label = UI.label("9", 34, FateConfig.COLOR_GOLD)
	row.add_child(_coin_label)
	row.add_child(UI.label("金币", 13, FateConfig.COLOR_TEXT_DIM))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fill)
	row.add_child(UI.label("命运碎片 " + str(_gs.total_shards if _gs != null else 0),
			12, FateConfig.COLOR_VIOLET))


func _build_ball_cell() -> void:
	var cell := _make_cell(FateConfig.HUD_CELL_BALL, 16)
	var row := UI.hbox(10)
	cell.add_child(row)
	var left := UI.vbox(0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(UI.label("可用弹珠", 11, FateConfig.COLOR_TEXT_DIM))
	_ball_left_label = UI.label("5/5", 14, FateConfig.COLOR_TEXT)
	left.add_child(_ball_left_label)
	row.add_child(left)
	_lamps_box = UI.hbox(7)
	_lamps_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lamps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_lamps_box)


## 提示条放在 ⑧ 弹珠库面板底部（x<632 左栏内），不覆盖右侧台面。
func _build_phase_hint() -> void:
	_phase_hint_panel = PanelContainer.new()
	_phase_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_hint_panel.position = Vector2(16.0, 684.0)
	_phase_hint_panel.size = Vector2(608.0, 26.0)
	_phase_hint_panel.custom_minimum_size = Vector2(608.0, 26.0)
	var style := UI.panel_style(Color(0.05, 0.035, 0.09, 0.78),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.22), 8, 1, false)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	_phase_hint_panel.add_theme_stylebox_override("panel", style)
	add_child(_phase_hint_panel)

	_phase_hint_label = UI.label("", 12,
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.88), HORIZONTAL_ALIGNMENT_CENTER)
	_phase_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_phase_hint_label.clip_text = true
	_phase_hint_panel.add_child(_phase_hint_label)
	_phase_hint_panel.visible = false


# ==================================================================
# ③ 弹珠灯
# ==================================================================

func _ensure_lamps() -> void:
	if _gs == null:
		return
	var count: int = maxi(_gs.balls_total, 0)
	if count == _lamp_count:
		return
	_lamp_count = count
	_lamps.clear()
	_lamp_icons.clear()
	_lamp_glows.clear()
	_lamp_borders.clear()
	_lamp_highlights.clear()
	_lamp_dots.clear()
	_lamp_names.clear()
	for child in _lamps_box.get_children():
		_lamps_box.remove_child(child)
		child.queue_free()
	for i in count:
		var lamp := _make_lamp()
		_lamps_box.add_child(lamp)
		_lamps.append(lamp)


func _make_lamp() -> Control:
	# 每盏灯 = 48×48 珠图标 + 底部卡名小字（红色）
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(LAMP_SIZE, LAMP_SIZE + 12.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lamp := Control.new()
	lamp.custom_minimum_size = Vector2(LAMP_SIZE, LAMP_SIZE)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lamp)

	var glow := Panel.new()
	glow.position = Vector2(-6.0, -6.0)
	glow.size = Vector2(LAMP_SIZE + 12.0, LAMP_SIZE + 12.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", _lamp_glow_normal)
	lamp.add_child(glow)

	var icon := TextureRect.new()
	icon.texture = UI.load_texture("res://assets/art/ball_normal.png")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(2.0, 2.0)
	icon.size = Vector2(LAMP_SIZE - 4.0, LAMP_SIZE - 4.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.add_child(icon)

	var border := Panel.new()
	border.position = Vector2.ZERO
	border.size = Vector2(LAMP_SIZE, LAMP_SIZE)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override("panel", _lamp_adv_border)
	border.visible = false
	lamp.add_child(border)

	var highlight := Panel.new()
	highlight.position = Vector2(-3.0, -3.0)
	highlight.size = Vector2(LAMP_SIZE + 6.0, LAMP_SIZE + 6.0)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.add_theme_stylebox_override("panel", _lamp_hilite)
	highlight.visible = false
	lamp.add_child(highlight)

	var dot := Panel.new()
	dot.position = Vector2(LAMP_SIZE - 14.0, 2.0)
	dot.size = Vector2(10.0, 10.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.set_corner_radius_all(0)
	dot_style.bg_color = FateConfig.COLOR_GOLD
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.visible = false
	lamp.add_child(dot)

	var name_label := UI.label("", 9, FateConfig.COLOR_CRIMSON,
			HORIZONTAL_ALIGNMENT_CENTER)
	name_label.custom_minimum_size = Vector2(LAMP_SIZE, 12.0)
	name_label.clip_text = true
	box.add_child(name_label)

	_lamp_icons.append(icon)
	_lamp_glows.append(glow)
	_lamp_borders.append(border)
	_lamp_highlights.append(highlight)
	_lamp_dots.append(dot)
	_lamp_names.append(name_label)
	return box


func _update_lamps() -> void:
	if _gs == null:
		return
	var total: int = _gs.balls_total
	var used_count: int = clampi(total - _gs.balls_left, 0, total)
	if _ball_left_label != null:
		_ball_left_label.text = "%d/%d" % [_gs.balls_left, total]
	for i in _lamps.size():
		var used := i < used_count
		var slot: Dictionary = _gs.get_ball_slot(i)
		var advanced := int(slot.get("type", 0)) == 1
		var card := String(slot.get("card", ""))
		var has_card := card != ""
		var tint := Color(1.0, 0.42, 0.45) if has_card else Color(1.0, 1.0, 1.0)
		if used:
			tint = Color(0.55, 0.26, 0.30, 0.6) if has_card \
					else Color(0.34, 0.32, 0.42, 0.5)
		_lamp_icons[i].modulate = tint
		_lamp_glows[i].visible = not used and has_card
		_lamp_borders[i].visible = advanced
		_lamp_borders[i].modulate = Color(1.0, 1.0, 1.0,
				1.0 if not used else 0.35)
		_lamp_dots[i].visible = advanced
		_lamp_dots[i].modulate = Color(1.0, 1.0, 1.0,
				1.0 if not used else 0.35)
		var name_label := _lamp_names[i]
		name_label.text = _short_card_name(card) if has_card else ""
		name_label.add_theme_color_override("font_color",
				Color(FateConfig.COLOR_CRIMSON.r, FateConfig.COLOR_CRIMSON.g,
				FateConfig.COLOR_CRIMSON.b, 1.0 if not used else 0.45))


func _short_card_name(card_id: String) -> String:
	if card_id == "":
		return ""
	var full := card_id
	if _gs != null:
		full = _gs.get_card_name(card_id)
	if full == "":
		full = card_id
	return full.trim_suffix("卡")


func _make_glow_style(buffed: bool) -> StyleBoxFlat:
	# 像素风：方形硬色块，无柔光阴影
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_border_width_all(0)
	if buffed:
		style.bg_color = Color(1.0, 0.24, 0.32, 0.22)
	else:
		style.bg_color = Color(0.91, 0.76, 0.42, 0.12)
	return style


func _make_border_style(color: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_border_width_all(width)
	style.border_color = color
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.anti_aliasing = false
	return style


func _set_lamp_highlight(active: bool) -> void:
	for i in _lamp_highlights.size():
		_lamp_highlights[i].visible = active and not _is_lamp_used(i)


func _is_lamp_used(index: int) -> bool:
	if _gs == null:
		return false
	var used_count: int = clampi(_gs.balls_total - _gs.balls_left, 0,
			_gs.balls_total)
	return index < used_count


func _lamp_at(viewport_pos: Vector2) -> int:
	for i in _lamps.size():
		if _control_view_rect(_lamps[i]).grow(8.0).has_point(viewport_pos):
			return i
	return -1


# ==================================================================
# ⑦ 道具区
# ==================================================================

func _build_item_area() -> void:
	_item_panel = _make_cell(FateConfig.ITEM_AREA, 18)
	# 「待使用」行与面板底边框留出 4px 呼吸空间
	var sb := _item_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.content_margin_bottom = 12.0
	_item_root = UI.vbox(7)
	_item_panel.add_child(_item_root)


func _update_item_area() -> void:
	if _item_panel == null or _gs == null:
		return
	var pending := _gs.get_pending_items()
	var sig := "%d|%s|%s|%d|%d" % [_phase, str(_offers), str(pending),
			_gs.coins, _gs.level]
	if sig == _item_sig:
		return
	_item_sig = sig
	if _press_active or _drag_active:
		_item_dirty = true
		return
	_item_dirty = false
	_rebuild_item_area()


func _rebuild_item_area() -> void:
	for child in _item_root.get_children():
		_item_root.remove_child(child)
		child.queue_free()
	_offer_cards.clear()

	# 标题行
	var header := UI.hbox(8)
	header.add_child(UI.label("道具库", 19, FateConfig.COLOR_GOLD))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(fill)
	var hint_text := "长按图标拖到右侧立柱使用" if _phase == PHASE_PLAY \
			else "点击购买 · 长按已购道具拖拽使用"
	header.add_child(UI.label(hint_text, 11, FateConfig.COLOR_TEXT_DIM))
	_item_root.add_child(header)

	# 商店货品（仅 SHOP）
	var pending: Array[String] = []
	if _gs != null:
		pending = _gs.get_pending_items()
	if _phase == PHASE_SHOP and not _offers.is_empty():
		var cards := UI.hbox(10)
		cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for id in _offers:
			cards.add_child(_make_offer_card(id))
		_item_root.add_child(cards)
	else:
		var empty := CenterContainer.new()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var empty_text := "长按下方道具，拖到右侧立柱或上方弹珠灯使用" \
				if not pending.is_empty() \
				else "暂无待使用道具 · 在商店购买后长按拖拽使用"
		empty.add_child(UI.label(empty_text, 13, FateConfig.COLOR_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER))
		_item_root.add_child(empty)

	# 已购待使用道具
	_item_root.add_child(_build_pending_row())


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
			Color(0.16, 0.11, 0.26, 0.94),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.8), 14, 1))
	_offer_cards[id] = card

	var box := UI.vbox(3)
	card.add_child(box)

	var top := UI.hbox(6)
	top.add_child(UI.item_icon(id, 30.0))
	var name_label := UI.label(item_name, 16, FateConfig.COLOR_GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	box.add_child(top)

	box.add_child(UI.label(tag + " · " + _kind_label(kind), 10,
			FateConfig.COLOR_VIOLET))

	var desc_label := UI.label(desc, 11, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(0.0, 32.0)
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc_label)

	var price_row := UI.hbox(4)
	price_row.add_child(UI.icon("coin", 15.0))
	price_row.add_child(UI.label(str(cost), 14, FateConfig.COLOR_GOLD))
	price_row.add_child(UI.label("金币", 10, FateConfig.COLOR_TEXT_DIM))
	box.add_child(price_row)

	var buy_btn := UI.button("购买", 15, 48.0)
	if _bought_ids.has(id):
		buy_btn.text = "已购 ✓"
	if owned_passive:
		buy_btn.text = "已获得"
		buy_btn.disabled = true
	elif not can_buy:
		buy_btn.modulate = Color(0.62, 0.62, 0.68)
	buy_btn.pressed.connect(_on_buy_offer.bind(id))
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


func _build_pending_row() -> HBoxContainer:
	var row := UI.hbox(7)
	row.add_child(UI.label("待使用", 12, FateConfig.COLOR_TEXT_DIM))
	var pending: Array[String] = []
	if _gs != null:
		pending = _gs.get_pending_items()
	if pending.is_empty():
		row.add_child(UI.label("（购买装备 / 增益卡后拖动到右侧立柱或弹珠灯）",
				11, FateConfig.COLOR_TEXT_DIM))
		return row
	var counts: Dictionary = {}
	var order: Array[String] = []
	for id in pending:
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	for id in order:
		row.add_child(_make_pending_icon(id, int(counts[id])))
	return row


func _make_pending_icon(id: String, count: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(54.0, 54.0)
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := Panel.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(54.0, 54.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.20, 0.14, 0.31, 0.95), FateConfig.COLOR_GOLD_DIM, 12, 1, false))
	holder.add_child(bg)

	var tex := UI.item_icon(id, 42.0)
	tex.position = Vector2(6.0, 6.0)
	holder.add_child(tex)

	if count > 1:
		var badge := UI.label("×%d" % count, 11, FateConfig.COLOR_TEXT)
		badge.position = Vector2(30.0, 36.0)
		badge.size = Vector2(22.0, 16.0)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		holder.add_child(badge)

	_attach_drag_source(holder, "pending", id)
	return holder


func _on_buy_offer(id: String) -> void:
	if _gs == null:
		return
	if not _gs.can_buy_item(id):
		var info: Dictionary = FateConfig.ITEMS.get(id, {})
		if String(info.get("kind", "")) == "passive" and _gs.has_item(id):
			flash_error("这件遗物已经生效了")
		else:
			flash_error("金币不足")
		_item_sig = ""
		_update_item_area()
		return
	if _gs.buy_item(id):
		UI.play_sfx("buy")
		_bought_ids[id] = true
		_item_sig = ""
		refresh()
	else:
		flash_error("无法购买")


# ==================================================================
# ⑧ 弹珠库
# ==================================================================

func _build_library_area() -> void:
	var panel := _make_cell(FateConfig.LIBRARY_AREA, 18)
	var root := UI.vbox(4)
	panel.add_child(root)

	var header := UI.hbox(8)
	header.add_child(UI.label("弹珠库", 19, FateConfig.COLOR_GOLD))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(fill)
	header.add_child(UI.label("长按普通珠选择合成 · 拖珠子到弹珠灯替换", 11,
			FateConfig.COLOR_TEXT_DIM))
	var exit_btn := UI.button("返回标题", 12, 36.0)
	exit_btn.custom_minimum_size = Vector2(96.0, 36.0)
	exit_btn.pressed.connect(_on_exit_pressed)
	header.add_child(exit_btn)
	root.add_child(header)

	var body := UI.hbox(18)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(body)

	# 普通珠
	var normal_box := UI.vbox(2)
	normal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lib_normal_holder = _make_library_holder("ball_normal", "library_normal")
	_lib_normal_hl = _lib_normal_holder.get_meta("highlight")
	normal_box.add_child(_lib_normal_holder)
	_lib_normal_count = UI.label("普通 × 0", 14, FateConfig.COLOR_TEXT)
	normal_box.add_child(_lib_normal_count)
	body.add_child(normal_box)

	# 进阶珠
	var advanced_box := UI.vbox(2)
	advanced_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lib_advanced_holder = _make_library_holder("ball_advanced", "library_advanced")
	_lib_advanced_hl = _lib_advanced_holder.get_meta("highlight")
	advanced_box.add_child(_lib_advanced_holder)
	_lib_advanced_count = UI.label("进阶 × 0", 14, FateConfig.COLOR_GOLD)
	advanced_box.add_child(_lib_advanced_count)
	body.add_child(advanced_box)

	# 合成操作
	var action := UI.vbox(3)
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	_lib_merge_btn = UI.button("合成进阶", 14, 44.0)
	_lib_merge_btn.custom_minimum_size = Vector2(132.0, 44.0)
	_lib_merge_btn.visible = false
	_lib_merge_btn.pressed.connect(_on_merge_pressed)
	action.add_child(_lib_merge_btn)
	_lib_sel_label = UI.label("", 11, FateConfig.COLOR_JADE,
			HORIZONTAL_ALIGNMENT_CENTER)
	action.add_child(_lib_sel_label)
	var dots := UI.hbox(5)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 3:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(12.0, 12.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
		_lib_sel_dots.append(dot)
	action.add_child(dots)
	body.add_child(action)


func _make_library_holder(texture_name: String, drag_kind: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(76.0, 76.0)
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := Panel.new()
	bg.size = Vector2(76.0, 76.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.17, 0.12, 0.27, 0.95), FateConfig.COLOR_PANEL_EDGE, 16, 1, false))
	holder.add_child(bg)

	var tex := TextureRect.new()
	tex.texture = UI.load_texture("res://assets/art/%s.png" % texture_name)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.position = Vector2(6.0, 6.0)
	tex.size = Vector2(64.0, 64.0)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tex)

	var highlight := Panel.new()
	highlight.position = Vector2(-2.0, -2.0)
	highlight.size = Vector2(80.0, 80.0)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.add_theme_stylebox_override("panel", _make_border_style(
			FateConfig.COLOR_GOLD, 2))
	highlight.visible = false
	holder.add_child(highlight)
	holder.set_meta("highlight", highlight)

	_attach_drag_source(holder, drag_kind, "")
	return holder


func _update_library() -> void:
	if _gs == null or _lib_normal_count == null:
		return
	var normal: int = _gs.library_normal
	var advanced: int = _gs.library_advanced
	_lib_normal_count.text = "普通 × %d" % normal
	_lib_advanced_count.text = "进阶 × %d" % advanced
	_lib_normal_holder.modulate = Color(1.0, 1.0, 1.0) if normal > 0 \
			else Color(0.55, 0.53, 0.62, 0.6)
	_lib_advanced_holder.modulate = Color(1.0, 1.0, 1.0) if advanced > 0 \
			else Color(0.55, 0.53, 0.62, 0.6)

	if _selection_count > 3:
		_selection_count = 3
	if _selection_count > normal:
		_selection_count = normal
	if normal <= 0:
		_selection_active = false
		_selection_count = 0

	_lib_normal_hl.visible = _selection_active and _selection_count > 0
	_lib_merge_btn.visible = _selection_active
	_lib_merge_btn.disabled = normal < 3 or _selection_count < 3
	_lib_sel_label.text = "已选 %d / 3" % _selection_count if _selection_active \
			else ""
	for i in _lib_sel_dots.size():
		var dot := _lib_sel_dots[i]
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(0)
		style.set_border_width_all(1)
		if _selection_active and i < _selection_count:
			style.bg_color = FateConfig.COLOR_GOLD
			style.border_color = Color(1.0, 0.95, 0.8, 0.9)
		else:
			style.bg_color = Color(0.10, 0.08, 0.15, 0.9)
			style.border_color = Color(0.36, 0.31, 0.47, 0.8)
		dot.add_theme_stylebox_override("panel", style)


func _on_merge_pressed() -> void:
	if _gs == null:
		return
	if _gs.library_normal < 3:
		flash_error("普通弹珠不足 3 颗")
		return
	if _gs.merge_library_balls():
		UI.play_sfx("buy")
		_reset_selection()
		refresh()
	else:
		flash_error("合成失败")


func _reset_selection() -> void:
	_selection_active = false
	_selection_count = 0


func _start_selection(count: int) -> void:
	if _gs == null or _gs.library_normal <= 0:
		return
	_selection_active = true
	_selection_count = clampi(count, 1, mini(3, _gs.library_normal))
	UI.play_sfx("click")
	_update_library()


func _on_library_tapped(kind: String) -> void:
	if kind != "library_normal" or _gs == null:
		return
	if _selection_active:
		_selection_count = clampi(_selection_count + 1, 1,
				mini(3, _gs.library_normal))
		UI.play_sfx("click")
		_update_library()
	else:
		_start_selection(1)


# ==================================================================
# ⑥ 关闭 / 返回
# ==================================================================

func _build_close_button() -> void:
	var rect := FateConfig.CLOSE_RECT
	_close_btn = UI.button("✕", 26, rect.size.y)
	_close_btn.position = rect.position
	_close_btn.size = rect.size
	_close_btn.custom_minimum_size = rect.size
	_close_btn.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
	_close_btn.add_theme_color_override("font_hover_color",
			Color(1.0, 0.78, 0.78))
	_close_btn.pressed.connect(_on_close_pressed)
	_close_btn.visible = _phase == PHASE_SHOP
	add_child(_close_btn)


func _on_close_pressed() -> void:
	UI.play_sfx("click")
	shop_closed.emit()


func _on_exit_pressed() -> void:
	UI.play_sfx("click")
	exit_pressed.emit()


# ==================================================================
# 横幅 / 提示 / 拖拽层
# ==================================================================

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.position = Vector2(648.0, 108.0)
	_banner.size = Vector2(560.0, 92.0)
	_banner.custom_minimum_size = Vector2(560.0, 0.0)
	_banner.visible = false
	_banner.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.14, 0.09, 0.24, 0.96),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.8), 14, 1))
	add_child(_banner)
	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner_title = UI.label("命运事件", 20, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_banner_title)
	_banner_desc = UI.label("", 13, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	_banner_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_desc.custom_minimum_size = Vector2(520.0, 0.0)
	box.add_child(_banner_desc)
	_banner.add_child(box)


func _build_flash() -> void:
	_flash_label = UI.label("", 22, FateConfig.COLOR_CRIMSON,
			HORIZONTAL_ALIGNMENT_CENTER)
	_flash_label.position = Vector2(400.0, 210.0)
	_flash_label.size = Vector2(480.0, 40.0)
	_flash_label.visible = false
	_flash_label.add_theme_color_override("font_outline_color",
			Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, 0.9))
	_flash_label.add_theme_constant_override("outline_size", 8)
	add_child(_flash_label)


func _build_drag_layer() -> void:
	_drag_layer = Control.new()
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(_drag_layer)
	add_child(_drag_layer)


# ==================================================================
# ⑦ 待使用道具详情（短按 <0.25s 弹窗；长按仍是拖拽）
# ==================================================================

func _build_detail() -> void:
	_detail_root = Control.new()
	_detail_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(_detail_root)
	_detail_root.visible = false
	add_child(_detail_root)

	var dim := ColorRect.new()
	dim.color = Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(dim)
	dim.gui_input.connect(_on_detail_dim_input)
	_detail_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -290.0
	panel.offset_top = -150.0
	panel.offset_right = 290.0
	panel.offset_bottom = 150.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.08, 0.06, 0.14, 0.99), FateConfig.COLOR_GOLD, 0, 4))
	_detail_root.add_child(panel)

	_detail_body = UI.vbox(10)
	panel.add_child(_detail_body)


func _on_detail_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_hide_item_detail()


func _show_item_detail(item_id: String) -> void:
	if _detail_root == null or not FateConfig.ITEMS.has(item_id):
		return
	var info: Dictionary = FateConfig.ITEMS[item_id]
	for child in _detail_body.get_children():
		_detail_body.remove_child(child)
		child.queue_free()

	var top := UI.hbox(14)
	top.add_child(UI.item_icon(item_id, 64.0))
	var info_box := UI.vbox(2)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.add_child(UI.label(String(info.get("name", item_id)), 28,
			FateConfig.COLOR_GOLD))
	info_box.add_child(UI.label("%s · %s" % [String(info.get("tag", "")),
			_kind_label(String(info.get("kind", "equipment")))], 13,
			FateConfig.COLOR_VIOLET))
	top.add_child(info_box)
	_detail_body.add_child(top)

	var desc := UI.label(String(info.get("desc", "")), 16,
			FateConfig.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0.0, 76.0)
	_detail_body.add_child(desc)

	var price_row := UI.hbox(8)
	price_row.add_child(UI.icon("coin", 24.0))
	price_row.add_child(UI.label("价格 %d 金币" % int(info.get("cost", 0)), 16,
			FateConfig.COLOR_GOLD))
	_detail_body.add_child(price_row)

	_detail_body.add_child(UI.label("点击空白处关闭（长按可拖拽使用）", 11,
			FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_detail_root.visible = true
	_detail_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_detail_root, "modulate:a", 1.0, 0.12)


func _hide_item_detail() -> void:
	if _detail_root != null:
		_detail_root.visible = false


# ==================================================================
# 拖拽
# ==================================================================

func _attach_drag_source(ctrl: Control, kind: String, item_id: String) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ctrl.set_meta("drag_kind", kind)
	ctrl.set_meta("drag_item", item_id)
	ctrl.gui_input.connect(_on_source_gui_input.bind(kind, item_id, ctrl))


func _on_source_gui_input(event: InputEvent, kind: String, item_id: String,
		ctrl: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _press_active:
		return
	_press_active = true
	_drag_active = false
	_press_kind = kind
	_press_item = item_id
	_press_source = ctrl
	_press_time = Time.get_ticks_msec()
	_pointer_view = ctrl.get_global_transform_with_canvas() * mb.position
	_press_start_view = _pointer_view
	ctrl.modulate = Color(0.72, 0.70, 0.82)


func _process(_delta: float) -> void:
	if not _press_active or _drag_active:
		return
	if Time.get_ticks_msec() - _press_time < int(LONG_PRESS_SEC * 1000.0):
		return
	_start_drag()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_view = (event as InputEventMouseMotion).position
		if _drag_active:
			_update_ghost()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_pointer_view = mb.position
	if mb.pressed:
		return
	if not _press_active:
		return
	if _drag_active:
		_finish_drag(_pointer_view)
		get_viewport().set_input_as_handled()
	else:
		_finish_tap()


func _start_drag() -> void:
	if not _press_active:
		return
	# 弹珠库没有对应珠子时不允许拖动
	if _press_kind == "library_normal" and (_gs == null or _gs.library_normal <= 0):
		_clear_press()
		return
	if _press_kind == "library_advanced" and (_gs == null or _gs.library_advanced <= 0):
		_clear_press()
		return
	_drag_active = true
	_ghost = TextureRect.new()
	_ghost.texture = _drag_texture()
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.size = Vector2(GHOST_SIZE, GHOST_SIZE)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.modulate = Color(1.0, 1.0, 1.0, 0.72)
	_drag_layer.add_child(_ghost)
	if _press_kind.begins_with("library_"):
		_set_lamp_highlight(true)
	if _press_kind == "library_normal" and _gs != null and _gs.library_normal > 0:
		_selection_active = true
		_selection_count = clampi(maxi(_selection_count, 1), 1,
				mini(3, _gs.library_normal))
		_update_library()
	_update_ghost()


func _drag_texture() -> Texture2D:
	match _press_kind:
		"library_normal":
			return UI.load_texture("res://assets/art/ball_normal.png")
		"library_advanced":
			return UI.load_texture("res://assets/art/ball_advanced.png")
		_:
			var tex := UI.icon_texture(_press_item)
			if tex != null:
				return tex
			return UI.load_texture("res://assets/art/ball_normal.png")


func _update_ghost() -> void:
	if _ghost == null:
		return
	var local := _viewport_to_local(_pointer_view)
	_ghost.position = local - Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5


func _finish_tap() -> void:
	var kind := _press_kind
	var item_id := _press_item
	_clear_press()
	if kind == "library_normal":
		_on_library_tapped(kind)
	elif kind == "pending" and item_id != "":
		_show_item_detail(item_id)


func _finish_drag(viewport_pos: Vector2) -> void:
	var kind := _press_kind
	var item_id := _press_item
	var success := false
	match kind:
		"pending":
			success = _use_pending_item(item_id, viewport_pos)
		"library_normal":
			success = _use_library_ball(false, viewport_pos)
		"library_advanced":
			success = _use_library_ball(true, viewport_pos)
		_:
			pass
	if success:
		_reset_selection()
		refresh()
	_end_drag(not success)


func _use_pending_item(id: String, viewport_pos: Vector2) -> bool:
	if _gs == null:
		return false
	var info: Dictionary = FateConfig.ITEMS.get(id, {})
	var kind := String(info.get("kind", "equipment"))
	if kind == "equipment":
		if viewport_pos.x > FateConfig.BOARD_LEFT:
			# 由 gameplay 判定立柱落点并在成功后消耗道具
			equip_requested.emit(id, viewport_pos)
			UI.play_sfx("click")
			return true
		flash_error("请把装备拖到右侧台面的立柱上")
		return false
	if kind == "card":
		var index := _lamp_at(viewport_pos)
		if index < 0:
			flash_error("请把增益卡拖到上方的弹珠灯上")
			return false
		if _is_lamp_used(index):
			flash_error("这颗弹珠已经发射过了")
			return false
		if _gs.get_ball_card(index) != "":
			flash_error("这颗弹珠已经绑定卡牌了")
			return false
		if _gs.set_ball_card(index, id):
			_gs.consume_pending_item(id)
			UI.play_sfx("coin")
			return true
		flash_error("这张卡无法绑定")
		return false
	flash_error("这里不能使用")
	return false


func _use_library_ball(advanced: bool, viewport_pos: Vector2) -> bool:
	if _gs == null:
		return false
	var index := _lamp_at(viewport_pos)
	if index < 0:
		flash_error("请把弹珠拖到上方的弹珠灯上")
		return false
	if _is_lamp_used(index):
		flash_error("这颗弹珠已经发射过了")
		return false
	if advanced and _gs.library_advanced <= 0:
		flash_error("弹珠库里没有进阶珠")
		return false
	if not advanced and _gs.library_normal <= 0:
		flash_error("弹珠库里没有普通珠")
		return false
	if bool(_gs.get_ball_slot(index).get("buffed", false)):
		flash_error("这颗弹珠已被增益，无法替换")
		return false
	if _gs.replace_ball_slot(index, advanced):
		UI.play_sfx("slot")
		return true
	flash_error("替换失败")
	return false


func _end_drag(rebound: bool) -> void:
	_set_lamp_highlight(false)
	if _press_source != null and is_instance_valid(_press_source):
		_press_source.modulate = Color(1.0, 1.0, 1.0)
	if _ghost != null:
		if rebound:
			var target := _viewport_to_local(_press_start_view) \
					- Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5
			var ghost := _ghost
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(ghost, "position", target, 0.16) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(ghost, "modulate:a", 0.0, 0.16)
			tween.chain().tween_callback(ghost.queue_free)
		else:
			_ghost.queue_free()
		_ghost = null
	_drag_active = false
	_press_active = false
	_press_kind = ""
	_press_item = ""
	_press_source = null
	if _item_dirty:
		_item_dirty = false
		_item_sig = ""
		_update_item_area()


func _clear_press() -> void:
	if _press_source != null and is_instance_valid(_press_source):
		_press_source.modulate = Color(1.0, 1.0, 1.0)
	_press_active = false
	_drag_active = false
	_press_kind = ""
	_press_item = ""
	_press_source = null


# ==================================================================
# 坐标换算
# ==================================================================

func _viewport_to_local(viewport_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_pos


func _control_view_rect(ctrl: Control) -> Rect2:
	var xf := ctrl.get_global_transform_with_canvas()
	var p0: Vector2 = xf * Vector2.ZERO
	var p1: Vector2 = xf * ctrl.size
	return Rect2(p0, p1 - p0).abs()


# ==================================================================
# 顶栏刷新 / 信号
# ==================================================================

func _update_score_cell() -> void:
	if _gs == null:
		return
	_score_level_label.text = "第 %d 间 · %s" % [_gs.level, _gs.get_level_name()]
	var event: Dictionary = _gs.fate_event
	if event.is_empty():
		_score_event_label.text = "命运事件 · —"
	else:
		_score_event_label.text = "命运事件 · " + String(event.get("name", ""))
	_score_current.text = str(_gs.level_score)
	_score_target.text = str(_gs.get_target())


func _update_coin_cell() -> void:
	if _gs == null or _coin_label == null:
		return
	_coin_label.text = str(_gs.coins)


func _make_cell(rect: Rect2, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.custom_minimum_size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _cell_style(radius))
	add_child(panel)
	return panel


func _cell_style(radius: int) -> StyleBoxFlat:
	var edge := Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.55)
	var style := UI.panel_style(Color(0.065, 0.048, 0.12, 0.96), edge, radius, 3)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _connect_signals() -> void:
	if _gs == null:
		push_warning("[HUD] 未找到 GameState，HUD 不会自动刷新")
		return
	if not _gs.coins_changed.is_connected(_on_any_changed):
		_gs.coins_changed.connect(_on_any_changed)
	if not _gs.score_changed.is_connected(_on_score_changed):
		_gs.score_changed.connect(_on_score_changed)
	if not _gs.balls_changed.is_connected(_on_balls_changed):
		_gs.balls_changed.connect(_on_balls_changed)
	if not _gs.level_started.is_connected(_on_level_started):
		_gs.level_started.connect(_on_level_started)
	if not _gs.library_changed.is_connected(_on_library_changed):
		_gs.library_changed.connect(_on_library_changed)
	if not _gs.items_changed.is_connected(_on_items_changed):
		_gs.items_changed.connect(_on_items_changed)


func _on_any_changed(_value: int) -> void:
	refresh()


func _on_score_changed(_level_score: int, _total_score: int) -> void:
	refresh()


func _on_balls_changed(_balls_left: int, _balls_total: int) -> void:
	refresh()


func _on_level_started(_level: int, _target: int, _event: Dictionary) -> void:
	refresh()


func _on_library_changed(_normal_count: int, _advanced_count: int) -> void:
	refresh()


func _on_items_changed() -> void:
	refresh()

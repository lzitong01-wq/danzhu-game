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
const DetailPopup := preload("res://scripts/ui/detail_popup.gd")

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
var _lamp_glow_source: StyleBoxFlat = null
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

# ---- ⑧ 弹珠库（v1.4：三种琉璃珠 + 合成按钮）----
var _lib_holders: Array[Control] = []
var _lib_counts: Array[Label] = []
var _lib_synth_core_btn: Button = null
var _lib_synth_source_btn: Button = null
var _lib_synth_hint: Label = null

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
var _detail_popup: Control = null


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
	_lamp_glow_source = _make_glow_style(false)
	_lamp_glow_source.bg_color = Color(0.95, 0.98, 1.0, 0.22)
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


## 操作无效 / 命核碎片不足 / 合成失败的浮动提示（红色）。
func flash_error(text: String) -> void:
	_toast(text, FateConfig.COLOR_CRIMSON)


## 通用浮动提示（合成成功用绿色等）。
func _toast(text: String, color: Color) -> void:
	if not _built:
		_ensure_built()
	if _flash_label == null:
		return
	_flash_label.add_theme_color_override("font_color", color)
	_flash_label.text = text
	_flash_label.visible = true
	_flash_label.modulate.a = 1.0
	if not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(1.2)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 0.45)
	_flash_tween.tween_callback(func() -> void:
		_flash_label.visible = false
	)


func set_toast(text: String, success: bool = true) -> void:
	_toast(text, FateConfig.COLOR_JADE if success else FateConfig.COLOR_CRIMSON)


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
	row.add_child(UI.label("命核碎片", 13, FateConfig.COLOR_TEXT_DIM))
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
	# 每盏灯 = 48×48 珠图标 + 底部卡名小字（红色）；点击查看弹珠详情
	var lamp_index := _lamp_icons.size()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(LAMP_SIZE, LAMP_SIZE + 12.0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lamp := Control.new()
	lamp.custom_minimum_size = Vector2(LAMP_SIZE, LAMP_SIZE)
	lamp.mouse_filter = Control.MOUSE_FILTER_STOP
	lamp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lamp.gui_input.connect(_on_lamp_gui_input.bind(lamp_index))
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


func _on_lamp_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton) or _gs == null:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _drag_active:
		return
	var slot: Dictionary = _gs.get_ball_slot(index)
	_show_ball_detail(clampi(int(slot.get("type", 0)), 0, 2))


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
		var ball_type := clampi(int(slot.get("type", 0)), 0, 2)
		var card := String(slot.get("card", ""))
		var has_card := card != ""
		var tex := UI.ball_texture(ball_type)
		if tex != null:
			_lamp_icons[i].texture = tex
		var tint := Color(1.0, 0.42, 0.45) if has_card else Color(1.0, 1.0, 1.0)
		if used:
			tint = Color(0.55, 0.26, 0.30, 0.6) if has_card \
					else Color(0.34, 0.32, 0.42, 0.5)
		_lamp_icons[i].modulate = tint
		_lamp_glows[i].visible = not used and (has_card or ball_type == 2)
		if _lamp_glows[i].visible:
			if has_card:
				_lamp_glows[i].add_theme_stylebox_override("panel",
						_lamp_glow_buffed)
			elif ball_type == 2:
				_lamp_glows[i].add_theme_stylebox_override("panel",
						_lamp_glow_source)
			else:
				_lamp_glows[i].add_theme_stylebox_override("panel",
						_lamp_glow_normal)
		_lamp_borders[i].visible = ball_type >= 1
		_lamp_borders[i].modulate = Color(1.0, 1.0, 1.0,
				1.0 if not used else 0.35)
		_lamp_dots[i].visible = ball_type >= 1
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
	var full := _card_display_name(card_id)
	return full.trim_suffix("卡")


## 读 FateConfig.ITEMS 的名字（v1.4 起 GameState 不再提供 get_card_name）。
func _card_display_name(card_id: String) -> String:
	if FateConfig.ITEMS.has(card_id):
		return String(FateConfig.ITEMS[card_id].get("name", card_id))
	return card_id


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
	var owned_passive := kind == "passive" and _gs != null \
			and _gs.run_items.has(id)
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
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(30.0, 30.0)
	icon_box.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	icon_box.gui_input.connect(_on_offer_icon_input.bind(id))
	icon_box.add_child(UI.item_icon(id, 30.0))
	top.add_child(icon_box)
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
	price_row.add_child(UI.label("命核碎片", 10, FateConfig.COLOR_TEXT_DIM))
	box.add_child(price_row)

	var buy_btn := UI.button("购买", 15, 48.0)
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
	buy_btn.pressed.connect(_on_buy_offer.bind(id))
	box.add_child(buy_btn)
	return card


func _on_offer_icon_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_show_item_detail(id)


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
	# v1.6：相同道具不堆叠，逐个图标显示
	for id in pending:
		row.add_child(_make_pending_icon(id))
	return row


func _make_pending_icon(id: String) -> Control:
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

	_attach_drag_source(holder, "pending", id)
	return holder


func _on_buy_offer(id: String) -> void:
	if _gs == null:
		return
	if _gs.is_item_bought(id):
		flash_error("本轮已经购买过这件道具了")
		_item_sig = ""
		_update_item_area()
		return
	if not _gs.can_buy_item(id):
		var info: Dictionary = FateConfig.ITEMS.get(id, {})
		if String(info.get("kind", "")) == "passive" \
				and _gs.run_items.has(id):
			flash_error("这件遗物已经生效了")
		else:
			flash_error("命核碎片不足")
		_item_sig = ""
		_update_item_area()
		return
	if _gs.buy_item(id):
		UI.play_sfx("success")
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
	header.add_child(UI.label("拖珠子到弹珠灯替换 · 每关可合成一次", 11,
			FateConfig.COLOR_TEXT_DIM))
	var exit_btn := UI.button("返回标题", 12, 36.0)
	exit_btn.custom_minimum_size = Vector2(96.0, 36.0)
	exit_btn.pressed.connect(_on_exit_pressed)
	header.add_child(exit_btn)
	root.add_child(header)

	var body := UI.hbox(14)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(body)

	_lib_holders.clear()
	_lib_counts.clear()
	var names := ["命运", "命核", "命源"]
	var kinds := ["library_normal", "library_advanced", "library_high"]
	for i in 3:
		var box := UI.vbox(2)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		var holder := _make_library_holder(i, kinds[i])
		_lib_holders.append(holder)
		box.add_child(holder)
		var count_label := UI.label("%s × 0" % names[i], 13,
				FateConfig.COLOR_TEXT if i == 0 else FateConfig.COLOR_GOLD)
		_lib_counts.append(count_label)
		box.add_child(count_label)
		body.add_child(box)

	# 合成操作
	var action := UI.vbox(4)
	action.alignment = BoxContainer.ALIGNMENT_CENTER
	_lib_synth_core_btn = UI.button("合成命核 3命运·60%", 13, 44.0)
	_lib_synth_core_btn.custom_minimum_size = Vector2(226.0, 44.0)
	_lib_synth_core_btn.pressed.connect(_on_synth_pressed.bind("core"))
	action.add_child(_lib_synth_core_btn)
	_lib_synth_source_btn = UI.button("合成命源 3命核·40%", 13, 44.0)
	_lib_synth_source_btn.custom_minimum_size = Vector2(226.0, 44.0)
	_lib_synth_source_btn.pressed.connect(_on_synth_pressed.bind("source"))
	action.add_child(_lib_synth_source_btn)
	_lib_synth_hint = UI.label("", 10, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	action.add_child(_lib_synth_hint)
	body.add_child(action)


func _make_library_holder(ball_type: int, drag_kind: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(64.0, 64.0)
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var bg := Panel.new()
	bg.size = Vector2(64.0, 64.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.17, 0.12, 0.27, 0.95), FateConfig.COLOR_PANEL_EDGE, 0, 1, false))
	holder.add_child(bg)

	var tex := TextureRect.new()
	tex.texture = UI.ball_texture(ball_type)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.position = Vector2(5.0, 5.0)
	tex.size = Vector2(54.0, 54.0)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tex)

	_attach_drag_source(holder, drag_kind, "")
	return holder


func _update_library() -> void:
	if _gs == null or _lib_counts.is_empty():
		return
	var counts := [_gs.library_normal, _gs.library_advanced, _gs.library_high]
	for i in _lib_holders.size():
		var count := int(counts[i])
		_lib_counts[i].text = ["命运 × %d", "命核 × %d", "命源 × %d"][i] % count
		_lib_holders[i].modulate = Color(1.0, 1.0, 1.0) if count > 0 \
				else Color(0.55, 0.53, 0.62, 0.6)
	var used := bool(_gs.synth_used)
	if _lib_synth_core_btn != null:
		_lib_synth_core_btn.disabled = used or int(counts[0]) < 3
	if _lib_synth_source_btn != null:
		_lib_synth_source_btn.disabled = used or int(counts[1]) < 3
	if _lib_synth_hint != null:
		_lib_synth_hint.text = "本关已合成过（每关一次）" if used \
				else "失败返还：3 命运珠 / 2 命核珠"


func _on_synth_pressed(kind: String) -> void:
	if _gs == null:
		return
	var result: Dictionary
	if kind == "core":
		result = _gs.synthesize_core()
	else:
		result = _gs.synthesize_source()
	if bool(result.get("ok", false)):
		var gained := "命核琉璃珠" if kind == "core" else "命源琉璃珠"
		UI.play_sfx("success")
		_toast("合成成功！获得 1 颗" + gained, FateConfig.COLOR_JADE)
	else:
		UI.play_sfx("synth_fail")
		var reason := String(result.get("reason", ""))
		if reason != "":
			_toast(reason, FateConfig.COLOR_CRIMSON)
		else:
			var refund := "3 颗命运琉璃珠" if kind == "core" else "2 颗命核琉璃珠"
			_toast("合成失败，返还 " + refund, FateConfig.COLOR_CRIMSON)
	refresh()


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
	_ensure_detail_popup()


func _ensure_detail_popup() -> Control:
	if _detail_popup == null or not is_instance_valid(_detail_popup):
		_detail_popup = DetailPopup.new()
		add_child(_detail_popup)
	return _detail_popup


func _on_detail_dim_input(_event: InputEvent) -> void:
	pass


func _show_item_detail(item_id: String) -> void:
	if not FateConfig.ITEMS.has(item_id):
		return
	_ensure_detail_popup().call("open_item", item_id)


func _show_ball_detail(ball_type: int) -> void:
	_ensure_detail_popup().call("open_ball", ball_type)


func _hide_item_detail() -> void:
	if _detail_popup != null and is_instance_valid(_detail_popup):
		_detail_popup.visible = false


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
	var have := true
	match _press_kind:
		"library_normal":
			have = _gs != null and _gs.library_normal > 0
		"library_advanced":
			have = _gs != null and _gs.library_advanced > 0
		"library_high":
			have = _gs != null and _gs.library_high > 0
	if not have:
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
	_update_ghost()


func _drag_texture() -> Texture2D:
	match _press_kind:
		"library_normal":
			return UI.ball_texture(FateConfig.BALL_TYPE_FATE)
		"library_advanced":
			return UI.ball_texture(FateConfig.BALL_TYPE_CORE)
		"library_high":
			return UI.ball_texture(FateConfig.BALL_TYPE_SOURCE)
		_:
			var tex := UI.icon_texture(_press_item)
			if tex != null:
				return tex
			return UI.ball_texture(FateConfig.BALL_TYPE_FATE)


func _update_ghost() -> void:
	if _ghost == null:
		return
	var local := _viewport_to_local(_pointer_view)
	_ghost.position = local - Vector2(GHOST_SIZE, GHOST_SIZE) * 0.5


func _finish_tap() -> void:
	var kind := _press_kind
	var item_id := _press_item
	_clear_press()
	match kind:
		"pending":
			if item_id != "":
				_show_item_detail(item_id)
		"library_normal":
			_show_ball_detail(FateConfig.BALL_TYPE_FATE)
		"library_advanced":
			_show_ball_detail(FateConfig.BALL_TYPE_CORE)
		"library_high":
			_show_ball_detail(FateConfig.BALL_TYPE_SOURCE)


func _finish_drag(viewport_pos: Vector2) -> void:
	var kind := _press_kind
	var item_id := _press_item
	var success := false
	match kind:
		"pending":
			success = _use_pending_item(item_id, viewport_pos)
		"library_normal":
			success = _use_library_ball(FateConfig.BALL_TYPE_FATE, viewport_pos)
		"library_advanced":
			success = _use_library_ball(FateConfig.BALL_TYPE_CORE, viewport_pos)
		"library_high":
			success = _use_library_ball(FateConfig.BALL_TYPE_SOURCE, viewport_pos)
		_:
			pass
	if success:
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


func _use_library_ball(ball_type: int, viewport_pos: Vector2) -> bool:
	if _gs == null:
		return false
	var index := _lamp_at(viewport_pos)
	if index < 0:
		flash_error("请把弹珠拖到上方的弹珠灯上")
		return false
	if _is_lamp_used(index):
		flash_error("这颗弹珠已经发射过了")
		return false
	match ball_type:
		FateConfig.BALL_TYPE_CORE:
			if _gs.library_advanced <= 0:
				flash_error("弹珠库里没有命核琉璃珠")
				return false
		FateConfig.BALL_TYPE_SOURCE:
			if _gs.library_high <= 0:
				flash_error("弹珠库里没有命源琉璃珠")
				return false
		_:
			if _gs.library_normal <= 0:
				flash_error("弹珠库里没有命运琉璃珠")
				return false
	if _gs.get_ball_card(index) != "":
		flash_error("这颗弹珠已绑定卡牌，无法替换")
		return false
	if _gs.replace_ball_slot_type(index, ball_type):
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


func _on_library_changed(_normal_count: int, _advanced_count: int,
		_high_count: int) -> void:
	refresh()


func _on_items_changed() -> void:
	refresh()

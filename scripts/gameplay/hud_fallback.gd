extends Control
## HUD 兜底版本 v1.1：仅当 res://scenes/ui/hud.tscn 缺失或接口不匹配时使用。
## 按 CONTRACT_V2 第 5 节实现 P1 简化布局：
##   ① 目标分/当前分  ② 金币  ③ 弹珠灯  ⑥ ❌ 关闭  ⑦ 商店/待用道具  ⑧ 弹珠库
## 接口与真实 HUD 一致：
##   signal shop_closed / exit_pressed / equip_requested(item_id, screen_pos)
##   set_game(game) / refresh() / set_phase(phase) / open_shop(level, offers)
##   set_phase_hint / show_fate_event / popup_score / flash_error

signal shop_closed
signal exit_pressed
signal equip_requested(item_id: String, screen_pos: Vector2)

var _game = null
var _phase: int = 1
var _offers: Array[String] = []
var _needs_rebuild := false

var _score_label: Label = null
var _coin_label: Label = null
var _lamp_box: Control = null
var _hint_label: Label = null
var _fate_label: Label = null
var _error_label: Label = null
var _library_label: Label = null
var _merge_btn: Button = null
var _shop_panel: Control = null
var _shop_box: VBoxContainer = null
var _pending_box: HBoxContainer = null
var _close_btn: Button = null
var _fate_tween: Tween = null
var _error_tween: Tween = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _build_theme()
	_build_static_ui()
	refresh()

func _process(_delta: float) -> void:
	if _needs_rebuild:
		_needs_rebuild = false
		_rebuild_dynamic()
	_update_top_labels()

# ---------------- 主题 / 字体 ----------------

func _build_theme() -> Theme:
	var result := Theme.new()
	var font := _load_font()
	if font != null:
		result.default_font = font
	result.default_font_size = 20
	return result

func _load_font() -> Font:
	var candidates: Array = ["res://assets/fonts/FateBody.ttf", "res://assets/fonts/FateTitle.ttf"]
	for p in candidates:
		var path := String(p)
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Font:
				return res
	return ThemeDB.fallback_font

# ---------------- 静态 UI ----------------

func _build_static_ui() -> void:
	# 顶部三个信息格背景
	for rect in [FateConfig.HUD_CELL_SCORE, FateConfig.HUD_CELL_COIN, FateConfig.HUD_CELL_BALL]:
		var panel := ColorRect.new()
		panel.position = rect.position
		panel.size = rect.size
		panel.color = Color(0.08, 0.05, 0.14, 0.72)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
	_score_label = _make_label(FateConfig.HUD_CELL_SCORE.position + Vector2(16, 14), FateConfig.HUD_CELL_SCORE.size - Vector2(32, 24), 22, FateConfig.COLOR_TEXT)
	_coin_label = _make_label(FateConfig.HUD_CELL_COIN.position + Vector2(16, 28), FateConfig.HUD_CELL_COIN.size - Vector2(32, 40), 22, FateConfig.COLOR_GOLD)
	_lamp_box = Control.new()
	_lamp_box.position = FateConfig.HUD_CELL_BALL.position
	_lamp_box.size = FateConfig.HUD_CELL_BALL.size
	_lamp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lamp_box)
	# ⑦ 道具 / 商店区
	_shop_panel = ColorRect.new()
	_shop_panel.position = FateConfig.ITEM_AREA.position
	_shop_panel.size = FateConfig.ITEM_AREA.size
	_shop_panel.color = Color(0.09, 0.06, 0.16, 0.82)
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shop_panel)
	var shop_title := _make_label(FateConfig.ITEM_AREA.position + Vector2(14, 6), Vector2(400, 30), 20, FateConfig.COLOR_GOLD)
	shop_title.text = "命运商店 · 拖拽使用道具"
	shop_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_box = VBoxContainer.new()
	_shop_box.position = FateConfig.ITEM_AREA.position + Vector2(14, 42)
	_shop_box.size = FateConfig.ITEM_AREA.size - Vector2(28, 56)
	_shop_box.add_theme_constant_override("separation", 8)
	_shop_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shop_box)
	_pending_box = HBoxContainer.new()
	_pending_box.position = FateConfig.ITEM_AREA.position + Vector2(14, 292)
	_pending_box.size = Vector2(FateConfig.ITEM_AREA.size.x - 28, 44)
	_pending_box.add_theme_constant_override("separation", 8)
	_pending_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pending_box)
	# ⑧ 弹珠库
	var lib_panel := ColorRect.new()
	lib_panel.position = FateConfig.LIBRARY_AREA.position
	lib_panel.size = FateConfig.LIBRARY_AREA.size
	lib_panel.color = Color(0.09, 0.06, 0.16, 0.82)
	lib_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(lib_panel)
	_library_label = _make_label(FateConfig.LIBRARY_AREA.position + Vector2(16, 26), Vector2(560, 40), 20, FateConfig.COLOR_TEXT)
	_library_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_merge_btn = Button.new()
	_merge_btn.text = "合成：3 普通 → 1 进阶"
	_merge_btn.position = FateConfig.LIBRARY_AREA.position + Vector2(16, 84)
	_merge_btn.size = Vector2(300, 52)
	_merge_btn.add_theme_font_size_override("font_size", 18)
	_merge_btn.pressed.connect(_on_merge_pressed)
	add_child(_merge_btn)
	# ⑥ ❌ 关闭道具界面
	_close_btn = Button.new()
	_close_btn.text = "❌"
	_close_btn.position = FateConfig.CLOSE_RECT.position
	_close_btn.size = FateConfig.CLOSE_RECT.size
	_close_btn.add_theme_font_size_override("font_size", 26)
	_close_btn.pressed.connect(_on_close_pressed)
	add_child(_close_btn)
	# 返回标题（兜底 HUD 额外提供，真实 HUD 用自身按钮）
	var exit_btn := Button.new()
	exit_btn.text = "返回"
	exit_btn.position = Vector2(1208, 8)
	exit_btn.size = Vector2(64, 40)
	exit_btn.add_theme_font_size_override("font_size", 16)
	exit_btn.pressed.connect(_on_exit_pressed)
	add_child(exit_btn)
	# 提示 / 命运事件 / 错误
	_hint_label = _make_label(Vector2(280, 676), Vector2(720, 36), 20, FateConfig.COLOR_TEXT_DIM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fate_label = _make_label(Vector2(280, 112), Vector2(720, 40), 22, FateConfig.COLOR_VIOLET)
	_fate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fate_label.modulate.a = 0.0
	_error_label = _make_label(Vector2(280, 158), Vector2(720, 40), 22, FateConfig.COLOR_CRIMSON)
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.modulate.a = 0.0

func _make_label(pos: Vector2, box_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = box_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

# ---------------- 对外接口（与真实 HUD 一致） ----------------

func set_game(game: Node) -> void:
	_game = game

func set_phase(phase: int) -> void:
	_phase = phase
	var shop_visible := phase == 0
	_shop_panel.visible = shop_visible
	_shop_box.visible = shop_visible
	_pending_box.visible = true
	_close_btn.visible = shop_visible
	_merge_btn.visible = phase != 2
	_library_label.visible = phase != 2
	if phase == 2:
		_hint_label.text = ""

func open_shop(level: int, offers: Array) -> void:
	_offers.clear()
	for item in offers:
		_offers.append(String(item))
	_needs_rebuild = true

func refresh() -> void:
	_needs_rebuild = true

func set_phase_hint(text: String) -> void:
	_hint_label.text = text

func show_fate_event(event: Dictionary) -> void:
	if _fate_tween != null and _fate_tween.is_valid():
		_fate_tween.kill()
	if event.is_empty():
		_fate_label.modulate.a = 0.0
		return
	_fate_label.text = "命运事件 · %s：%s" % [String(event.get("name", "")), String(event.get("desc", ""))]
	_fate_label.modulate.a = 1.0
	_fate_tween = create_tween()
	_fate_tween.tween_interval(2.8)
	_fate_tween.tween_property(_fate_label, "modulate:a", 0.0, 0.6)

func popup_score(value: int, world_pos: Vector2) -> void:
	var text := ("+%d" % value) if value > 0 else "0"
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = world_pos - Vector2(90.0, 24.0)
	label.size = Vector2(180.0, 42.0)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(0.0, -60.0), 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.35)
	tween.finished.connect(label.queue_free)

func flash_error(text: String) -> void:
	if _error_tween != null and _error_tween.is_valid():
		_error_tween.kill()
	_error_label.text = text
	_error_label.modulate.a = 1.0
	_error_tween = create_tween()
	_error_tween.tween_interval(1.2)
	_error_tween.tween_property(_error_label, "modulate:a", 0.0, 0.5)

# ---------------- 动态内容 ----------------

func _update_top_labels() -> void:
	_score_label.text = "第%d间「%s」\n目标 %d ｜ 当前 %d" % [
		GameState.level, GameState.get_level_name(), GameState.get_target(), GameState.level_score]
	_coin_label.text = "金币 %d\n碎片 %d ｜ 最高分 %d" % [GameState.coins, GameState.total_shards, GameState.best_score]

func _rebuild_dynamic() -> void:
	_rebuild_lamps()
	_rebuild_shop()
	_rebuild_pending()
	_library_label.text = "弹珠库：普通 %d ｜ 进阶 %d\n长按拖到弹珠灯可替换" % [GameState.library_normal, GameState.library_advanced]
	_merge_btn.disabled = GameState.library_normal < 3
	_update_top_labels()

func _rebuild_lamps() -> void:
	for child in _lamp_box.get_children():
		_lamp_box.remove_child(child)
		child.queue_free()
	var total := GameState.balls_total
	var used := total - GameState.balls_left
	for i in total:
		var slot := GameState.get_ball_slot(i)
		var card := GameState.get_ball_card(i)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 30)
		label.position = Vector2(14 + i * 46, 26)
		label.size = Vector2(44, 44)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < used:
			label.text = "○"
			label.add_theme_color_override("font_color", Color(0.35, 0.32, 0.42))
		elif card != "":
			label.text = "★"
			label.add_theme_color_override("font_color", FateConfig.COLOR_CRIMSON)
		elif int(slot.get("type", 0)) == 1:
			label.text = "◆"
			label.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
		else:
			label.text = "●"
			label.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
		_lamp_box.add_child(label)

func _rebuild_shop() -> void:
	for child in _shop_box.get_children():
		_shop_box.remove_child(child)
		child.queue_free()
	for item_id in _offers:
		_shop_box.add_child(_make_shop_row(item_id))

func _make_shop_row(item_id: String) -> Control:
	var data: Dictionary = FateConfig.ITEMS.get(item_id, {})
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(FateConfig.ITEM_AREA.size.x - 28.0, 64.0)
	row.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = String(data.get("name", item_id))
	name_label.custom_minimum_size = Vector2(110, 0)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	row.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = String(data.get("desc", ""))
	desc_label.custom_minimum_size = Vector2(370, 0)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 15)
	desc_label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT_DIM)
	row.add_child(desc_label)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(96, 48)
	buy.add_theme_font_size_override("font_size", 17)
	buy.text = "购买 %d" % int(data.get("cost", 0))
	buy.disabled = not GameState.can_buy_item(item_id)
	buy.pressed.connect(_on_buy_pressed.bind(item_id))
	row.add_child(buy)
	return row

func _rebuild_pending() -> void:
	for child in _pending_box.get_children():
		_pending_box.remove_child(child)
		child.queue_free()
	var counts := {}
	for item_id in GameState.get_pending_items():
		counts[item_id] = int(counts.get(item_id, 0)) + 1
	for item_id in counts.keys():
		var data: Dictionary = FateConfig.ITEMS.get(item_id, {})
		var button := Button.new()
		button.text = "%s ×%d" % [String(data.get("name", item_id)), int(counts[item_id])]
		button.custom_minimum_size = Vector2(130, 44)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_on_pending_pressed.bind(String(item_id)))
		_pending_box.add_child(button)

# ---------------- 内部按钮回调 ----------------

func _on_buy_pressed(item_id: String) -> void:
	if GameState.buy_item(item_id):
		Audio.play_sfx("buy")
		refresh()
	else:
		flash_error("金币不足，命运拒绝了你")

func _on_pending_pressed(item_id: String) -> void:
	var info: Dictionary = FateConfig.ITEMS.get(item_id, {})
	var kind := String(info.get("kind", "equipment"))
	if kind == "equipment":
		# 兜底 HUD 没有拖拽：把装备送到台面中央，由 game._on_equip_requested 找最近立柱
		equip_requested.emit(item_id, Vector2(900.0, 320.0))
	elif kind == "card":
		var total := GameState.balls_total
		var used := total - GameState.balls_left
		var applied := false
		for i in range(used, total):
			if GameState.get_ball_card(i) != "":
				continue
			if GameState.set_ball_card(i, item_id):
				applied = true
				break
		if applied:
			GameState.consume_pending_item(item_id)
			Audio.play_sfx("buy")
			refresh()
		else:
			flash_error("没有可绑定卡牌的弹珠了")
	else:
		GameState.consume_pending_item(item_id)
		refresh()

func _on_merge_pressed() -> void:
	if GameState.merge_library_balls():
		Audio.play_sfx("buy")
		refresh()
	else:
		flash_error("普通弹珠不足 3 颗")

func _on_close_pressed() -> void:
	Audio.play_sfx("click")
	shop_closed.emit()

func _on_exit_pressed() -> void:
	Audio.play_sfx("click")
	exit_pressed.emit()

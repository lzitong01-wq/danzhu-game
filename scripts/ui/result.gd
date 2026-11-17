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
signal checkpoint_pressed

const UI := preload("res://scripts/ui/ui_theme.gd")

const PANEL_SIZE := Vector2(820.0, 660.0)

var _gs := UI.game_state()
var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _level_label: Label = null
var _story_label: Label = null
var _score_value: Label = null
var _shards_value: Label = null
var _best_value: Label = null
var _carried_box: HBoxContainer = null
var _badge: Label = null
var _badge_tween: Tween = null
var _retry_btn: Button = null
var _menu_btn: Button = null
var _stat_headings: Array[Label] = []
var _fail_level: int = 1
var _is_victory := false
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

	# 失败固定文案（策划案 11 条）
	_story_label = UI.label("", 14, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	_story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_label.custom_minimum_size = Vector2(680.0, 0.0)
	_story_label.visible = false
	root_box.add_child(_story_label)

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
	menu_btn.custom_minimum_size = Vector2(260.0, 76.0)
	menu_btn.pressed.connect(_on_menu_pressed)
	buttons.add_child(menu_btn)
	_menu_btn = menu_btn
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
	var heading_label := UI.label(heading, 17, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(heading_label)
	_stat_headings.append(heading_label)
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
	# v1.8：未拥有命源珠（隐藏关未解锁）时，不显示 /10、第10间、「十间」「命源再现」等
	var source_unlocked := level >= FateConfig.MAX_LEVEL \
			or (_gs != null and _gs.has_source_ball())

	_panel.add_theme_stylebox_override("panel", _make_panel_style(victory))
	if victory:
		_title.text = "命 源 再 现" if source_unlocked else "命 运 改 写"
	else:
		_title.text = "失 败"
	_title.add_theme_color_override("font_color",
			FateConfig.COLOR_GOLD if victory else FateConfig.COLOR_CRIMSON)
	_title.add_theme_color_override("font_outline_color",
			Color(0.91, 0.76, 0.42, 0.30) if victory
			else Color(1.0, 0.36, 0.42, 0.30))

	if victory:
		if source_unlocked:
			_subtitle.text = "十间命运房间已贯通，命源在你掌中重燃。"
			_level_label.text = "第 %d / %d 间 · 命源再现 · 命运改写" % [
					FateConfig.MAX_LEVEL, FateConfig.MAX_LEVEL]
		else:
			_subtitle.text = "命运回廊已暂告一段落，命源的去向仍藏在雾里。"
			_level_label.text = "%s · 命运改写" % _progress_text(level)
		_story_label.visible = false
		_story_label.text = ""
	else:
		_subtitle.text = "命运琉璃碎裂，但碎片已被你握在手中。"
		_level_label.text = "止步于 %s · %s" % [_progress_text(level),
				FateConfig.LEVEL_NAMES[clampi(level, 1, FateConfig.MAX_LEVEL) - 1]]
		var story := String(summary.get("story", ""))
		if story == "":
			story = FateConfig.FAILURE_STORY_LINE
		_story_label.text = "「" + story + "」"
		_story_label.visible = true

	_fail_level = level
	_is_victory = victory
	if victory:
		if _stat_headings.size() >= 3:
			_stat_headings[0].text = "本局总分"
			_stat_headings[1].text = "获得命运碎片"
			_stat_headings[2].text = "历史最高分"
		if _retry_btn != null:
			_retry_btn.text = "再来一局"
		if _menu_btn != null:
			_menu_btn.text = "返回标题"
			_menu_btn.disabled = false
			_menu_btn.modulate = Color(1.0, 1.0, 1.0)
		_score_value.text = str(total_score)
		_shards_value.text = "+%d" % shards
		_shards_value.add_theme_color_override("font_color",
				FateConfig.COLOR_VIOLET)
		_best_value.text = str(best)
		_best_value.add_theme_color_override("font_color",
				FateConfig.COLOR_GOLD)
		_carried_box.visible = true
		_update_carried(summary)
	else:
		var level_score := int(summary.get("level_score", total_score))
		if _stat_headings.size() >= 3:
			_stat_headings[0].text = "关卡得分"
			_stat_headings[1].text = "本局总分"
			_stat_headings[2].text = "获得命运碎片"
		if _retry_btn != null:
			_retry_btn.text = "重试本关"
		if _menu_btn != null:
			_menu_btn.text = "返回上一存档点"
			var can_return := level > 2
			_menu_btn.disabled = not can_return
			_menu_btn.modulate = Color(1.0, 1.0, 1.0) if can_return \
					else Color(0.55, 0.53, 0.62, 0.75)
		_score_value.text = str(level_score)
		_shards_value.text = str(total_score)
		_shards_value.add_theme_color_override("font_color",
				FateConfig.COLOR_GOLD)
		_best_value.text = "+%d" % shards
		_best_value.add_theme_color_override("font_color",
				FateConfig.COLOR_VIOLET)
		_carried_box.visible = false
		_clear_carried()

	_badge.visible = is_new_best and victory
	if is_new_best and victory:
		_start_badge_pulse()
	elif _badge_tween != null and _badge_tween.is_valid():
		_badge_tween.kill()

	visible = true
	_play_open_animation()


func _clear_carried() -> void:
	for child in _carried_box.get_children():
		_carried_box.remove_child(child)
		child.queue_free()


## 未拥有命源珠/未到第10间时只显示「第 X 间」，不泄露隐藏关总关数。
func _progress_text(level: int) -> String:
	if level >= FateConfig.MAX_LEVEL \
			or (_gs != null and _gs.has_source_ball()):
		return "第 %d / %d 间" % [level, FateConfig.MAX_LEVEL]
	return "第 %d 间" % level


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
	if _menu_btn != null and _menu_btn.disabled:
		return
	UI.play_sfx("click")
	# 失败时「返回上一存档点」：优先发 checkpoint_pressed（gameplay 接线）。
	# 若 gameplay 仍只连接旧 menu_pressed，则回退为 menu_pressed，避免按钮失效。
	if not _is_victory and _fail_level > 0 \
			and checkpoint_pressed.get_connections().size() > 0:
		checkpoint_pressed.emit()
	else:
		menu_pressed.emit()

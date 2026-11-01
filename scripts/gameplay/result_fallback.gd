extends Control
## 结算兜底版本：仅当 res://scenes/ui/result.tscn 缺失或加载失败时使用。
## 接口与真实结算一致：show_result(victory, summary) + retry_pressed / menu_pressed。

signal retry_pressed
signal menu_pressed

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _build_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, 0.93)
	bg.size = Vector2(1280.0, 720.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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

## summary: {"total_score","shards","is_new_best","best","level"}
func show_result(victory: bool, summary: Dictionary) -> void:
	for child in get_children():
		if child is ColorRect:
			continue
		remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "试炼完成 · 命运偏移" if victory else "本间试炼失败 · 坠入虚空"
	title.position = Vector2(140.0, 170.0)
	title.size = Vector2(1000.0, 70.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", FateConfig.COLOR_GOLD if victory else FateConfig.COLOR_CRIMSON)
	add_child(title)
	var total := int(summary.get("total_score", 0))
	var shards := int(summary.get("shards", 0))
	var best := int(summary.get("best", 0))
	var is_new_best := bool(summary.get("is_new_best", false))
	var body_text := "本局总分：%d\n命运碎片：+%d\n最高分：%d%s" % [
		total,
		shards,
		best,
		"\n※ 新纪录！" if is_new_best else "",
	]
	var body := Label.new()
	body.text = body_text
	body.position = Vector2(340.0, 280.0)
	body.size = Vector2(600.0, 200.0)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 26)
	body.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	body.add_theme_constant_override("line_spacing", 12)
	add_child(body)
	var retry := Button.new()
	retry.text = "再来一局" if victory else "重试本关"
	retry.position = Vector2(400.0, 520.0)
	retry.size = Vector2(200.0, 68.0)
	retry.add_theme_font_size_override("font_size", 26)
	retry.pressed.connect(_on_retry_pressed)
	add_child(retry)
	var menu := Button.new()
	menu.text = "返回标题"
	menu.position = Vector2(680.0, 520.0)
	menu.size = Vector2(200.0, 68.0)
	menu.add_theme_font_size_override("font_size", 26)
	menu.pressed.connect(_on_menu_pressed)
	add_child(menu)

func _on_retry_pressed() -> void:
	Audio.play_sfx("click")
	retry_pressed.emit()

func _on_menu_pressed() -> void:
	Audio.play_sfx("click")
	menu_pressed.emit()

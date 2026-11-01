extends Control
## 局外「行囊」面板的兜底版本（真实 scenes/ui/meta_panel.tscn 缺失时使用）。
## 接口：func open_panel() + signal closed

signal closed

var _built := false
var _content_box: VBoxContainer = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var theme := Theme.new()
	var font := _load_font()
	if font != null:
		theme.default_font = font
	theme.default_font_size = 20
	self.theme = theme
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, 0.86)
	bg.size = FateConfig.VIEW_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := ColorRect.new()
	panel.color = Color(0.11, 0.08, 0.19, 0.97)
	panel.position = Vector2(240.0, 70.0)
	panel.size = Vector2(800.0, 580.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var title := Label.new()
	title.text = "行囊（局外）"
	title.position = Vector2(0.0, 18.0)
	title.size = Vector2(800.0, 44.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	panel.add_child(title)
	_content_box = VBoxContainer.new()
	_content_box.position = Vector2(48.0, 86.0)
	_content_box.size = Vector2(704.0, 380.0)
	_content_box.add_theme_constant_override("separation", 10)
	panel.add_child(_content_box)
	var close_btn := Button.new()
	close_btn.text = "确认带入下一局"
	close_btn.position = Vector2(250.0, 492.0)
	close_btn.size = Vector2(300.0, 60.0)
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(_on_close_pressed)
	panel.add_child(close_btn)
	_built = true

func _load_font() -> Font:
	var candidates: Array = ["res://assets/fonts/FateBody.ttf", "res://assets/fonts/FateTitle.ttf"]
	for p in candidates:
		var path := String(p)
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Font:
				return res
	return ThemeDB.fallback_font

func open_panel() -> void:
	refresh()

func refresh() -> void:
	if not _built or _content_box == null:
		return
	for child in _content_box.get_children():
		_content_box.remove_child(child)
		child.queue_free()
	_content_box.add_child(_make_line("行囊弹珠：普通 %d ｜ 进阶 %d" % [GameState.meta_balls_normal, GameState.meta_balls_advanced]))
	var selected_balls := "已勾选带入弹珠：普通 %d ｜ 进阶 %d（上限 %d）" % [
		GameState.selected_balls_normal, GameState.selected_balls_advanced, FateConfig.META_MAX_SELECT_BALLS]
	_content_box.add_child(_make_line(selected_balls))
	_content_box.add_child(_make_line("— 卡牌 —"))
	var stacks: Array = GameState.get_meta_card_stacks()
	if stacks.is_empty():
		_content_box.add_child(_make_line("（暂无卡牌）"))
	for entry in stacks:
		var id := String(entry.get("id", ""))
		var count := int(entry.get("count", 0))
		var data: Dictionary = FateConfig.ITEMS.get(id, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = "%s ×%d" % [String(data.get("name", id)), count]
		label.custom_minimum_size = Vector2(360.0, 0.0)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
		row.add_child(label)
		var toggle := Button.new()
		toggle.text = "取消勾选" if GameState.is_card_selected(id) else "勾选"
		toggle.custom_minimum_size = Vector2(130.0, 44.0)
		toggle.add_theme_font_size_override("font_size", 17)
		toggle.pressed.connect(_on_toggle_card.bind(id))
		row.add_child(toggle)
		_content_box.add_child(row)
	_content_box.add_child(_make_line("局外勾选上限：卡牌 %d 张" % FateConfig.META_MAX_SELECT_CARDS))

func _make_line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	return label

func _on_toggle_card(card_id: String) -> void:
	if not GameState.toggle_selected_card(card_id):
		Audio.play_sfx("click")
	refresh()

func _on_close_pressed() -> void:
	Audio.play_sfx("click")
	GameState.save_game()
	closed.emit()

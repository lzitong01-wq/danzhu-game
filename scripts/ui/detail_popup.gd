extends Control
## 通用「道具 / 弹珠」详情弹窗（v1.6）。
## 用法：
##   const DetailPopup := preload("res://scripts/ui/detail_popup.gd")
##   var popup := DetailPopup.new(); add_child(popup)
##   popup.open_item("splitcard") / popup.open_ball(FateConfig.BALL_TYPE_CORE)
## 点击弹窗外的遮罩关闭；signal closed 可忽略。

signal closed

const UI := preload("res://scripts/ui/ui_theme.gd")
const PANEL_SIZE := Vector2(640.0, 540.0)

var _gs := UI.game_state()
var _built := false
var _body: VBoxContainer = null


func _ready() -> void:
	_ensure_built()
	visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_gs = UI.game_state()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)

	var dim := ColorRect.new()
	dim.color = Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(dim)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.075, 0.055, 0.12, 0.99), FateConfig.COLOR_GOLD, 0, 4))
	add_child(panel)

	_body = UI.vbox(10)
	panel.add_child(_body)


func open_item(item_id: String) -> void:
	if not FateConfig.ITEMS.has(item_id):
		return
	_ensure_built()
	_clear_body()
	var info: Dictionary = FateConfig.ITEMS[item_id]

	var top := UI.hbox(16)
	top.add_child(UI.item_icon(item_id, 76.0))
	var info_box := UI.vbox(2)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.add_child(UI.label(String(info.get("name", item_id)), 30,
			FateConfig.COLOR_GOLD))
	info_box.add_child(UI.label("%s · %s" % [String(info.get("tag", "")),
			_kind_label(String(info.get("kind", "equipment")))], 14,
			FateConfig.COLOR_VIOLET))
	top.add_child(info_box)
	_body.add_child(top)
	_body.add_child(_divider())

	var desc := UI.label(String(info.get("desc", "")), 17,
			FateConfig.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0.0, 58.0)
	_body.add_child(desc)

	var price_row := UI.hbox(8)
	price_row.add_child(UI.icon("coin", 24.0))
	price_row.add_child(UI.label("价格 %d 命核碎片" % int(info.get("cost", 0)),
			17, FateConfig.COLOR_GOLD))
	_body.add_child(price_row)

	var lore := String(FateConfig.ITEM_LORES.get(item_id, ""))
	if lore != "":
		var lore_label := UI.label("「" + lore + "」", 13,
				FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore_label.custom_minimum_size = Vector2(0.0, 64.0)
		_body.add_child(lore_label)

	_body.add_child(_hint())
	_open()


func open_ball(ball_type: int) -> void:
	var t := clampi(ball_type, 0, 2)
	_ensure_built()
	_clear_body()

	var top := UI.hbox(16)
	top.add_child(UI.ball_icon_type(t, 76.0))
	var info_box := UI.vbox(2)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	info_box.add_child(UI.label(FateConfig.BALL_NAMES[t], 30,
			FateConfig.COLOR_GOLD))
	info_box.add_child(UI.label(["命运 · 基础型", "命核 · 凝聚型", "命源 · 原初型"][t],
			14, FateConfig.COLOR_VIOLET))
	top.add_child(info_box)
	_body.add_child(top)
	_body.add_child(_divider())

	var score_row := UI.hbox(8)
	score_row.add_child(UI.label("基础得分", 16, FateConfig.COLOR_TEXT_DIM))
	score_row.add_child(UI.label("%s 分" % FateConfig.BALL_BASE_DESC[t], 20,
			FateConfig.COLOR_GOLD))
	_body.add_child(score_row)

	var way_row := UI.vbox(2)
	way_row.add_child(UI.label("获取方式", 16, FateConfig.COLOR_TEXT_DIM))
	var way := UI.label(FateConfig.BALL_GET_WAYS[t], 15,
			FateConfig.COLOR_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	way.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	way_row.add_child(way)
	_body.add_child(way_row)

	var lore := UI.label("「" + FateConfig.BALL_LORES[t] + "」", 13,
			FateConfig.COLOR_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.custom_minimum_size = Vector2(0.0, 78.0)
	_body.add_child(lore)

	_body.add_child(_hint())
	_open()


func _kind_label(kind: String) -> String:
	match kind:
		"equipment":
			return "拖到立柱使用"
		"card":
			return "拖到弹珠使用"
		"passive":
			return "购买即生效"
		"instant":
			return "购买即生效"
		_:
			return kind


func _divider() -> Control:
	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.30)
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _hint() -> Label:
	return UI.label("点击空白处关闭", 11, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)


func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _open() -> void:
	visible = true
	modulate.a = 0.0
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)


func close_popup() -> void:
	visible = false
	closed.emit()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			close_popup()

extends Control
## 《！？珠珠？！》v1.4 新手教程大厅（需求 6：循序渐进教 P1 各区域名词）。
##
## 版式：
##   左侧：P1 布局示意图（用 FateConfig 的 HUD_CELL_SCORE/COIN/BALL、ITEM_AREA、
##         LIBRARY_AREA、PEG_AREA、SLOT_RECT、CLOSE_RECT、RAIL/LAUNCH_POS/GATE_RECT
##         按 0.66 倍绘制；当前页对应区域高亮，其余变暗）
##   右侧：区域名词 + 一句说明 + 本页要点（立柱/琉璃珠图例等）
##   底部：上一页 / 页码 / 下一页 / 跳过教程；最后一页「进入试炼」
##
## 入口：主菜单「新手教程」；「进入试炼」→ GameState.start_new_run() + corridor。
## 只读使用 FateConfig / GameState / FateUI；不改动任何存档字段。

const UI := preload("res://scripts/ui/ui_theme.gd")

const CORRIDOR_PATH := "res://scenes/corridor.tscn"
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"

const BOARD_SCALE := 0.66
const BOARD_POS := Vector2(20.0, 104.0)
const BOARD_SIZE := Vector2(844.8, 475.2)

var _gs := UI.game_state()

var _pages: Array = []
var _page := 0

var _board: HallBoard = null
var _board_note: Label = null
var _page_title: Label = null
var _page_desc: Label = null
var _legend_box: VBoxContainer = null
var _page_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _skip_btn: Button = null
var _start_btn: Button = null
var _dots: Array[Panel] = []
var _transitioning := false


func _ready() -> void:
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)
	_gs = UI.game_state()

	_pages = _build_pages()

	_build_background()
	_build_top_bar()
	_build_board()
	_build_side_panel()
	_build_bottom_bar()

	_set_page(0, false)
	UI.play_bgm("menu")


# ==================================================================
# 页面数据（循序渐进 10 页）
# ==================================================================

func _build_pages() -> Array:
	var rail_rect := Rect2(FateConfig.RAIL_LEFT, FateConfig.RAIL_TOP,
			FateConfig.RAIL_RIGHT - FateConfig.RAIL_LEFT,
			FateConfig.RAIL_BOTTOM - FateConfig.RAIL_TOP)
	var pages: Array = [
		{
			"mode": "board",
			"title": "① 目标分",
			"desc": "每间房都有一个目标分（第 1 间 30 分，第 10 间 130 分）。在弹珠灯耗尽前把当前得分推到目标分，就能通过这一间。",
			"focus": [FateConfig.HUD_CELL_SCORE, FateConfig.SLOT_RECT],
			"legend": [
				{"color": FateConfig.COLOR_GOLD, "name": "当前得分 / 目标分",
					"desc": "显示在左上 ①"},
				{"color": FateConfig.COLOR_JADE, "name": "底部槽位",
					"desc": "×3 / ×1.5 / ×1 / 裂隙 / ×1 / ×1.5 决定本球得分倍率"},
			],
		},
		{
			"mode": "board",
			"title": "② 命核碎片",
			"desc": "命核碎片是命运回廊里的货币：撞白色立柱、踩中带加成的槽位都能获得；在 ⑦ 道具区购物、刷新货架都要花它。",
			"focus": [FateConfig.HUD_CELL_COIN],
			"legend": [
				{"color": FateConfig.COLOR_GOLD, "name": "命核碎片",
					"desc": "顶部 ② 显示当前持有量"},
				{"color": FateConfig.COLOR_WHITE_PEG, "name": "白色立柱",
					"desc": "命中后 20% 概率掉落命核碎片"},
			],
		},
		{
			"mode": "board",
			"title": "③ 弹珠灯",
			"desc": "顶部右侧的弹珠灯就是本关还能发射的弹珠数：常规 5 盏，被增益卡强化后变红，进阶与命源琉璃珠会带金框。",
			"focus": [FateConfig.HUD_CELL_BALL],
			"legend": [
				{"color": FateConfig.COLOR_VIOLET, "name": "弹珠灯",
					"desc": "灯灭 = 本关弹珠用完"},
				{"color": FateConfig.COLOR_CRIMSON, "name": "红色弹珠灯",
					"desc": "已附加强化卡，弹珠更强"},
			],
		},
		{
			"mode": "board",
			"title": "④ 弹簧发射",
			"desc": "按住右下弹簧蓄力（约 1 秒满力），松手沿轨道向上发射；按住时拖动可以改变出射角度与轨迹。",
			"focus": [rail_rect],
			"legend": [
				{"color": FateConfig.COLOR_JADE, "name": "蓄力",
					"desc": "按得越久，发射力度越大"},
				{"color": FateConfig.COLOR_GOLD, "name": "轨迹",
					"desc": "轨道一次只容一球通过"},
			],
		},
		{
			"mode": "board",
			"title": "⑤ 立柱阵",
			"desc": "台面上是 6×7 的立柱阵：弹珠撞到立柱就得分，五种立柱效果各不相同。",
			"focus": [FateConfig.PEG_AREA],
			"legend": [
				{"texture": "res://assets/art/peg_normal.png",
					"color": Color(0.72, 0.69, 0.82), "name": "普通立柱",
					"desc": "撞到获得基础分"},
				{"texture": "res://assets/art/peg_yellow.png",
					"color": FateConfig.COLOR_GOLD, "name": "黄色立柱",
					"desc": "连击加成：每次额外加分"},
				{"texture": "res://assets/art/peg_green.png",
					"color": FateConfig.COLOR_JADE, "name": "绿色立柱",
					"desc": "与相邻绿柱连成横/竖线，线会再次弹开弹珠"},
				{"texture": "res://assets/art/peg_black.png",
					"color": Color(0.82, 0.79, 0.92), "name": "黑色立柱",
					"desc": "撞到扣除命核碎片"},
				{"texture": "res://assets/art/peg_white.png",
					"color": FateConfig.COLOR_WHITE_PEG, "name": "白色立柱",
					"desc": "概率掉落命核碎片（关卡加成可提高）"},
			],
		},
		{
			"mode": "board",
			"title": "⑥ 运动改变区",
			"desc": "轨道顶端的缺口：弹珠射入台面后闸门会关闭，球不会逃回轨道；下一球发射时再打开。",
			"focus": [FateConfig.GATE_RECT],
			"legend": [
				{"color": FateConfig.COLOR_CRIMSON, "name": "闸门关闭",
					"desc": "台面内的球只能在台面反弹"},
				{"color": FateConfig.COLOR_JADE, "name": "闸门打开",
					"desc": "发射瞬间放行，球进入台面"},
			],
		},
		{
			"mode": "board",
			"title": "⑦ 道具区",
			"desc": "商店买到的装备与增益卡都在这里。长按道具，拖到 ⑤ 立柱（装备）或 ③ 弹珠灯（增益卡）上，松手生效。",
			"focus": [FateConfig.ITEM_AREA, FateConfig.HUD_CELL_BALL,
					FateConfig.PEG_AREA],
			"legend": [
				{"ordinal": "1", "color": FateConfig.COLOR_GOLD, "name": "长按道具",
					"desc": FateConfig.TUTORIAL_TEXT_1},
				{"ordinal": "2", "color": FateConfig.COLOR_JADE, "name": "拖到目标",
					"desc": FateConfig.TUTORIAL_TEXT_2},
				{"ordinal": "3", "color": FateConfig.COLOR_VIOLET, "name": "松手生效",
					"desc": FateConfig.TUTORIAL_TEXT_3},
			],
		},
		{
			"mode": "board",
			"title": "⑧ 弹珠库",
			"desc": "弹珠库存放三种琉璃珠。每关可合成一次：3 普通→命核 60%，3 命核→命源 40%，失败会返还；也可以长按珠子拖到 ③ 弹珠灯替换。",
			"focus": [FateConfig.LIBRARY_AREA, FateConfig.HUD_CELL_BALL],
			"legend": [
				{"color": FateConfig.COLOR_TEXT, "name": "命运琉璃珠 · 5 分",
					"desc": "最常见的基础琉璃珠"},
				{"color": FateConfig.COLOR_GOLD, "name": "命核琉璃珠 · 10 分",
					"desc": "3 颗命运珠有 60% 概率合成"},
				{"color": FateConfig.COLOR_VIOLET, "name": "命源琉璃珠 · 20 分",
					"desc": "3 颗命核珠有 40% 概率合成"},
			],
		},
		{
			"mode": "corridor",
			"title": "走廊与局外行囊",
			"desc": "每两间房之间要沿走廊前进：走近门即可开始试炼；在 NPC 附近停留 1 秒，可以听到这一间的命运故事。一局结束后，行囊里的琉璃珠与卡牌能带入下一局（最多 3 珠 / 2 卡）。",
			"focus": [],
			"legend": [
				{"color": FateConfig.COLOR_JADE, "name": "命运回廊",
					"desc": "10 间房，10 扇门，10 段命运"},
				{"color": FateConfig.COLOR_VIOLET, "name": "局外行囊",
					"desc": "跨局保留的琉璃珠与卡牌"},
			],
		},
		{
			"mode": "all",
			"title": "开始试炼",
			"desc": "准备就绪：长按拖动道具、按弹簧发射、把得分推到目标分。祝你好运，旅者——投掷的瞬间，便是自由本身。",
			"focus": [],
			"legend": [
				{"color": FateConfig.COLOR_GOLD, "name": "随时可以回来",
					"desc": "主菜单 → 新手教程，可再次查看本讲解"},
			],
		},
	]
	return pages


# ==================================================================
# 背景 / 顶栏
# ==================================================================

func _build_background() -> void:
	var base := ColorRect.new()
	base.color = FateConfig.COLOR_BG_DEEP
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(base)
	add_child(base)

	var bg := TextureRect.new()
	bg.texture = _load_texture("res://assets/art/hall_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(bg)
	add_child(bg)

	var dust := CPUParticles2D.new()
	dust.texture = _load_texture("res://assets/art/particle_dot.png")
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.amount = 30
	dust.lifetime = 14.0
	dust.preprocess = 7.0
	dust.position = Vector2(640.0, 380.0)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(620.0, 330.0)
	dust.direction = Vector2(0.0, -1.0)
	dust.spread = 20.0
	dust.gravity = Vector2(0.0, -6.0)
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 12.0
	dust.scale_amount_min = 0.14
	dust.scale_amount_max = 0.45
	dust.color = Color(0.9, 0.82, 0.58, 0.22)
	dust.emitting = true
	add_child(dust)


func _build_top_bar() -> void:
	var back := UI.button("← 返回", 20, 56.0)
	back.custom_minimum_size = Vector2(160.0, 56.0)
	back.size = Vector2(160.0, 56.0)
	back.position = Vector2(24.0, 20.0)
	back.pressed.connect(_on_skip_pressed)
	UI.add_click_sfx(back)
	add_child(back)

	var title := UI.title("新手教程 · 命运回廊入门", 34, FateConfig.COLOR_GOLD)
	title.position = Vector2(0.0, 22.0)
	title.size = Vector2(1280.0, 56.0)
	add_child(title)

	var sub := UI.label("逐页讲解 P1 台面各区域名词 · 共 %d 页" % _pages.size(), 14,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.72), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0.0, 76.0)
	sub.size = Vector2(1280.0, 22.0)
	add_child(sub)

	var line := ColorRect.new()
	line.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.45)
	line.position = Vector2(24.0, 98.0)
	line.size = Vector2(1232.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)


# ==================================================================
# 左侧：P1 示意图
# ==================================================================

func _build_board() -> void:
	var frame := Panel.new()
	frame.position = BOARD_POS - Vector2(6.0, 6.0)
	frame.size = BOARD_SIZE + Vector2(12.0, 12.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.04, 0.03, 0.07, 0.9),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.85), 0, 2))
	add_child(frame)

	_board = HallBoard.new()
	_board.position = BOARD_POS
	_board.size = BOARD_SIZE
	_board.font = UI.body_font()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

	_board_note = UI.label("P1 布局示意图 · 高亮区域为当前讲解", 12,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.72))
	_board_note.position = Vector2(20.0, 582.0)
	_board_note.size = Vector2(844.0, 20.0)
	add_child(_board_note)


# ==================================================================
# 右侧：名词 / 说明 / 图例
# ==================================================================

func _build_side_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(884.0, 100.0)
	panel.size = Vector2(372.0, 506.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.06, 0.047, 0.10, 0.95),
			Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.72), 0, 2))
	add_child(panel)

	_page_title = UI.title("", 30, FateConfig.COLOR_GOLD)
	_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_page_title.position = Vector2(18.0, 12.0)
	_page_title.size = Vector2(336.0, 46.0)
	panel.add_child(_page_title)

	var tag := UI.label("新手教程 · 区域讲解", 12,
			Color(FateConfig.COLOR_VIOLET.r, FateConfig.COLOR_VIOLET.g,
			FateConfig.COLOR_VIOLET.b, 0.9))
	tag.position = Vector2(18.0, 54.0)
	tag.size = Vector2(336.0, 18.0)
	panel.add_child(tag)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.6)
	divider.position = Vector2(18.0, 80.0)
	divider.size = Vector2(336.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	_page_desc = UI.label("", 17, FateConfig.COLOR_TEXT)
	_page_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_desc.position = Vector2(18.0, 92.0)
	_page_desc.size = Vector2(336.0, 138.0)
	_page_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(_page_desc)

	var divider2 := ColorRect.new()
	divider2.color = Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.8)
	divider2.position = Vector2(18.0, 238.0)
	divider2.size = Vector2(336.0, 1.0)
	divider2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider2)

	var legend_head := UI.label("本页要点", 14, FateConfig.COLOR_GOLD_DIM)
	legend_head.position = Vector2(18.0, 246.0)
	legend_head.size = Vector2(336.0, 20.0)
	panel.add_child(legend_head)

	_legend_box = UI.vbox(6)
	_legend_box.position = Vector2(18.0, 270.0)
	_legend_box.size = Vector2(336.0, 226.0)
	panel.add_child(_legend_box)


# ==================================================================
# 底部：翻页 / 跳过 / 进入试炼
# ==================================================================

func _build_bottom_bar() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.022, 0.055, 0.9)
	bg.position = Vector2(0.0, 610.0)
	bg.size = Vector2(1280.0, 110.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var line := ColorRect.new()
	line.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.45)
	line.position = Vector2(0.0, 610.0)
	line.size = Vector2(1280.0, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)

	_prev_btn = UI.button("上一页", 22, 64.0)
	_prev_btn.custom_minimum_size = Vector2(180.0, 64.0)
	_prev_btn.size = Vector2(180.0, 64.0)
	_prev_btn.position = Vector2(24.0, 628.0)
	_prev_btn.pressed.connect(_on_prev_pressed)
	UI.add_click_sfx(_prev_btn)
	add_child(_prev_btn)

	_skip_btn = UI.button("跳过教程", 22, 64.0)
	_skip_btn.custom_minimum_size = Vector2(180.0, 64.0)
	_skip_btn.size = Vector2(180.0, 64.0)
	_skip_btn.position = Vector2(220.0, 628.0)
	_skip_btn.pressed.connect(_on_skip_pressed)
	UI.add_click_sfx(_skip_btn)
	add_child(_skip_btn)

	_page_label = UI.label("", 18, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	_page_label.position = Vector2(440.0, 616.0)
	_page_label.size = Vector2(400.0, 26.0)
	add_child(_page_label)

	# 页码圆点
	var dots_row := HBoxContainer.new()
	dots_row.position = Vector2(525.0, 652.0)
	dots_row.size = Vector2(230.0, 16.0)
	dots_row.add_theme_constant_override("separation", 10)
	dots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dots_row)
	for i in _pages.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14.0, 14.0)
		dot.size = Vector2(14.0, 14.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots_row.add_child(dot)
		_dots.append(dot)

	_next_btn = UI.button("下一页", 22, 64.0)
	_next_btn.custom_minimum_size = Vector2(180.0, 64.0)
	_next_btn.size = Vector2(180.0, 64.0)
	_next_btn.position = Vector2(1076.0, 628.0)
	_next_btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	_next_btn.pressed.connect(_on_next_pressed)
	UI.add_click_sfx(_next_btn)
	add_child(_next_btn)

	_start_btn = UI.button("进入试炼", 28, 76.0)
	_start_btn.custom_minimum_size = Vector2(240.0, 76.0)
	_start_btn.size = Vector2(240.0, 76.0)
	_start_btn.position = Vector2(1016.0, 620.0)
	_start_btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	var normal := UI.panel_style(Color(0.16, 0.115, 0.055, 0.98),
			FateConfig.COLOR_GOLD, 0, 4)
	normal.content_margin_top = 18.0
	normal.content_margin_bottom = 14.0
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.21, 0.155, 0.075, 1.0)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.07, 0.035, 1.0)
	_start_btn.add_theme_stylebox_override("normal", normal)
	_start_btn.add_theme_stylebox_override("hover", hover)
	_start_btn.add_theme_stylebox_override("pressed", pressed)
	_start_btn.visible = false
	_start_btn.pressed.connect(_on_start_pressed)
	UI.add_click_sfx(_start_btn)
	add_child(_start_btn)


# ==================================================================
# 翻页
# ==================================================================

func _set_page(index: int, animate: bool = true) -> void:
	if _pages.is_empty():
		return
	_page = clampi(index, 0, _pages.size() - 1)
	var data: Dictionary = _pages[_page]

	_board.show_page(data)
	var mode := String(data.get("mode", "board"))
	if _board_note != null:
		match mode:
			"all":
				_board_note.text = "全部区域总览 · 准备进入命运回廊"
			"corridor":
				_board_note.text = "走廊示意图 · 10 间房与局外行囊"
			_:
				_board_note.text = "P1 布局示意图 · 高亮区域为当前讲解"
	_page_title.text = String(data.get("title", ""))
	_page_desc.text = String(data.get("desc", ""))
	_page_label.text = "第 %d 页 / 共 %d 页" % [_page + 1, _pages.size()]
	_prev_btn.disabled = _page == 0
	_next_btn.visible = _page < _pages.size() - 1
	_start_btn.visible = _page == _pages.size() - 1
	_rebuild_legend(data.get("legend", []))
	_update_dots()

	if animate:
		_board.modulate.a = 0.55
		create_tween().tween_property(_board, "modulate:a", 1.0, 0.18)


func _update_dots() -> void:
	for i in _dots.size():
		var dot := _dots[i]
		var active := i == _page
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(0)
		style.set_border_width_all(1)
		style.anti_aliasing = false
		if active:
			style.bg_color = FateConfig.COLOR_GOLD
			style.border_color = FateConfig.COLOR_GOLD
		else:
			style.bg_color = Color(0.10, 0.08, 0.16, 0.9)
			style.border_color = Color(FateConfig.COLOR_PANEL_EDGE.r,
					FateConfig.COLOR_PANEL_EDGE.g, FateConfig.COLOR_PANEL_EDGE.b, 0.9)
		dot.add_theme_stylebox_override("panel", style)


func _on_prev_pressed() -> void:
	if _page <= 0:
		return
	_set_page(_page - 1)


func _on_next_pressed() -> void:
	if _page >= _pages.size() - 1:
		return
	_set_page(_page + 1)


func _on_skip_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	if get_tree() != null:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_start_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_gs = UI.game_state()
	if _gs != null:
		_gs.start_new_run()
	if get_tree() != null:
		get_tree().change_scene_to_file(CORRIDOR_PATH)


# ==================================================================
# 图例
# ==================================================================

func _rebuild_legend(entries: Array) -> void:
	for child in _legend_box.get_children():
		_legend_box.remove_child(child)
		child.queue_free()
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_legend_box.add_child(_make_legend_row(entry))


func _make_legend_row(entry: Dictionary) -> Control:
	var row := UI.hbox(10)
	var accent: Color = entry.get("color", FateConfig.COLOR_GOLD)
	row.add_child(_legend_icon(entry, accent))

	var text_box := UI.vbox(0)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UI.label(String(entry.get("name", "")), 15, accent)
	text_box.add_child(name_label)
	var desc_label := UI.label(String(entry.get("desc", "")), 12,
			FateConfig.COLOR_TEXT_DIM)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(276.0, 0.0)
	text_box.add_child(desc_label)
	row.add_child(text_box)
	return row


func _legend_icon(entry: Dictionary, accent: Color) -> Control:
	# 优先用现成立柱像素图；没有贴图时用「金框色块 / 序号块」兜底。
	var tex_path := String(entry.get("texture", ""))
	if tex_path != "":
		var tex := UI.load_texture(tex_path)
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(26.0, 26.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return icon

	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(26.0, 26.0)
	badge.size = Vector2(26.0, 26.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_border_width_all(2)
	style.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.95)
	style.border_color = accent
	style.anti_aliasing = false
	badge.add_theme_stylebox_override("panel", style)

	var ordinal := String(entry.get("ordinal", ""))
	if ordinal != "":
		var label := UI.label(ordinal, 14, accent, HORIZONTAL_ALIGNMENT_CENTER)
		label.position = Vector2.ZERO
		label.size = badge.size
		badge.add_child(label)
	return badge


# ==================================================================
# 工具
# ==================================================================

## 读取纹理：优先资源导入结果；未导入时直接读 PNG（桌面/自测可用），避免空白。
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


# ==================================================================
# P1 示意图（内联 _draw）
# ==================================================================

class HallBoard extends Control:
	const S := 0.66

	var font: Font = null
	var page: Dictionary = {}
	var pulse := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		pulse += delta
		queue_redraw()

	func show_page(data: Dictionary) -> void:
		page = data
		queue_redraw()

	# ---------------- 坐标换算 ----------------

	func _r(rect: Rect2) -> Rect2:
		return Rect2(rect.position * S, rect.size * S)

	func _p(point: Vector2) -> Vector2:
		return point * S

	func _is_focus(rect: Rect2) -> bool:
		var focus: Array = page.get("focus", [])
		for item in focus:
			if typeof(item) != TYPE_RECT2:
				continue
			var other: Rect2 = item
			if absf(other.position.x - rect.position.x) < 0.5 \
					and absf(other.position.y - rect.position.y) < 0.5 \
					and absf(other.size.x - rect.size.x) < 0.5 \
					and absf(other.size.y - rect.size.y) < 0.5:
				return true
		return false

	# ---------------- 绘制入口 ----------------

	func _draw() -> void:
		if font == null:
			font = ThemeDB.fallback_font
		var mode := String(page.get("mode", "board"))
		if mode == "corridor":
			_draw_corridor()
			return
		_draw_board(mode == "all")

	# ---------------- 主台面 ----------------

	func _draw_board(all_bright: bool) -> void:
		var full := _r(Rect2(0.0, 0.0, 1280.0, 720.0))
		draw_rect(full, Color(0.035, 0.028, 0.062, 0.96), true)
		draw_rect(full, Color(0.36, 0.29, 0.52, 0.95), false, 2.0)

		var regions := _regions()
		for reg in regions:
			_draw_region_base(reg, all_bright)
		_draw_hud_details()
		_draw_item_area()
		_draw_library_area()
		_draw_pegs()
		_draw_rail()
		_draw_slots()
		_draw_close()
		_draw_trajectory(all_bright or _is_focus(_rail_rect()))
		for reg in regions:
			var reg_rect: Rect2 = reg["rect"]
			if all_bright or _is_focus(reg_rect):
				_draw_region_highlight(reg)
		if _is_focus(FateConfig.ITEM_AREA) and not all_bright:
			_draw_drag_arrows()

	func _rail_rect() -> Rect2:
		return Rect2(FateConfig.RAIL_LEFT, FateConfig.RAIL_TOP,
				FateConfig.RAIL_RIGHT - FateConfig.RAIL_LEFT,
				FateConfig.RAIL_BOTTOM - FateConfig.RAIL_TOP)

	func _regions() -> Array:
		return [
			{"rect": FateConfig.HUD_CELL_SCORE, "color": FateConfig.COLOR_GOLD,
				"num": "①", "label": ""},
			{"rect": FateConfig.HUD_CELL_COIN, "color": FateConfig.COLOR_GOLD,
				"num": "②", "label": "命核碎片"},
			{"rect": FateConfig.HUD_CELL_BALL, "color": FateConfig.COLOR_VIOLET,
				"num": "③", "label": "弹珠灯"},
			{"rect": _rail_rect(), "color": FateConfig.COLOR_JADE,
				"num": "④", "label": ""},
			{"rect": FateConfig.PEG_AREA, "color": FateConfig.COLOR_JADE,
				"num": "⑤", "label": "立柱阵"},
			{"rect": FateConfig.GATE_RECT, "color": FateConfig.COLOR_CRIMSON,
				"num": "⑥", "label": ""},
			{"rect": FateConfig.ITEM_AREA, "color": FateConfig.COLOR_GOLD,
				"num": "⑦", "label": "道具区"},
			{"rect": FateConfig.LIBRARY_AREA, "color": FateConfig.COLOR_VIOLET,
				"num": "⑧", "label": "弹珠库"},
			{"rect": FateConfig.SLOT_RECT, "color": FateConfig.COLOR_JADE,
				"num": "", "label": "底部槽位"},
			{"rect": FateConfig.CLOSE_RECT, "color": FateConfig.COLOR_CRIMSON,
				"num": "❌", "label": ""},
		]

	func _draw_region_base(reg: Dictionary, all_bright: bool) -> void:
		var rect: Rect2 = reg["rect"]
		var color: Color = reg["color"]
		var rr := _r(rect)
		var active := all_bright or _is_focus(rect)
		draw_rect(rr, Color(color.r, color.g, color.b, 0.10 if active else 0.03), true)
		draw_rect(rr, Color(0.32, 0.27, 0.44, 0.9), false, 1.0)
		_draw_badge(rr, String(reg["num"]), color)
		var label := String(reg["label"])
		if label != "":
			_text(rr.position + Vector2(8.0, 4.0), label, 12,
					FateConfig.COLOR_TEXT_DIM)

	func _draw_badge(rect: Rect2, num: String, color: Color) -> void:
		if num == "":
			return
		var bsize := 21.0
		var bpos := rect.position + Vector2(rect.size.x - bsize - 5.0, 5.0)
		if rect.size.x < bsize + 10.0:
			bpos = rect.position + Vector2(3.0, 5.0)
		draw_rect(Rect2(bpos, Vector2(bsize, bsize)),
				Color(0.045, 0.035, 0.075, 0.96), true)
		draw_rect(Rect2(bpos, Vector2(bsize, bsize)), color, false, 1.0)
		var tw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12).x
		draw_string(font, bpos + Vector2((bsize - tw) * 0.5, 15.0), num,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, color)

	func _draw_region_highlight(reg: Dictionary) -> void:
		var rect: Rect2 = reg["rect"]
		var color: Color = reg["color"]
		var rr := _r(rect)
		var alpha := 0.65 + 0.35 * sin(pulse * 3.4)
		draw_rect(rr, Color(color.r, color.g, color.b, alpha), false, 3.0)
		draw_rect(rr.grow(4.0), Color(color.r, color.g, color.b, 0.18), false, 1.0)
		for corner in [Vector2(0.0, 0.0), Vector2(1.0, 0.0),
				Vector2(0.0, 1.0), Vector2(1.0, 1.0)]:
			var pos := rr.position + Vector2(corner.x * rr.size.x, corner.y * rr.size.y)
			draw_rect(Rect2(pos + Vector2(-4.0, -4.0), Vector2(9.0, 9.0)), color, true)

	func _text(pos: Vector2, text: String, size: int, color: Color) -> void:
		draw_string(font, pos + Vector2(0.0, float(size)), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)

	# ---------------- HUD / 台面细节 ----------------

	func _draw_hud_details() -> void:
		# ① 目标分：目标分 / 当前分 / 关卡名 / 进度条
		var score_rect := _r(FateConfig.HUD_CELL_SCORE)
		_text(score_rect.position + Vector2(10.0, 2.0), "目标分", 11,
				FateConfig.COLOR_TEXT_DIM)
		_text(score_rect.position + Vector2(56.0, 1.0), "0 / 30", 16,
				FateConfig.COLOR_GOLD)
		_text(score_rect.position + Vector2(10.0, 22.0), "第 1 间 · 微光之径", 10,
				FateConfig.COLOR_TEXT_DIM)
		# 进度条（像素段）
		var bar := Rect2(score_rect.position + Vector2(10.0, 40.0),
				Vector2(120.0, 8.0))
		draw_rect(bar, Color(0.1, 0.08, 0.16, 1.0), true)
		for i in 10:
			if i < 3:
				draw_rect(Rect2(bar.position + Vector2(i * 12.0, 0.0),
						Vector2(10.0, 8.0)), FateConfig.COLOR_GOLD, true)

		# ② 命核碎片
		var coin_rect := _r(FateConfig.HUD_CELL_COIN)
		var coin_center := coin_rect.position + Vector2(28.0, 40.0)
		draw_rect(Rect2(coin_center - Vector2(9.0, 9.0), Vector2(18.0, 18.0)),
				FateConfig.COLOR_GOLD, true)
		draw_rect(Rect2(coin_center - Vector2(5.0, 5.0), Vector2(10.0, 10.0)),
				Color(0.35, 0.26, 0.08, 1.0), true)
		_text(coin_rect.position + Vector2(50.0, 18.0), "× 12", 18,
				FateConfig.COLOR_GOLD)

		# ③ 弹珠灯（5 盏，其中 2 盏强化变红）
		var ball_rect := _r(FateConfig.HUD_CELL_BALL)
		for i in 5:
			var center := ball_rect.position + Vector2(34.0 + i * 52.0, 40.0)
			var is_buffed := i >= 3
			var col := FateConfig.COLOR_CRIMSON if is_buffed \
					else FateConfig.COLOR_VIOLET
			draw_rect(Rect2(center - Vector2(11.0, 11.0), Vector2(22.0, 22.0)),
					Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 1.0), true)
			draw_rect(Rect2(center - Vector2(11.0, 11.0), Vector2(22.0, 22.0)),
					col, false, 2.0)
		_text(ball_rect.position + Vector2(266.0, 2.0), "5 / 5", 13,
				FateConfig.COLOR_TEXT_DIM)

	func _draw_item_area() -> void:
		var area := _r(FateConfig.ITEM_AREA)
		for i in 3:
			var pos := area.position + Vector2(14.0 + i * 84.0, 30.0)
			var card := Rect2(pos, Vector2(72.0, 88.0))
			draw_rect(card, Color(0.10, 0.075, 0.16, 0.95), true)
			draw_rect(card, FateConfig.COLOR_GOLD_DIM, false, 1.0)
			var icon := pos + Vector2(36.0, 30.0)
			draw_rect(Rect2(icon - Vector2(8.0, 8.0), Vector2(16.0, 16.0)),
					FateConfig.COLOR_VIOLET_DIM, true)
			draw_rect(Rect2(icon - Vector2(8.0, 8.0), Vector2(16.0, 16.0)),
					FateConfig.COLOR_VIOLET, false, 1.0)
			var tw := font.get_string_size("卡", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
					10).x
			draw_string(font, pos + Vector2((72.0 - tw) * 0.5, 68.0), "卡",
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
					FateConfig.COLOR_TEXT_DIM)
		_text(area.position + Vector2(14.0, 128.0), "已购道具：长按拖到目标", 11,
				FateConfig.COLOR_TEXT_DIM)
		for i in 2:
			var chip := area.position + Vector2(14.0 + i * 96.0, 150.0)
			draw_rect(Rect2(chip, Vector2(84.0, 44.0)),
					Color(0.13, 0.095, 0.21, 0.95), true)
			draw_rect(Rect2(chip, Vector2(84.0, 44.0)),
					Color(FateConfig.COLOR_JADE.r, FateConfig.COLOR_JADE.g,
					FateConfig.COLOR_JADE.b, 0.6), false, 1.0)

	func _draw_library_area() -> void:
		var area := _r(FateConfig.LIBRARY_AREA)
		var colors := [FateConfig.COLOR_TEXT, FateConfig.COLOR_GOLD,
				FateConfig.COLOR_VIOLET]
		var names := ["命运", "命核", "命源"]
		for i in 3:
			var center := area.position + Vector2(40.0 + i * 72.0, 62.0)
			draw_rect(Rect2(center - Vector2(22.0, 22.0), Vector2(44.0, 44.0)),
					Color(colors[i].r * 0.4, colors[i].g * 0.4, colors[i].b * 0.4,
					1.0), true)
			draw_rect(Rect2(center - Vector2(22.0, 22.0), Vector2(44.0, 44.0)),
					colors[i], false, 2.0)
			var tw := font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, 10).x
			draw_string(font, Vector2(center.x - tw * 0.5,
					center.y + 38.0), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0,
					10, FateConfig.COLOR_TEXT_DIM)
		var btn := Rect2(area.position + Vector2(240.0, 30.0), Vector2(150.0, 40.0))
		draw_rect(btn, Color(0.16, 0.12, 0.05, 0.95), true)
		draw_rect(btn, FateConfig.COLOR_GOLD_DIM, false, 1.0)
		var tw := font.get_string_size("合成 60% / 40%",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11).x
		draw_string(font, btn.position + Vector2((btn.size.x - tw) * 0.5, 26.0),
				"合成 60% / 40%", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
				FateConfig.COLOR_GOLD)
		_text(area.position + Vector2(240.0, 84.0), "拖珠子到 ③ 替换", 10,
				FateConfig.COLOR_TEXT_DIM)

	func _draw_pegs() -> void:
		var area := FateConfig.PEG_AREA
		var cols := FateConfig.PEG_COLS
		var rows := FateConfig.PEG_ROWS
		var margin := 30.0
		var step := Vector2((area.size.x - margin * 2.0) / float(cols - 1),
				(area.size.y - margin * 2.0) / float(rows - 1))
		var radius := maxf(3.0, FateConfig.PEG_RADIUS * S)
		# 固定图案：普通为主，点缀黄/绿/黑/白（绿柱两枚相邻，示意绿线）
		var types := {
			Vector2i(1, 2): FateConfig.PEG_TYPE_YELLOW,
			Vector2i(3, 4): FateConfig.PEG_TYPE_YELLOW,
			Vector2i(5, 1): FateConfig.PEG_TYPE_YELLOW,
			Vector2i(2, 1): FateConfig.PEG_TYPE_GREEN,
			Vector2i(2, 2): FateConfig.PEG_TYPE_GREEN,
			Vector2i(4, 3): FateConfig.PEG_TYPE_BLACK,
			Vector2i(1, 5): FateConfig.PEG_TYPE_WHITE,
			Vector2i(6, 0): FateConfig.PEG_TYPE_WHITE,
		}
		var green_positions: Array[Vector2] = []
		for row in rows:
			for col in cols:
				var offset := step.x * 0.5 if row % 2 == 1 else 0.0
				var pos := area.position + Vector2(
						margin + col * step.x + offset,
						margin + row * step.y)
				pos.x = clampf(pos.x, area.position.x + radius,
						area.end.x - radius)
				var type := int(types.get(Vector2i(row, col), FateConfig.PEG_TYPE_NORMAL))
				var paint := _peg_color(type)
				var center := _p(pos)
				draw_rect(Rect2(center - Vector2(radius, radius),
						Vector2(radius * 2.0, radius * 2.0)), paint, true)
				if type == FateConfig.PEG_TYPE_GREEN:
					green_positions.append(pos)
		# 绿色连线（只画横/竖相邻的一对）
		if green_positions.size() >= 2:
			draw_line(_p(green_positions[0]), _p(green_positions[1]),
					Color(FateConfig.COLOR_JADE.r, FateConfig.COLOR_JADE.g,
					FateConfig.COLOR_JADE.b, 0.55), 2.0)

	func _peg_color(type: int) -> Color:
		match type:
			FateConfig.PEG_TYPE_YELLOW:
				return FateConfig.COLOR_GOLD
			FateConfig.PEG_TYPE_GREEN:
				return FateConfig.COLOR_JADE
			FateConfig.PEG_TYPE_BLACK:
				return FateConfig.COLOR_BLACK_PEG
			FateConfig.PEG_TYPE_WHITE:
				return FateConfig.COLOR_WHITE_PEG
			_:
				return Color(0.70, 0.67, 0.80)

	func _draw_rail() -> void:
		var rail := _r(_rail_rect())
		draw_rect(rail, Color(0.10, 0.08, 0.16, 0.95), true)
		draw_rect(rail, Color(0.5, 0.42, 0.68, 0.9), false, 1.0)
		# 偏转板
		draw_line(_p(FateConfig.DEFLECTOR_A), _p(FateConfig.DEFLECTOR_B),
				FateConfig.COLOR_GOLD_DIM, 2.0)
		# 弹簧发射位
		var launch := _p(FateConfig.LAUNCH_POS)
		draw_rect(Rect2(launch - Vector2(7.0, 5.0), Vector2(14.0, 10.0)),
				FateConfig.COLOR_JADE, true)
		draw_rect(Rect2(launch - Vector2(4.0, 2.0), Vector2(8.0, 3.0)),
				Color(0.95, 0.92, 0.78), true)
		_text(Vector2(launch.x - 150.0, 70.0), "长按蓄力 →", 11,
				FateConfig.COLOR_JADE)

	func _draw_trajectory(strong: bool) -> void:
		var a := _p(FateConfig.LAUNCH_POS)
		var b := _p(Vector2(1244.0, 300.0))
		var c := _p(Vector2(1000.0, 250.0))
		var color := FateConfig.COLOR_GOLD if strong \
				else Color(0.78, 0.66, 0.34, 0.35)
		var width := 2.0 if strong else 1.0
		var prev := a
		var steps := 30
		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var inv := 1.0 - t
			var p: Vector2 = a * (inv * inv) + b * (2.0 * inv * t) + c * (t * t)
			if i % 3 != 0:
				draw_line(prev, p, color, width)
			prev = p
		# 箭头
		draw_line(prev, prev + Vector2(-10.0, 6.0), color, width)
		draw_line(prev, prev + Vector2(-4.0, 12.0), color, width)

	func _draw_slots() -> void:
		var slots := _r(FateConfig.SLOT_RECT)
		draw_rect(slots, Color(0.08, 0.065, 0.13, 0.96), true)
		draw_rect(slots, Color(0.5, 0.42, 0.68, 0.9), false, 1.0)
		var names := ["×3", "×1.5", "×1", "裂隙", "×1", "×1.5"]
		var cell_w := slots.size.x / float(names.size())
		for i in names.size():
			var x := slots.position.x + i * cell_w
			if i > 0:
				draw_line(Vector2(x, slots.position.y),
						Vector2(x, slots.end.y), Color(0.35, 0.28, 0.5), 1.0)
			var tw := font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, 11).x
			draw_string(font, Vector2(x + (cell_w - tw) * 0.5, slots.position.y + 31.0),
					names[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
					FateConfig.COLOR_TEXT_DIM if i != 3 else FateConfig.COLOR_CRIMSON)

	func _draw_close() -> void:
		var rr := _r(FateConfig.CLOSE_RECT)
		draw_rect(rr, Color(0.10, 0.06, 0.08, 0.95), true)
		draw_rect(rr, FateConfig.COLOR_CRIMSON, false, 1.0)
		var size := 12
		var tw := font.get_string_size("×", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				size).x
		draw_string(font, Vector2(rr.position.x + (rr.size.x - tw) * 0.5,
				rr.position.y + 28.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1.0, size,
				FateConfig.COLOR_CRIMSON)

	func _draw_drag_arrows() -> void:
		var from := _r(FateConfig.ITEM_AREA).position + Vector2(60.0, 40.0)
		var to_peg := _r(FateConfig.PEG_AREA).get_center()
		var to_lamp := _r(FateConfig.HUD_CELL_BALL).position + Vector2(120.0, 44.0)
		_dashed_arrow(from, to_peg, FateConfig.COLOR_JADE)
		_dashed_arrow(from + Vector2(0.0, 26.0), to_lamp, FateConfig.COLOR_GOLD)

	func _dashed_arrow(from: Vector2, to: Vector2, color: Color) -> void:
		var dist := from.distance_to(to)
		var count := int(dist / 14.0)
		for i in count:
			var t := float(i) / float(maxi(count, 1))
			var p := from.lerp(to, t)
			draw_rect(Rect2(p - Vector2(2.0, 2.0), Vector2(4.0, 4.0)),
					Color(color.r, color.g, color.b, 0.7), true)
		draw_line(to, to + Vector2(-8.0, 8.0), color, 2.0)
		draw_line(to, to + Vector2(4.0, -10.0), color, 2.0)

	# ---------------- 走廊页 ----------------

	func _draw_corridor() -> void:
		var area := Rect2(20.0, 20.0, size.x - 40.0, size.y - 40.0)
		draw_rect(area, Color(0.035, 0.028, 0.062, 0.96), true)
		draw_rect(area, Color(0.36, 0.29, 0.52, 0.95), false, 2.0)

		_text(area.position + Vector2(6.0, 4.0), "命运回廊 · 10 间房", 15,
				FateConfig.COLOR_GOLD)

		var floor_y := area.position.y + 218.0
		var strip_left := area.position.x + 24.0
		var strip_right := area.end.x - 24.0
		draw_line(Vector2(strip_left, floor_y), Vector2(strip_right, floor_y),
				Color(0.45, 0.36, 0.62), 2.0)
		# 10 扇门
		for i in 10:
			var ratio := float(i) / 9.0
			var x := lerpf(strip_left + 26.0, strip_right - 26.0, ratio)
			draw_rect(Rect2(x - 13.0, floor_y - 86.0, 26.0, 86.0),
					Color(0.11, 0.085, 0.18, 0.98), true)
			draw_rect(Rect2(x - 13.0, floor_y - 86.0, 26.0, 86.0),
					FateConfig.COLOR_GOLD_DIM, false, 1.0)
			draw_rect(Rect2(x - 5.0, floor_y - 52.0, 10.0, 10.0),
					FateConfig.COLOR_GOLD, true)
			var tw := font.get_string_size(str(i + 1), HORIZONTAL_ALIGNMENT_LEFT,
					-1.0, 10).x
			draw_string(font, Vector2(x - tw * 0.5, floor_y - 92.0), str(i + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
					FateConfig.COLOR_TEXT_DIM)
			# NPC（门左侧）
			draw_rect(Rect2(x - 42.0, floor_y - 26.0, 8.0, 20.0),
					FateConfig.COLOR_VIOLET, true)
		# 玩家像素小人（起点）
		var player_x := strip_left + 8.0
		draw_rect(Rect2(player_x - 6.0, floor_y - 30.0, 12.0, 30.0),
				FateConfig.COLOR_JADE, true)
		draw_rect(Rect2(player_x - 8.0, floor_y - 42.0, 16.0, 8.0),
				Color(0.55, 0.45, 0.30), true)
		_text(Vector2(player_x - 26.0, floor_y - 62.0), "你", 11,
				FateConfig.COLOR_JADE)

		# 局外行囊卡片
		var bag := Rect2(area.position.x + 24.0, floor_y + 26.0,
				area.size.x - 48.0, 92.0)
		draw_rect(bag, Color(0.075, 0.058, 0.13, 0.96), true)
		draw_rect(bag, Color(FateConfig.COLOR_VIOLET.r, FateConfig.COLOR_VIOLET.g,
				FateConfig.COLOR_VIOLET.b, 0.85), false, 1.0)
		_text(bag.position + Vector2(10.0, 8.0), "局外行囊", 14,
				FateConfig.COLOR_VIOLET)
		var ball_colors := [FateConfig.COLOR_TEXT, FateConfig.COLOR_GOLD,
				FateConfig.COLOR_VIOLET]
		for i in 3:
			var center := bag.position + Vector2(28.0 + i * 34.0, 56.0)
			draw_rect(Rect2(center - Vector2(9.0, 9.0), Vector2(18.0, 18.0)),
					ball_colors[i], true)
		for i in 2:
			var pos := bag.position + Vector2(160.0 + i * 42.0, 38.0)
			draw_rect(Rect2(pos, Vector2(32.0, 40.0)),
					Color(0.18, 0.13, 0.28, 1.0), true)
			draw_rect(Rect2(pos, Vector2(32.0, 40.0)),
					FateConfig.COLOR_GOLD_DIM, false, 1.0)
		_text(bag.position + Vector2(250.0, 40.0), "最多带入 3 珠 · 2 卡", 12,
				FateConfig.COLOR_TEXT_DIM)

extends Control
## 《？！珠珠！？》主菜单。
##
## 界面由代码构建（根节点只挂脚本），避免 .tscn 手写节点出错。
## 按钮「开始试炼」→ GameState.start_new_run() → 切换到 res://scenes/corridor.tscn。

const UI := preload("res://scripts/ui/ui_theme.gd")

const GAME_SCENE_PATH := "res://scenes/corridor.tscn"
const SUBTITLE_TEXT := "命运回廊 · 沿着回廊，走进 3 个命运房间"

const COLOR_STARDUST := Color(0.95, 0.85, 0.62, 0.32)

var _gs := UI.game_state()

var _value_best: Label = null
var _value_shards: Label = null
var _value_runs: Label = null


func _ready() -> void:
	theme = UI.build_theme()
	_build_background()
	_build_stardust()
	_build_content()
	_refresh_stats()
	UI.play_bgm("menu")


# ================= 背景 =================

func _build_background() -> void:
	var base := ColorRect.new()
	base.color = FateConfig.COLOR_BG_DEEP
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(base)
	add_child(base)

	var bg := UI.background(UI.ART_MENU_BG)
	add_child(bg)


func _build_stardust() -> void:
	var dust := CPUParticles2D.new()
	dust.texture = UI.load_texture("res://assets/art/particle_dot.png")
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.amount = 44
	dust.lifetime = 15.0
	dust.preprocess = 7.0
	dust.position = Vector2(640.0, 390.0)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(630.0, 380.0)
	dust.direction = Vector2(0.0, -1.0)
	dust.spread = 28.0
	dust.gravity = Vector2(0.0, -9.0)
	dust.initial_velocity_min = 4.0
	dust.initial_velocity_max = 18.0
	dust.scale_amount_min = 0.18
	dust.scale_amount_max = 0.62
	dust.color = COLOR_STARDUST
	dust.emitting = true
	add_child(dust)


# ================= 内容 =================

func _build_content() -> void:
	# 像素标题框（方角 + 4px 鎏金边框 + 四角小方块）
	var frame := Panel.new()
	frame.position = Vector2(280.0, 34.0)
	frame.size = Vector2(720.0, 160.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.07, 0.05, 0.12, 0.92), FateConfig.COLOR_GOLD, 0, 4))
	add_child(frame)

	var inner := Panel.new()
	inner.position = Vector2(6.0, 6.0)
	inner.size = Vector2(708.0, 148.0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.0, 0.0, 0.0, 0.0),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.7), 0, 1))
	frame.add_child(inner)

	for corner in [Vector2(0.0, 0.0), Vector2(710.0, 0.0),
			Vector2(0.0, 150.0), Vector2(710.0, 150.0)]:
		var block := ColorRect.new()
		block.color = FateConfig.COLOR_GOLD
		block.position = corner
		block.size = Vector2(10.0, 10.0)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(block)

	# 主标题（游戏名读取 FateConfig.GAME_TITLE）
	var title := UI.title(FateConfig.GAME_TITLE, 76, FateConfig.COLOR_GOLD)
	title.position = Vector2(0.0, 52.0)
	title.size = Vector2(1280.0, 136.0)
	add_child(title)

	# 副标题
	var subtitle := UI.label(SUBTITLE_TEXT, 30, FateConfig.COLOR_VIOLET,
			HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.position = Vector2(0.0, 198.0)
	subtitle.size = Vector2(1280.0, 48.0)
	add_child(subtitle)

	# 鎏金分隔线
	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD.r, FateConfig.COLOR_GOLD.g,
			FateConfig.COLOR_GOLD.b, 0.42)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.position = Vector2(500.0, 258.0)
	divider.size = Vector2(280.0, 2.0)
	add_child(divider)

	# 开场剧情
	var story := UI.label(FateConfig.STORY_OPENING, 21, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.position = Vector2(190.0, 280.0)
	story.size = Vector2(900.0, 96.0)
	add_child(story)

	# 存档数据
	var stats_row := UI.hbox(24)
	stats_row.position = Vector2(316.0, 398.0)
	add_child(stats_row)
	var best_panel := _make_stat_panel("最高分")
	_value_best = best_panel.get_meta("value_label")
	stats_row.add_child(best_panel)
	var shard_panel := _make_stat_panel("命运碎片")
	_value_shards = shard_panel.get_meta("value_label")
	stats_row.add_child(shard_panel)
	var runs_panel := _make_stat_panel("游玩局数")
	_value_runs = runs_panel.get_meta("value_label")
	stats_row.add_child(runs_panel)

	# 局外行囊摘要（v1.2）
	var bag := UI.label("", 16, FateConfig.COLOR_JADE,
			HORIZONTAL_ALIGNMENT_CENTER)
	bag.name = "BagSummary"
	bag.position = Vector2(0.0, 508.0)
	bag.size = Vector2(1280.0, 24.0)
	add_child(bag)
	_refresh_bag(bag)

	# 开始试炼
	var start_btn := UI.button("开始试炼", 34, 92.0)
	start_btn.position = Vector2(400.0, 546.0)
	start_btn.size = Vector2(480.0, 92.0)
	start_btn.pivot_offset = Vector2(240.0, 46.0)
	start_btn.add_theme_color_override("font_color", FateConfig.COLOR_GOLD)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)
	_pulse_scale(start_btn, 1.0, 1.025, 2.4)

	# 底部提示与版本号
	var hint := UI.label("点击开始，踏入命运回廊", 18, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(0.0, 660.0)
	hint.size = Vector2(1280.0, 28.0)
	add_child(hint)

	var version := UI.label("v" + FateConfig.GAME_VERSION, 16,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	version.position = Vector2(0.0, 688.0)
	version.size = Vector2(1210.0, 22.0)
	add_child(version)


func _make_stat_panel(heading: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200.0, 96.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.12, 0.09, 0.20, 0.84), FateConfig.COLOR_PANEL_EDGE, 16, 2))

	var box := UI.vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(UI.label(heading, 18, FateConfig.COLOR_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER))
	var value := UI.label("0", 36, FateConfig.COLOR_GOLD,
			HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(value)
	panel.add_child(box)
	panel.set_meta("value_label", value)
	return panel


# ================= 数据 / 交互 =================

func _refresh_stats() -> void:
	if _gs == null:
		push_warning("[MainMenu] 未找到 GameState，跳过存档数据刷新")
		return
	if _value_best != null:
		_value_best.text = str(_gs.best_score)
	if _value_shards != null:
		_value_shards.text = str(_gs.total_shards)
	if _value_runs != null:
		_value_runs.text = str(_gs.runs_played)


func _refresh_bag(bag: Label) -> void:
	if bag == null:
		return
	if _gs == null:
		bag.text = "行囊：0 珠 / 0 卡"
		return
	var balls := _gs.meta_balls_normal + _gs.meta_balls_advanced
	bag.text = "行囊：%d 珠 / %d 卡" % [balls, _gs.meta_cards.size()]


func _on_start_pressed() -> void:
	UI.play_sfx("click")
	if _gs != null:
		_gs.start_new_run()
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


# ================= 简单动画 =================

func _pulse(target: CanvasItem, property: String, from_value: float, to_value: float,
		duration: float) -> void:
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(target, property, to_value, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target, property, from_value, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _pulse_scale(target: Control, from_scale: float, to_scale: float,
		duration: float) -> void:
	target.scale = Vector2(from_scale, from_scale)
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(target, "scale", Vector2(to_scale, to_scale), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target, "scale", Vector2(from_scale, from_scale), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

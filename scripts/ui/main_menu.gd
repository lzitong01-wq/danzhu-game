extends Control
## 《！？珠珠？！》v1.5 主菜单（独游简洁风：虚化星空 + 右侧无脸主角 + 五项菜单）。
##
## 版式：
##   背景 = assets/art/menu_bg_blur.png（预模糊暗星空）
##   右侧 = assets/art/menu_hero_faceless.png（无脸占星师剪影，轻微浮动 + 星尘）
##   左侧 = 像素标题「！？珠珠？！」/ 副标题 / 等级小字 / 竖排五项按钮
##
## 五项（文案严格取自 FateConfig.MENU_*）：
##   继续未尽之命运 → GameState.resume_run() + corridor（无存档置灰，并显示「第X间 · 关卡名」）
##   起新途之命运   → GameState.start_new_run() + corridor
##   设置           → 音乐/音效音量弹窗（本地 user://frontend_flags.cfg）
##   关于我们       → 弹窗显示 FateConfig.ABOUT_TEXT
##   退出           → GameState.save_game() 后退出
##
## 只读使用 FateConfig / GameState / FateUI；不直接书写 Autoload 标识符（--check-only 兼容）。

const UI := preload("res://scripts/ui/ui_theme.gd")

const CORRIDOR_PATH := "res://scenes/corridor.tscn"
const BG_BLUR_PATH := "res://assets/art/menu_bg_blur.png"
const HERO_PATH := "res://assets/art/menu_hero_faceless.png"
const FLAGS_PATH := "user://frontend_flags.cfg"
const FLAG_SECTION := "frontend"

const MENU_WIDTH := 400.0
const MENU_BUTTON_H := 64.0
const MENU_SEP := 13

var _gs := UI.game_state()
var _audio := UI.audio_node()
var _flags := ConfigFile.new()

var _hero: TextureRect = null
var _hero_base_y := 0.0

var _continue_btn: Button = null
var _continue_sub: Label = null
var _level_label: Label = null

var _settings_layer: Control = null
var _about_layer: Control = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _music_value_label: Label = null
var _sfx_value_label: Label = null

var _music_value := 80
var _sfx_value := 80


func _ready() -> void:
	theme = UI.build_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(self)
	_gs = UI.game_state()
	_audio = UI.audio_node()
	_load_flags()

	_build_background()
	_build_hero()
	_build_title()
	_build_menu()
	_build_footer()

	_refresh_state()
	_apply_audio()
	UI.play_bgm("menu")
	_animate_hero.call_deferred()


# ==================================================================
# 背景 / 无脸主角
# ==================================================================

func _build_background() -> void:
	var base := ColorRect.new()
	base.color = FateConfig.COLOR_BG_DEEP
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(base)
	add_child(base)

	var bg := TextureRect.new()
	bg.name = "BackgroundBlur"
	bg.texture = _load_texture(BG_BLUR_PATH)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.set_full_rect(bg)
	add_child(bg)

	# 左上保持安静：背景图本身已在左侧压暗，这里不再叠硬边色块

	# 缓慢上浮的星尘
	var dust := CPUParticles2D.new()
	dust.name = "MenuDust"
	dust.texture = _load_texture("res://assets/art/particle_dot.png")
	dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dust.amount = 34
	dust.lifetime = 15.0
	dust.preprocess = 8.0
	dust.position = Vector2(640.0, 400.0)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(620.0, 360.0)
	dust.direction = Vector2(0.0, -1.0)
	dust.spread = 22.0
	dust.gravity = Vector2(0.0, -7.0)
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 14.0
	dust.scale_amount_min = 0.14
	dust.scale_amount_max = 0.5
	dust.color = Color(0.88, 0.80, 0.58, 0.22)
	dust.emitting = true
	add_child(dust)


func _build_hero() -> void:
	_hero = TextureRect.new()
	_hero.name = "HeroFaceless"
	_hero.texture = _load_texture(HERO_PATH)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_SCALE
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero.position = Vector2(720.0, 0.0)
	_hero.size = Vector2(560.0, 720.0)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.modulate.a = 0.0
	_hero_base_y = _hero.position.y
	add_child(_hero)

	# 主角周身的星尘（只落在右侧，避免干扰左侧文字）
	var hero_dust := CPUParticles2D.new()
	hero_dust.name = "HeroDust"
	hero_dust.texture = _load_texture("res://assets/art/particle_dot.png")
	hero_dust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero_dust.amount = 16
	hero_dust.lifetime = 7.0
	hero_dust.preprocess = 3.0
	hero_dust.position = Vector2(1000.0, 430.0)
	hero_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	hero_dust.emission_rect_extents = Vector2(220.0, 280.0)
	hero_dust.direction = Vector2(0.0, -1.0)
	hero_dust.spread = 30.0
	hero_dust.gravity = Vector2(0.0, -5.0)
	hero_dust.initial_velocity_min = 4.0
	hero_dust.initial_velocity_max = 16.0
	hero_dust.scale_amount_min = 0.16
	hero_dust.scale_amount_max = 0.55
	hero_dust.color = Color(0.80, 0.72, 1.0, 0.35)
	hero_dust.emitting = true
	add_child(hero_dust)


func _animate_hero() -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	var fade := create_tween()
	fade.tween_property(_hero, "modulate:a", 1.0, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var float_tween := create_tween()
	float_tween.set_loops()
	float_tween.tween_property(_hero, "position:y", _hero_base_y - 7.0, 3.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(_hero, "position:y", _hero_base_y + 3.0, 3.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ==================================================================
# 标题 / 菜单 / 页脚
# ==================================================================

func _build_title() -> void:
	var eyebrow := UI.label("FATE CORRIDOR · MARBLE TRIALS", 12,
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.75))
	eyebrow.position = Vector2(88.0, 62.0)
	eyebrow.size = Vector2(520.0, 20.0)
	add_child(eyebrow)

	var title := UI.title(FateConfig.GAME_TITLE, 84, FateConfig.COLOR_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(80.0, 80.0)
	title.size = Vector2(660.0, 118.0)
	add_child(title)

	var subtitle := UI.label(FateConfig.GAME_SUBTITLE, 22,
			FateConfig.COLOR_VIOLET)
	subtitle.position = Vector2(86.0, 202.0)
	subtitle.size = Vector2(520.0, 30.0)
	add_child(subtitle)

	_level_label = UI.label("", 14,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.85))
	_level_label.position = Vector2(88.0, 238.0)
	_level_label.size = Vector2(420.0, 22.0)
	add_child(_level_label)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.5)
	divider.position = Vector2(88.0, 268.0)
	divider.size = Vector2(340.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)


func _build_menu() -> void:
	var box := VBoxContainer.new()
	box.name = "MenuButtons"
	box.position = Vector2(84.0, 294.0)
	box.size = Vector2(MENU_WIDTH, 5.0 * MENU_BUTTON_H + 4.0 * MENU_SEP)
	box.add_theme_constant_override("separation", MENU_SEP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_continue_btn = _menu_button(FateConfig.MENU_CONTINUE)
	_continue_btn.pressed.connect(_on_continue_pressed)
	box.add_child(_continue_btn)

	# 「继续」右半的进度小字：第X间 · 关卡名
	_continue_sub = UI.label("", 12,
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.95), HORIZONTAL_ALIGNMENT_RIGHT)
	_continue_sub.anchor_left = 1.0
	_continue_sub.anchor_right = 1.0
	_continue_sub.anchor_top = 0.5
	_continue_sub.anchor_bottom = 0.5
	_continue_sub.offset_left = -236.0
	_continue_sub.offset_right = -18.0
	_continue_sub.offset_top = -14.0
	_continue_sub.offset_bottom = 14.0
	_continue_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continue_btn.add_child(_continue_sub)

	var new_btn := _menu_button(FateConfig.MENU_NEW)
	new_btn.pressed.connect(_on_new_pressed)
	box.add_child(new_btn)

	var settings_btn := _menu_button(FateConfig.MENU_SETTINGS)
	settings_btn.pressed.connect(open_settings)
	box.add_child(settings_btn)

	var about_btn := _menu_button(FateConfig.MENU_ABOUT)
	about_btn.pressed.connect(open_about)
	box.add_child(about_btn)

	var quit_btn := _menu_button(FateConfig.MENU_QUIT)
	quit_btn.pressed.connect(_on_quit_pressed)
	box.add_child(quit_btn)


func _menu_button(text: String) -> Button:
	var btn := UI.button(text, 25, MENU_BUTTON_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 独游简洁风：按钮文字左对齐，右半留给进度/提示小字
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", FateConfig.COLOR_GOLD)
	btn.add_theme_color_override("font_pressed_color", FateConfig.COLOR_GOLD)
	btn.add_theme_color_override("font_disabled_color",
			Color(0.58, 0.55, 0.64, 0.45))
	btn.add_theme_stylebox_override("normal", _btn_style(
			Color(0.045, 0.035, 0.075, 0.42),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.42)))
	btn.add_theme_stylebox_override("hover", _btn_style(
			Color(0.085, 0.065, 0.13, 0.62), FateConfig.COLOR_GOLD))
	btn.add_theme_stylebox_override("pressed", _btn_style(
			Color(0.03, 0.022, 0.05, 0.72), FateConfig.COLOR_GOLD))
	btn.add_theme_stylebox_override("disabled", _btn_style(
			Color(0.035, 0.028, 0.06, 0.28),
			Color(FateConfig.COLOR_PANEL_EDGE.r, FateConfig.COLOR_PANEL_EDGE.g,
			FateConfig.COLOR_PANEL_EDGE.b, 0.4)))
	UI.add_click_sfx(btn)
	return btn


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.bg_color = bg
	sb.border_color = border
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.anti_aliasing = false
	return sb


func _build_footer() -> void:
	# 版本号以 project.godot 的 config/version 为准（FateConfig.GAME_VERSION 由 Lead 维护）。
	var version := String(ProjectSettings.get_setting("application/config/version",
			FateConfig.GAME_VERSION))
	var foot := UI.label("v" + version + "　·　" + FateConfig.SPLASH_STUDIO, 12,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.45))
	foot.position = Vector2(24.0, 688.0)
	foot.size = Vector2(420.0, 20.0)
	add_child(foot)


# ==================================================================
# 状态刷新 / 行为
# ==================================================================

func _refresh_state() -> void:
	_gs = UI.game_state()
	var resumable := false
	if _gs != null:
		resumable = _gs.has_resumable_run()
		_level_label.text = "Lv.%d　命运经验 %d / %d" % [
				_gs.character_level, _gs.character_exp, _gs.exp_needed()]
	else:
		_level_label.text = "Lv.1　命运经验 0 / 100"
	_continue_btn.disabled = not resumable
	_continue_sub.visible = resumable
	if resumable and _gs != null:
		_continue_sub.text = "第%d间 · %s" % [_gs.level, _gs.get_level_name()]
	else:
		_continue_sub.text = ""


func _on_continue_pressed() -> void:
	if _gs == null or not _gs.has_resumable_run():
		return
	_gs.resume_run()
	_goto(CORRIDOR_PATH)


func _on_new_pressed() -> void:
	if _gs == null:
		push_warning("[MainMenu] 未找到 GameState（Autoload 缺失），无法开始新局")
		return
	_gs.start_new_run()
	_goto(CORRIDOR_PATH)


func _on_quit_pressed() -> void:
	if _gs != null:
		_gs.save_game()
	if get_tree() != null:
		get_tree().quit()


func _goto(path: String) -> void:
	if get_tree() == null:
		return
	get_tree().change_scene_to_file(path)


# ==================================================================
# 设置弹窗（音乐 / 音效音量）
# ==================================================================

func open_settings() -> void:
	_ensure_settings_layer()
	_settings_layer.visible = true
	_settings_layer.modulate.a = 0.0
	create_tween().tween_property(_settings_layer, "modulate:a", 1.0, 0.18)


func _ensure_settings_layer() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		return
	_settings_layer = Control.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(_settings_layer)
	_settings_layer.visible = false
	add_child(_settings_layer)

	_settings_layer.add_child(UI.dim_overlay(0.76))

	var panel := Panel.new()
	panel.position = Vector2(330.0, 168.0)
	panel.size = Vector2(620.0, 384.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.055, 0.042, 0.09, 0.985),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.9), 0, 2))
	_settings_layer.add_child(panel)

	var title := UI.title(FateConfig.MENU_SETTINGS, 38, FateConfig.COLOR_GOLD)
	title.position = Vector2(0.0, 14.0)
	title.size = Vector2(620.0, 58.0)
	panel.add_child(title)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.55)
	divider.position = Vector2(40.0, 78.0)
	divider.size = Vector2(540.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	var music_label := UI.label("音乐音量", 21, FateConfig.COLOR_TEXT)
	music_label.position = Vector2(50.0, 104.0)
	music_label.size = Vector2(130.0, 32.0)
	panel.add_child(music_label)

	_music_slider = _make_slider(_music_value)
	_music_slider.position = Vector2(190.0, 98.0)
	_music_slider.size = Vector2(300.0, 48.0)
	_music_slider.value_changed.connect(_on_music_changed)
	panel.add_child(_music_slider)

	_music_value_label = UI.label("%d%%" % _music_value, 17,
			FateConfig.COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_music_value_label.position = Vector2(500.0, 106.0)
	_music_value_label.size = Vector2(76.0, 28.0)
	panel.add_child(_music_value_label)

	var sfx_label := UI.label("音效音量", 21, FateConfig.COLOR_TEXT)
	sfx_label.position = Vector2(50.0, 172.0)
	sfx_label.size = Vector2(130.0, 32.0)
	panel.add_child(sfx_label)

	_sfx_slider = _make_slider(_sfx_value)
	_sfx_slider.position = Vector2(190.0, 166.0)
	_sfx_slider.size = Vector2(300.0, 48.0)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	panel.add_child(_sfx_slider)

	_sfx_value_label = UI.label("%d%%" % _sfx_value, 17,
			FateConfig.COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_sfx_value_label.position = Vector2(500.0, 174.0)
	_sfx_value_label.size = Vector2(76.0, 28.0)
	panel.add_child(_sfx_value_label)

	var close := UI.button("完成", 24, 64.0)
	close.custom_minimum_size = Vector2(240.0, 64.0)
	close.size = Vector2(240.0, 64.0)
	close.position = Vector2(190.0, 276.0)
	close.pressed.connect(_on_settings_close)
	UI.add_click_sfx(close)
	panel.add_child(close)


func _make_slider(value: int) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = float(value)
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(300.0, 48.0)

	var track := StyleBoxFlat.new()
	track.set_corner_radius_all(0)
	track.set_border_width_all(1)
	track.bg_color = Color(0.03, 0.024, 0.05, 0.95)
	track.border_color = Color(FateConfig.COLOR_PANEL_EDGE.r,
			FateConfig.COLOR_PANEL_EDGE.g, FateConfig.COLOR_PANEL_EDGE.b, 0.9)
	track.anti_aliasing = false
	track.content_margin_top = 10.0
	track.content_margin_bottom = 10.0

	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(0)
	fill.bg_color = FateConfig.COLOR_GOLD_DIM
	fill.anti_aliasing = false

	var fill_hi: StyleBoxFlat = fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = FateConfig.COLOR_GOLD

	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	return slider


func _on_music_changed(value: float) -> void:
	_music_value = clampi(int(round(value)), 0, 100)
	if _music_value_label != null:
		_music_value_label.text = "%d%%" % _music_value
	_apply_audio()


func _on_sfx_changed(value: float) -> void:
	_sfx_value = clampi(int(round(value)), 0, 100)
	if _sfx_value_label != null:
		_sfx_value_label.text = "%d%%" % _sfx_value
	_apply_audio()
	UI.play_sfx("coin")


func _on_settings_close() -> void:
	_write_flag("music_volume", _music_value)
	_write_flag("sfx_volume", _sfx_value)
	if _settings_layer != null and is_instance_valid(_settings_layer):
		_settings_layer.visible = false


func _apply_audio() -> void:
	if _audio == null:
		_audio = UI.audio_node()
	if _audio == null:
		return
	_audio.set_music_volume(_volume_to_db(_music_value))
	_audio.set_sfx_volume(_volume_to_db(_sfx_value))


func _volume_to_db(percent: int) -> float:
	if percent <= 0:
		return -80.0
	return linear_to_db(float(percent) / 100.0)


# ==================================================================
# 关于我们弹窗
# ==================================================================

func open_about() -> void:
	_ensure_about_layer()
	_about_layer.visible = true
	_about_layer.modulate.a = 0.0
	create_tween().tween_property(_about_layer, "modulate:a", 1.0, 0.18)


func _ensure_about_layer() -> void:
	if _about_layer != null and is_instance_valid(_about_layer):
		return
	_about_layer = Control.new()
	_about_layer.name = "AboutLayer"
	_about_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	UI.set_full_rect(_about_layer)
	_about_layer.visible = false
	add_child(_about_layer)

	_about_layer.add_child(UI.dim_overlay(0.78))

	var panel := Panel.new()
	panel.position = Vector2(260.0, 96.0)
	panel.size = Vector2(760.0, 528.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UI.panel_style(
			Color(0.055, 0.042, 0.09, 0.985),
			Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.9), 0, 2))
	_about_layer.add_child(panel)

	var title := UI.title(FateConfig.MENU_ABOUT, 40, FateConfig.COLOR_GOLD)
	title.position = Vector2(0.0, 16.0)
	title.size = Vector2(760.0, 62.0)
	panel.add_child(title)

	var divider := ColorRect.new()
	divider.color = Color(FateConfig.COLOR_GOLD_DIM.r, FateConfig.COLOR_GOLD_DIM.g,
			FateConfig.COLOR_GOLD_DIM.b, 0.55)
	divider.position = Vector2(40.0, 84.0)
	divider.size = Vector2(680.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	var body := UI.label(FateConfig.ABOUT_TEXT, 19, FateConfig.COLOR_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_constant_override("line_spacing", 8)
	body.position = Vector2(50.0, 104.0)
	body.size = Vector2(660.0, 300.0)
	panel.add_child(body)

	var foot := UI.label("琉璃回廊工作室　·　命运互动", 13,
			Color(FateConfig.COLOR_TEXT_DIM.r, FateConfig.COLOR_TEXT_DIM.g,
			FateConfig.COLOR_TEXT_DIM.b, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	foot.position = Vector2(0.0, 412.0)
	foot.size = Vector2(760.0, 20.0)
	panel.add_child(foot)

	var close := UI.button("完成", 24, 64.0)
	close.custom_minimum_size = Vector2(240.0, 64.0)
	close.size = Vector2(240.0, 64.0)
	close.position = Vector2(260.0, 444.0)
	close.pressed.connect(func() -> void:
		_about_layer.visible = false
	)
	UI.add_click_sfx(close)
	panel.add_child(close)


# ==================================================================
# 本地设置（user://frontend_flags.cfg，不写游戏存档）
# ==================================================================

func _load_flags() -> void:
	_flags.load(FLAGS_PATH)
	var music_stored := int(_flags.get_value(FLAG_SECTION, "music_volume", -1))
	var sfx_stored := int(_flags.get_value(FLAG_SECTION, "sfx_volume", -1))
	if music_stored < 0:
		music_stored = _default_volume_percent(true)
	if sfx_stored < 0:
		sfx_stored = _default_volume_percent(false)
	_music_value = clampi(music_stored, 0, 100)
	_sfx_value = clampi(sfx_stored, 0, 100)


func _default_volume_percent(music: bool) -> int:
	var audio := UI.audio_node()
	if audio == null:
		return 80
	var db: float = audio.music_volume_db if music else audio.sfx_volume_db
	return clampi(int(round(db_to_linear(db) * 100.0)), 0, 100)


func _write_flag(key: String, value: Variant) -> void:
	_flags.set_value(FLAG_SECTION, key, value)
	_flags.save(FLAGS_PATH)


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

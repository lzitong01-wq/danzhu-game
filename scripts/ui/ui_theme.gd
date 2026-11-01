class_name FateUI
extends RefCounted
## 《？！珠珠！？》UI 主题与控件工厂（全部由代码构建，不依赖 .tres）。
##
## 用法：
##     const UI := preload("res://scripts/ui/ui_theme.gd")
##     theme = UI.build_theme()
##     add_child(UI.title("？！珠珠！？", 84))
##
## 颜色统一取自 FateConfig，保证 UI 与玩法层视觉一致。

# ---------------- 资源路径 ----------------
const FONT_BODY_PATH := "res://assets/fonts/FateBody.ttf"
const FONT_TITLE_PATH := "res://assets/fonts/FateTitle.ttf"
const ART_MENU_BG := "res://assets/art/bg_menu.png"
const ART_BOARD_BG := "res://assets/art/bg_board.png"
const ICON_DIR := "res://assets/art/icons/"

# 注意：Godot 4.6 的 `--check-only --script` 独立检查不会注册 Autoload 标识符
# （直接书写 GameState / Audio 会报 “Identifier not found”）。
# 因此这里通过 preload 脚本类型 + /root 节点访问，既保留静态类型检查，也不影响运行时。
const GameStateScript := preload("res://scripts/autoload/game_state.gd")
const AudioScript := preload("res://scripts/autoload/audio.gd")

static var _body_font: Font = null
static var _title_font: Font = null
static var _theme: Theme = null

# ================= Autoload 访问 =================

## 取全局状态单例（GameState，Autoload）。
static func game_state() -> GameStateScript:
	var loop = Engine.get_main_loop()
	if loop == null:
		return null
	return loop.root.get_node_or_null("GameState") as GameStateScript


## 取音频单例（Audio，Autoload）。
static func audio_node() -> AudioScript:
	var loop = Engine.get_main_loop()
	if loop == null:
		return null
	return loop.root.get_node_or_null("Audio") as AudioScript


static func play_sfx(sfx_name: String, volume_offset_db: float = 0.0,
		pitch: float = 1.0) -> void:
	var audio := audio_node()
	if audio != null:
		audio.play_sfx(sfx_name, volume_offset_db, pitch)


static func play_bgm(track: String) -> void:
	var audio := audio_node()
	if audio != null:
		audio.play_bgm(track)


# ================= 字体 =================

static func body_font() -> Font:
	if _body_font == null:
		_body_font = _load_font(FONT_BODY_PATH)
	return _body_font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = _load_font(FONT_TITLE_PATH)
	return _title_font


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Font:
			return res
	push_warning("[FateUI] 字体缺失，使用引擎默认字体：" + path)
	return ThemeDB.fallback_font


# ================= 主题 =================

## 构建全局主题：像素方角面板 + 鎏金 3px 边框 + 命运色文字。
## 结果在静态变量中缓存，多处调用共享同一份 Theme。
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	th.default_font = body_font()
	th.default_font_size = 22

	# ---- Button（方角 + 顶部高光，无阴影）----
	var normal := _btn_style(Color(0.10, 0.075, 0.17, 0.98),
			FateConfig.COLOR_GOLD_DIM, 3)
	var hover := _btn_style(Color(0.17, 0.12, 0.29, 1.0),
			FateConfig.COLOR_GOLD, 3)
	var pressed := _btn_style(Color(0.07, 0.05, 0.12, 1.0),
			FateConfig.COLOR_GOLD, 3)
	pressed.content_margin_top = 15.0
	pressed.content_margin_bottom = 11.0
	var disabled := _btn_style(Color(0.09, 0.075, 0.13, 0.85),
			Color(0.32, 0.28, 0.40, 0.9), 3)
	var focus := StyleBoxEmpty.new()

	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", focus)
	th.set_font("font", "Button", body_font())
	th.set_font_size("font_size", "Button", 26)
	th.set_color("font_color", "Button", FateConfig.COLOR_TEXT)
	th.set_color("font_hover_color", "Button", FateConfig.COLOR_GOLD)
	th.set_color("font_pressed_color", "Button", FateConfig.COLOR_GOLD)
	th.set_color("font_focus_color", "Button", FateConfig.COLOR_TEXT)
	th.set_color("font_disabled_color", "Button", Color(0.64, 0.62, 0.72, 0.55))
	th.set_constant("outline_size", "Button", 0)

	# ---- Panel / PanelContainer ----
	var panel := panel_style(Color(0.10, 0.075, 0.17, 0.96),
			FateConfig.COLOR_PANEL_EDGE, 0, 3)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)

	# ---- Label ----
	th.set_font("font", "Label", body_font())
	th.set_font_size("font_size", "Label", 22)
	th.set_color("font_color", "Label", FateConfig.COLOR_TEXT)

	# ---- ProgressBar（若玩法层复用） ----
	th.set_stylebox("background", "ProgressBar", _flat(
			Color(0.06, 0.045, 0.10, 0.95), FateConfig.COLOR_PANEL_EDGE, 0, 2, false))
	var fill := _flat(FateConfig.COLOR_GOLD_DIM, FateConfig.COLOR_GOLD, 0, 2, false)
	th.set_stylebox("fill", "ProgressBar", fill)

	_theme = th
	return _theme


## 像素方角样式：圆角恒为 0、无柔和阴影、硬色块。
static func _flat(bg: Color, edge: Color, _radius: int, border: int,
		_shadow: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(maxi(1, border))
	sb.border_color = edge
	sb.anti_aliasing = false
	return sb


static func _btn_style(bg: Color, edge: Color, border: int) -> StyleBoxFlat:
	var sb := _flat(bg, edge, 0, border, false)
	sb.border_width_top = border + 1
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


# ================= 通用样式 =================

## 像素风面板样式（方形硬边；忽略圆角/阴影参数以兼容旧调用）。
static func panel_style(bg: Color, edge: Color, _radius: int = 0, border: int = 3,
		_shadow: bool = false) -> StyleBoxFlat:
	var sb := _flat(bg, edge, 0, border, false)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


## 半透明玻璃面板（Panel 节点，默认不拦截鼠标）。
static func glass_panel(edge = null, radius: int = 18, bg = null) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c_edge: Color = FateConfig.COLOR_PANEL_EDGE if edge == null else edge
	var c_bg: Color = Color(0.12, 0.09, 0.20, 0.88) if bg == null else bg
	p.add_theme_stylebox_override("panel", panel_style(c_bg, c_edge, radius))
	return p


## 深色遮罩（全屏，拦截点击用，模态界面用）。
static func dim_overlay(alpha: float = 0.72) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, alpha)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


# ================= 控件工厂 =================

## 普通文本（正文黑体）。
static func label(text: String, font_size: int = 22, color = null,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var c: Color = FateConfig.COLOR_TEXT if color == null else color
	lbl.add_theme_font_override("font", body_font())
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", c)
	return lbl


## 像素风标题（标题楷体 + 2px 深色硬描边 + 2px 偏移阴影，无柔光）。
static func title(text: String, font_size: int = 56, color = null) -> Label:
	var c: Color = FateConfig.COLOR_GOLD if color == null else color
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", title_font())
	lbl.add_theme_font_size_override("font_size", maxi(8, int(font_size)))
	lbl.add_theme_color_override("font_color", c)
	lbl.add_theme_color_override("font_outline_color",
			Color(FateConfig.COLOR_VOID.r, FateConfig.COLOR_VOID.g,
			FateConfig.COLOR_VOID.b, 0.95))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_constant_override("shadow_outline_size", 0)
	return lbl


## 标准按钮（像素方角 + 顶部 2px 高光，最小高度 ≥64px）。
static func button(text: String, font_size: int = 26,
		min_height: float = 64.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, min_height)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", body_font())
	btn.add_theme_font_size_override("font_size", int(font_size))
	btn.add_theme_color_override("font_color", FateConfig.COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", FateConfig.COLOR_GOLD)
	btn.add_theme_color_override("font_pressed_color", FateConfig.COLOR_GOLD)
	btn.add_theme_color_override("font_disabled_color", Color(0.64, 0.62, 0.72, 0.6))
	# 顶部 2px 像素高光
	var shine := ColorRect.new()
	shine.color = Color(1.0, 0.95, 0.75, 0.16)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.anchor_left = 0.0
	shine.anchor_right = 1.0
	shine.offset_left = 3.0
	shine.offset_right = -3.0
	shine.offset_top = 3.0
	shine.offset_bottom = 5.0
	btn.add_child(shine)
	return btn


## 为按钮附带统一点击音效（Audio 缺失时自身静默）。
static func add_click_sfx(btn: BaseButton) -> void:
	btn.pressed.connect(func() -> void:
		play_sfx("click")
	)


# ================= 纹理 / 图标 =================

static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	return null


## 道具图标（name 即 FateConfig.ITEMS 的 id / "coin" / "shard"）。
static func icon_texture(icon_name: String) -> Texture2D:
	return load_texture(ICON_DIR + icon_name + ".png")


## 弹珠图标（弹珠图在 assets/art 根目录，不在 icons/ 下）。
static func ball_icon(advanced: bool, pixel_size: float = 32.0) -> TextureRect:
	var path := "res://assets/art/ball_advanced.png" if advanced \
			else "res://assets/art/ball_normal.png"
	var tr := TextureRect.new()
	tr.texture = load_texture(path)
	tr.custom_minimum_size = Vector2(pixel_size, pixel_size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func icon(icon_name: String, pixel_size: float = 28.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon_texture(icon_name)
	tr.custom_minimum_size = Vector2(pixel_size, pixel_size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## 全屏背景贴图（缺失时透明，由场景底色兜底）。
static func background(path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load_texture(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


# ================= 布局辅助 =================

static func set_full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func vbox(separation: int = 10) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func hbox(separation: int = 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func margin(all_px: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", all_px)
	m.add_theme_constant_override("margin_right", all_px)
	m.add_theme_constant_override("margin_top", all_px)
	m.add_theme_constant_override("margin_bottom", all_px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 金币 / 碎片等「图标 + 数值」小组合。
static func stat_chip(icon_name: String, value_text: String, icon_size: float = 28.0,
		value_color = null) -> HBoxContainer:
	var row := hbox(6)
	row.add_child(icon(icon_name, icon_size))
	row.add_child(label(value_text, 24, value_color))
	return row


## 道具图标（资源缺失时用「首字 + 金框」兜底，保证未 import 时界面不空白）。
static func item_icon(item_id: String, pixel_size: float = 32.0) -> Control:
	var tex := icon_texture(item_id)
	if tex != null:
		return icon(item_id, pixel_size)
	var fallback := Panel.new()
	fallback.custom_minimum_size = Vector2(pixel_size, pixel_size)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_border_width_all(2)
	style.bg_color = Color(0.13, 0.10, 0.20, 0.98)
	style.border_color = Color(FateConfig.COLOR_GOLD_DIM.r,
			FateConfig.COLOR_GOLD_DIM.g, FateConfig.COLOR_GOLD_DIM.b, 0.9)
	fallback.add_theme_stylebox_override("panel", style)
	var display_name := item_id
	if FateConfig.ITEMS.has(item_id):
		display_name = String(FateConfig.ITEMS[item_id].get("name", item_id))
	var initial := "?"
	if display_name.length() > 0:
		initial = display_name.substr(0, 1)
	var letter := label(initial, maxi(12, int(pixel_size * 0.46)),
			FateConfig.COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.add_child(letter)
	return fallback

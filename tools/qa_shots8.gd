extends Node
## Lead v1.7 验收：手游回廊（顶部只留返回+行囊）/P1 对话/中间偏右交互按钮/新远景/商店P2
const OUT := "G:/GoDot/shots"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"

var _n := 0
var corridor: Node = null
var game: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.2
	await get_tree().process_frame
	await _run()
	print("[QA8] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v17_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA8] ", path)

func _find_button(root: Node, text_substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(text_substr) >= 0:
			return child
	for child in root.get_children():
		var r := _find_button(child, text_substr)
		if r != null:
			return r
	return null

func _find_text(root: Node, text_substr: String) -> Node:
	for child in root.get_children():
		if child is Label and String(child.text).find(text_substr) >= 0:
			return child
	for child in root.get_children():
		var r := _find_text(child, text_substr)
		if r != null:
			return r
	return null

func _find_with_method(root: Node, method: String) -> Node:
	for child in root.get_children():
		if child.has_method(method):
			return child
	var found: Node = null
	for child in root.get_children():
		found = _find_with_method(child, method)
		if found != null:
			return found
	return null

func _press(btn: Button) -> void:
	if btn == null:
		print("[QA8] button not found")
		return
	btn.emit_signal("pressed")

func _click_at(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = pos
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _new_corridor(level: int, player_x: float) -> Node:
	GameState.start_new_run()
	GameState.level = level
	var c := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(c)
	await get_tree().create_timer(1.0).timeout
	var p = c.get("player")
	if p != null:
		p.position = Vector2(player_x, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	return c

func _run() -> void:
	print("[QA8] === 回廊：顶部 UI / 新远景 / 交互键 / P1 对话 ===")
	corridor = await _new_corridor(2, FateConfig.CORRIDOR_DOOR_X[1] - FateConfig.CORRIDOR_NPC_OFFSET + 30.0)
	await _shot("corridor_v17")
	var interact_btn := _find_button(corridor, "交互")
	print("[QA8] interact_btn=", interact_btn)
	await _shot("corridor_interact")
	_press(interact_btn)
	await get_tree().create_timer(1.0).timeout
	await _shot("dialog_p1_typewriter")
	# 点击文本框补全
	_click_at(Vector2(900, 400))
	await get_tree().create_timer(0.6).timeout
	await _shot("dialog_p1_full")
	# 再点一次显示进入试炼
	_click_at(Vector2(900, 400))
	await get_tree().create_timer(0.6).timeout
	var enter_btn := _find_button(corridor, "进入试炼")
	print("[QA8] enter_btn=", enter_btn, " npc_seen=", GameState.is_npc_seen(2))
	await _shot("dialog_enter_button")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA8] === 绕过 NPC 到门前 → 进入试炼 ===")
	corridor = await _new_corridor(2, FateConfig.CORRIDOR_DOOR_X[1] - 10.0)
	var door_enter := _find_button(corridor, "进入试炼")
	print("[QA8] door enter_btn=", door_enter)
	await _shot("door_enter_button")
	# 行囊按钮打开面板
	var bag_btn := _find_button(corridor, "行囊")
	print("[QA8] bag_btn=", bag_btn)
	_press(bag_btn)
	await get_tree().create_timer(1.0).timeout
	var panel := _find_with_method(corridor, "open_to_tab")
	await _shot("bag_character_panel")
	if panel != null:
		_press(_find_button(panel, "弹珠"))
		await get_tree().create_timer(0.4).timeout
		await _shot("bag_panel_balls")
		_press(_find_button(panel, "关闭"))
		await get_tree().create_timer(0.4).timeout
	corridor.queue_free()
	await get_tree().process_frame

	print("[QA8] === 商店 P2 ===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	var prep := _find_with_method(game, "open_prep")
	await _shot("prep_p2")
	var old_line := _find_text(prep, "查看牌组")
	var old_tip := _find_text(prep, "购买 / 整理完毕")
	print("[QA8] old 查看牌组=", old_line, " old tip=", old_tip)
	var carry_btn := _find_button(prep, "携带道具")
	var ball_btn := _find_button(prep, "携带弹珠")
	print("[QA8] carry_btn=", carry_btn, " ball_btn=", ball_btn)
	_press(carry_btn)
	await get_tree().create_timer(0.9).timeout
	await _shot("prep_panel_items")
	var p2 := _find_with_method(prep, "open_to_tab")
	if p2 != null:
		_press(_find_button(p2, "关闭"))
		await get_tree().create_timer(0.5).timeout
	_press(ball_btn)
	await get_tree().create_timer(0.9).timeout
	await _shot("prep_panel_balls")
	var p3 := _find_with_method(prep, "open_to_tab")
	if p3 != null:
		_press(_find_button(p3, "关闭"))
		await get_tree().create_timer(0.5).timeout
	game.queue_free()
	await get_tree().process_frame

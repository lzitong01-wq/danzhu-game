extends Node
## Lead v1.4 验收：启动页/健康忠告、主菜单(继续)、教程大厅、走廊(动画+NPC文案)、PREP刷新/合成、右端通道、失败story、续关存档
## 用法： & 'D:\Godot_v4.6.3-stable_win64.exe' --path 'G:\GoDot\？！珠珠！？' res://tools/qa_shots5.tscn --resolution 1280x720 --position 40,40
const OUT := "G:/GoDot/shots"
const SPLASH := "res://scenes/splash.tscn"
const MENU := "res://scenes/main_menu.tscn"
const HALL := "res://scenes/tutorial_hall.tscn"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"

var _n := 0
var game: Node = null
var hud: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.2
	await get_tree().process_frame
	await _run()
	print("[QA5] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v14_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA5] ", path)

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

func _find_button(root: Node, text_substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(text_substr) >= 0:
			return child
	for child in root.get_children():
		var r := _find_button(child, text_substr)
		if r != null:
			return r
	return null

func _press(btn: Button) -> void:
	if btn == null:
		print("[QA5] button not found")
		return
	btn.emit_signal("pressed")

func _key(keys: Array, pressed: bool) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = pressed
		Input.parse_input_event(ev)

func _run() -> void:
	print("[QA5] === 启动页 ===")
	var splash := (load(SPLASH) as PackedScene).instantiate()
	add_child(splash)
	await get_tree().create_timer(1.2).timeout
	await _shot("splash_loading")
	if splash.has_method("show_health_page"):
		splash.call("show_health_page")
	await get_tree().create_timer(0.6).timeout
	await _shot("splash_health_tip")
	splash.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA5] === 主菜单（含续关）===")
	GameState.start_new_run()
	GameState.level = 3
	GameState.save_game()
	var menu := (load(MENU) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.2).timeout
	await _shot("menu_with_continue")
	var settings_btn := _find_button(menu, "设置")
	_press(settings_btn)
	await get_tree().create_timer(0.6).timeout
	await _shot("menu_settings")
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA5] === 新手教程大厅 ===")
	var hall := (load(HALL) as PackedScene).instantiate()
	add_child(hall)
	await get_tree().create_timer(1.0).timeout
	await _shot("tutorial_hall_p1")
	if hall.has_method("_set_page"):
		hall.call("_set_page", 4, false)
	await get_tree().create_timer(0.5).timeout
	await _shot("tutorial_hall_p5")
	if hall.has_method("_set_page"):
		hall.call("_set_page", 7, false)
	await get_tree().create_timer(0.5).timeout
	await _shot("tutorial_hall_p8")
	hall.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA5] === 走廊（角色动画 + NPC 文案）===")
	GameState.start_new_run()
	GameState.level = 2
	var corridor := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(corridor)
	await get_tree().create_timer(1.2).timeout
	_key([KEY_D], true)
	await get_tree().create_timer(1.0).timeout
	await _shot("corridor_walk")
	_key([KEY_D], false)
	await get_tree().create_timer(0.7).timeout
	await _shot("corridor_idle")
	var player = corridor.get("player")
	if player != null and FateConfig.CORRIDOR_DOOR_X.size() > 1:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[1] - FateConfig.CORRIDOR_NPC_OFFSET + 40.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(1.8).timeout
	await _shot("corridor_npc_story")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA5] === 房间 PREP（刷新/合成）===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	hud = game.get("hud")
	var prep := _find_with_method(game, "open_prep")
	var refresh_btn := _find_button(prep, "刷新")
	print("[QA5] refresh_btn=", refresh_btn)
	_press(refresh_btn)
	await get_tree().create_timer(0.6).timeout
	await _shot("prep_after_refresh")
	GameState.library_normal = 4
	GameState.library_advanced = 4
	GameState.library_high = 1
	if hud != null:
		hud.call("refresh")
	await get_tree().create_timer(0.5).timeout
	await _shot("prep_library")
	var synth_btn := _find_button(hud, "合成命核")
	print("[QA5] synth_btn=", synth_btn)
	_press(synth_btn)
	await get_tree().create_timer(0.8).timeout
	await _shot("prep_synth_result")

	var start_btn := _find_button(prep, "开始试炼")
	_press(start_btn)
	await get_tree().create_timer(0.6).timeout
	var safe_btn := _find_button(prep, "稳妥开局")
	_press(safe_btn)
	await get_tree().create_timer(1.6).timeout
	print("[QA5] phase=", game.get("phase"), " double=", GameState.double_mode)

	var board = game.get("board")
	if board != null:
		var max_x := 0.0
		for peg in board.pegs:
			max_x = maxf(max_x, float(peg.position.x))
		print("[QA5] rightmost peg x=", max_x, " rail_left=", FateConfig.RAIL_LEFT,
			" gap_to_rail=", FateConfig.RAIL_LEFT - max_x)
	await _shot("play_pixel_10levels")

	# 发射一颗
	var pos := Vector2(1244.0, 676.0)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await get_tree().create_timer(0.55).timeout
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)
	await get_tree().create_timer(0.7).timeout
	await _shot("ball_flight_v14")
	await get_tree().create_timer(3.0).timeout

	# 失败结算（story）
	if game != null and is_instance_valid(game):
		var summary := GameState.fail_room()
		print("[QA5] fail story=", summary.get("story", ""))
		game.call("_show_result", false, summary)
		await get_tree().create_timer(1.2).timeout
		await _shot("result_fail_story")
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	print("[QA5] === 续关存档验证 ===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	GameState.level_score = 10
	GameState.complete_room()
	GameState.save_game()
	var f := FileAccess.open("user://fate_save.json", FileAccess.READ)
	var txt := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	print("[QA5] save contains run_active=", txt.find("\"run_active\": true") >= 0,
		" run_level2=", txt.find("\"run_level\": 2") >= 0)
	GameState.load_save()
	print("[QA5] after load: run_active=", GameState.run_active, " level=", GameState.level,
		" resumable=", GameState.has_resumable_run())

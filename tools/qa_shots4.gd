extends Node
## Lead v1.3 验收：像素主菜单/走廊、PREP 双倍注对话框、新手引导、卡牌详情、力度回弹、卡球救援、结算
## 用法： & 'D:\Godot_v4.6.3-stable_win64.exe' --path 'G:\GoDot\？！珠珠！？' res://tools/qa_shots4.tscn --resolution 1280x720 --position 40,40
const OUT := "G:/GoDot/shots"
const MENU := "res://scenes/main_menu.tscn"
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
	print("[QA4] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v13_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA4] ", path)

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

func _press_button(btn: Button) -> void:
	if btn == null:
		print("[QA4] button not found!")
		return
	btn.emit_signal("pressed")

func _run() -> void:
	print("[QA4] === 像素主菜单 ===")
	var menu := (load(MENU) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.0).timeout
	await _shot("pixel_main_menu")
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA4] === 走廊 ===")
	GameState.start_new_run()
	GameState.tutorial_seen = false
	var corridor := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(corridor)
	await get_tree().create_timer(1.0).timeout
	var player = corridor.get("player")
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[0] - 120.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	await _shot("pixel_corridor")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA4] === PREP + 双倍注 + 新手引导 ===")
	GameState.start_new_run()
	GameState.tutorial_seen = false
	GameState.prepare_level(1)
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	hud = game.get("hud")
	var prep := _find_with_method(game, "open_prep")
	print("[QA4] prep=", prep, " phase=", game.get("phase"))
	await _shot("pixel_prep")
	var start_btn := _find_button(prep, "开始试炼")
	print("[QA4] start_btn=", start_btn)
	_press_button(start_btn)
	await get_tree().create_timer(0.6).timeout
	await _shot("double_dialog")
	var dbl_btn := _find_button(prep, "双倍押注")
	print("[QA4] dbl_btn=", dbl_btn)
	_press_button(dbl_btn)
	await get_tree().create_timer(1.4).timeout
	print("[QA4] after start: phase=", game.get("phase"), " double_mode=", GameState.double_mode)
	await _shot("tutorial")
	var ok_btn := _find_button(game, "知道了")
	print("[QA4] tutorial ok_btn=", ok_btn)
	_press_button(ok_btn)
	await get_tree().create_timer(0.5).timeout

	# 卡牌详情（直接调用 HUD 的详情接口）
	GameState.pending_items.append("splitcard")
	if hud != null:
		hud.call("refresh")
		if hud.has_method("_show_item_detail"):
			hud.call("_show_item_detail", "splitcard")
	await get_tree().create_timer(0.6).timeout
	await _shot("card_detail")
	if hud != null and hud.has_method("_hide_item_detail"):
		hud.call("_hide_item_detail")
	await get_tree().create_timer(0.3).timeout

	# 力度回弹：按住 0.45s 与 1.35s 各截一张，力度应不同
	print("[QA4] === 力度回弹 ===")
	var pos := Vector2(1244.0, 676.0)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await get_tree().create_timer(0.45).timeout
	var launcher = game.get("launcher")
	print("[QA4] charge@0.45=", launcher.get("_charge") if launcher != null else "?")
	await _shot("charge_a")
	await get_tree().create_timer(0.9).timeout
	print("[QA4] charge@1.35=", launcher.get("_charge") if launcher != null else "?")
	await _shot("charge_b")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)
	await get_tree().create_timer(0.5).timeout
	await _shot("ball_flight")
	await get_tree().create_timer(2.0).timeout

	# 卡球救援：把球停住并放到最右侧，观察是否被救走
	var balls = game.get("_active_balls")
	if balls is Array and balls.size() > 0:
		var b = balls[0]
		if b != null and is_instance_valid(b):
			b.linear_velocity = Vector2.ZERO
			b.global_position = Vector2(1205.0, 300.0)
			var before: Vector2 = b.global_position
			await get_tree().create_timer(2.2).timeout
			var after: Vector2 = b.global_position if is_instance_valid(b) else Vector2(-1, -1)
			print("[QA4] stuck test before=", before, " after=", after)
			await _shot("stuck_rescue")
	else:
		print("[QA4] no active ball for stuck test")

	await get_tree().create_timer(0.5).timeout
	GameState.set_double_mode(false)
	if game != null and is_instance_valid(game):
		var summary := GameState.fail_room()
		game.call("_show_result", false, summary)
		await get_tree().create_timer(1.2).timeout
		await _shot("pixel_result_defeat")

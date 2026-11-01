extends Node
## Lead v1.2 验收：走廊+行囊、PREP 两阶段、PLAY（错落立柱/随机框/卡牌/轨迹）、结算带出
## 用法： & 'D:\Godot_v4.6.3-stable_win64.exe' --path 'G:\GoDot\？！珠珠！？' res://tools/qa_shots3.tscn --resolution 1280x720 --position 40,40
const OUT := "G:/GoDot/shots"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"
const META := "res://scenes/ui/meta_panel.tscn"

var _n := 0
var game: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.25
	await get_tree().process_frame
	await _run()
	print("[QA3] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v12_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA3] ", path)

func _find_child_with_method(root: Node, method: String) -> Node:
	for child in root.get_children():
		if child is CanvasLayer:
			for sub in child.get_children():
				if sub.has_method(method):
					return sub
	return null

func _press_spring(charge: float) -> void:
	var pos := Vector2(1244.0, 676.0)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await get_tree().create_timer(charge).timeout
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)

func _wait_settle(max_wait: float) -> bool:
	var t := 0.0
	while t < max_wait:
		await get_tree().create_timer(0.15).timeout
		t += 0.15
		if game == null or not is_instance_valid(game):
			return false
		var balls = game.get("_active_balls")
		if balls is Array and balls.is_empty():
			return true
	return false

func _run() -> void:
	print("[QA3] === 走廊 + 行囊 ===")
	GameState.start_new_run()
	# 演示行囊内容
	GameState.meta_balls_normal = 4
	GameState.meta_balls_advanced = 1
	GameState.meta_cards.assign(["splitcard", "powercard", "masscard"])
	var corridor := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(corridor)
	await get_tree().create_timer(1.2).timeout
	var player = corridor.get("player")
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[0] - 120.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	await _shot("corridor_with_bag")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var meta := (load(META) as PackedScene).instantiate()
	add_child(meta)
	await get_tree().create_timer(0.6).timeout
	meta.call("open_panel")
	await get_tree().create_timer(0.8).timeout
	await _shot("meta_panel")
	# 勾选一张卡 + 2 普通珠
	GameState.toggle_selected_card("splitcard")
	GameState.select_meta_balls(false, 1)
	GameState.select_meta_balls(false, 1)
	GameState.select_meta_balls(true, 1)
	await get_tree().create_timer(0.6).timeout
	await _shot("meta_selected")
	meta.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA3] === PREP（商店 + 查看牌组）===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	print("[QA3] pockets A: ", str(GameState.slot_configs))
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	var prep := _find_child_with_method(game, "open_prep")
	print("[QA3] prep=", prep, " phase=", game.get("phase"))
	await _shot("prep_shop_and_deck")
	# 买一张分裂卡
	GameState.buy_item("splitcard")
	await get_tree().create_timer(0.5).timeout
	await _shot("prep_after_buy")

	print("[QA3] === 开始试炼 → PLAY ===")
	if prep != null:
		prep.emit_signal("start_pressed")
	await get_tree().create_timer(1.2).timeout
	print("[QA3] phase=", game.get("phase"), " pockets=", str(GameState.slot_configs))
	var board = game.get("board")
	if board != null:
		var counts := [0, 0, 0, 0, 0]
		for peg in board.pegs:
			var t := int(peg.get("peg_type"))
			if t >= 0 and t < counts.size():
				counts[t] += 1
		print("[QA3] peg counts normal/yellow/green/black/white = ", str(counts))
	# 给前 3 颗弹珠绑卡，便于 HUD 展示
	GameState.set_ball_card(0, "powercard")
	GameState.set_ball_card(1, "masscard")
	GameState.set_ball_card(2, "shrinkcard")
	if game.get("hud") != null:
		game.get("hud").call("refresh")
	await get_tree().create_timer(0.5).timeout
	await _shot("play_staggered_board")

	# 蓄力轨迹预判
	var pos := Vector2(1244.0, 676.0)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await get_tree().create_timer(0.6).timeout
	await _shot("charging_trajectory")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)
	await get_tree().create_timer(0.45).timeout
	await _shot("ball_flight")
	await _wait_settle(24.0)
	await get_tree().create_timer(1.5).timeout
	await _shot("after_first_ball")
	print("[QA3] after ball1: score=", GameState.level_score, " balls_left=", GameState.balls_left,
		" pockets=", str(GameState.slot_configs))

	# 结算（带出局外）
	if game != null and is_instance_valid(game):
		var summary := GameState.fail_room()
		game.call("_show_result", false, summary)
		await get_tree().create_timer(1.2).timeout
		await _shot("result_defeat_carried")
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# 胜利结算
	GameState.start_new_run()
	GameState.prepare_level(3)
	GameState.total_score = 137
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var prep2 := _find_child_with_method(game, "open_prep")
	if prep2 != null:
		prep2.emit_signal("start_pressed")
	await get_tree().create_timer(1.0).timeout
	var vic := GameState.finish_run(true)
	game.call("_show_result", true, vic)
	await get_tree().create_timer(1.2).timeout
	await _shot("result_victory_carried")

extends Node
## Lead v1.1 验收：走廊 → P1 商店/道具/弹珠库 → 右侧弹簧发射 → 槽位飘分 → 失败/胜利结算（真实渲染截图）
## 用法： & 'D:\Godot_v4.6.3-stable_win64.exe' --path 'G:\GoDot\？！珠珠！？' res://tools/qa_shots2.tscn --resolution 1280x720 --position 40,40
const OUT := "G:/GoDot/shots"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"

var _n := 0
var corridor: Node = null
var game: Node = null
var hud: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.3
	await get_tree().process_frame
	await _run()
	print("[QA2] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v11_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA2] ", path)

func _find_hud(root: Node) -> Node:
	for child in root.get_children():
		if child is CanvasLayer:
			for sub in child.get_children():
				if sub.has_method("set_phase") and sub.has_signal("shop_closed"):
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

func _wait_ball_settle(max_wait: float) -> bool:
	var t := 0.0
	while t < max_wait:
		await get_tree().create_timer(0.15).timeout
		t += 0.15
		if game == null or not is_instance_valid(game):
			return false
		if game.get("active_ball") == null:
			return true
	return false

func _make_corridor(level: int) -> Node:
	GameState.level = level
	var c := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(c)
	return c

func _run() -> void:
	print("[QA2] === 走廊 ===")
	GameState.start_new_run()
	corridor = _make_corridor(1)
	await get_tree().create_timer(1.2).timeout
	await _shot("corridor_start")
	var player = corridor.get("player")
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[0] - 90.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("corridor_room1_door")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 进度：第 1 间已通过、第 2 间当前
	corridor = _make_corridor(2)
	await get_tree().create_timer(1.0).timeout
	player = corridor.get("player")
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[0] + 120.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	await _shot("corridor_room1_cleared")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA2] === 进入房间（P1 商店）===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	GameState.fate_event["target_delta"] = 0  # 让目标稳定为 25，便于截图与受控失败
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	hud = _find_hud(game)
	print("[QA2] hud=", hud, " balls=", GameState.balls_total, " target=", GameState.get_target())
	await _shot("shop_p1_layout")

	# 演示：待用道具 + 弹珠库 + 一颗灯被增益（红）
	GameState.pending_items.append("reflector")
	GameState.pending_items.append("powercard")
	GameState.library_normal = 3
	GameState.library_advanced = 1
	GameState.buff_ball_slot(0)
	if hud != null:
		hud.call("refresh")
	await get_tree().create_timer(0.5).timeout
	await _shot("items_library_filled")

	# 装备拖到立柱（模拟 HUD 的 equip_requested）
	var peg_world := FateConfig.PEG_AREA.position + FateConfig.PEG_AREA.size * 0.5
	game.call("_on_equip_requested", "reflector", peg_world)
	await get_tree().create_timer(0.4).timeout
	await _shot("equip_to_peg")

	# 关闭商店 → 发射
	if hud != null:
		hud.emit_signal("shop_closed")
	await get_tree().create_timer(1.0).timeout
	await _shot("play_ready")

	print("[QA2] === 发射 1 颗弹珠（受控失败演示）===")
	for i in 1:
		await _press_spring(0.45)
		await get_tree().create_timer(0.35).timeout
		await _shot("ball_%d_flight" % (i + 1))
		var settled := await _wait_ball_settle(16.0)
		print("[QA2] ball ", i + 1, " settled=", settled, " level_score=", GameState.level_score,
			" left=", GameState.balls_left, " total=", GameState.total_score)
		await _shot("ball_%d_after" % (i + 1))
		if game == null or not is_instance_valid(game):
			break
		if int(game.get("phase")) != 1:
			break

	# 受控失败 → 结算面板（不触发切场景）
	if game != null and is_instance_valid(game):
		game.call("_on_run_failed")
		await get_tree().create_timer(1.5).timeout
		await _shot("result_defeat")
		game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# 胜利结算面板
	GameState.start_new_run()
	GameState.prepare_level(3)
	GameState.total_score = 128
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout
	var summary := GameState.finish_run(true)
	game.call("_show_result", true, summary)
	await get_tree().create_timer(1.2).timeout
	await _shot("result_victory")

extends Node
## Lead v1.8 验收：交互按钮触摸/三按钮同一矩形/隐藏第10关不外显 + 解锁后显示 + 进度文案
const OUT := "G:/GoDot/shots"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"
var _n := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await _run()
	print("[QA9] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	img.save_png("%s/v18_%02d_%s.png" % [OUT, _n, name])
	print("[QA9] ", name)

func _tap(pos: Vector2) -> void:
	var d := InputEventScreenTouch.new(); d.index = 0; d.position = pos; d.pressed = true
	Input.parse_input_event(d)
	await get_tree().create_timer(0.05).timeout
	var u := InputEventScreenTouch.new(); u.index = 0; u.position = pos; u.pressed = false
	Input.parse_input_event(u)

func _find_text(root: Node, sub: String) -> Node:
	for ch in root.get_children():
		if ch is Label and String(ch.text).find(sub) >= 0:
			return ch
	for ch in root.get_children():
		var r := _find_text(ch, sub)
		if r != null:
			return r
	return null

func _run() -> void:
	print("[QA9] === 未拥有命源：隐藏第10关 ===")
	GameState.start_new_run()
	GameState.library_high = 0
	GameState.meta_balls_high = 0
	GameState.selected_balls_high = 0
	GameState.level = 5
	GameState.save_game()
	print("[QA9] visible_max=", GameState.visible_max_level(), " has_source=", GameState.has_source_ball())
	var c := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(c)
	await get_tree().create_timer(1.2).timeout
	var npcs = c.get("_npcs")
	print("[QA9] npc_count=", npcs.size(), " door9=", c.call("get_door_state", 9), " door4=", c.call("get_door_state", 4))
	await _shot("locked_corridor_9_doors")
	# 靠近当前 NPC，用真实 ScreenTouch 点交互按钮
	var p = c.get("player")
	var npc = c.get_npc_position(GameState.level - 1)
	p.position = Vector2(npc.x + 30.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	var ib: Button = c.get("_interact_btn")
	var eb: Button = c.get("_enter_btn")
	var db: Button = c.get("_dialog_enter_btn")
	print("[QA9] rects interact=", ib.get_global_rect(), " enter=", eb.get_global_rect(), " dialog_enter=", db.get_global_rect())
	print("[QA9] positions_equal=", ib.position == eb.position and ib.size == eb.size and db.position == eb.position and db.size == eb.size)
	var center := ib.get_global_rect().get_center()
	await _tap(center)
	await get_tree().create_timer(0.8).timeout
	print("[QA9] dialog_state_after_touch=", c.get("_dialog_state"))
	await _shot("touch_opens_dialog")
	c.queue_free()
	await get_tree().process_frame

	print("[QA9] === 拥有命源：解锁第10关 ===")
	GameState.start_new_run()
	GameState.library_high = 1
	GameState.level = 10
	GameState.save_game()
	print("[QA9] visible_max=", GameState.visible_max_level(), " has_source=", GameState.has_source_ball(), " display=", GameState.level_display())
	c = (load(CORRIDOR) as PackedScene).instantiate()
	add_child(c)
	await get_tree().create_timer(1.2).timeout
	print("[QA9] unlocked npc_count=", c.get("_npcs").size(), " door9=", c.call("get_door_state", 9))
	await _shot("unlocked_corridor_10_doors")
	c.queue_free()
	await get_tree().process_frame

	print("[QA9] === 进度文案 locked / unlocked ===")
	GameState.start_new_run()
	GameState.library_high = 0
	GameState.level = 5
	GameState.prepare_level(5)
	var g := (load(GAME) as PackedScene).instantiate()
	add_child(g)
	await get_tree().create_timer(1.2).timeout
	var t1 := _find_text(g, "第 5")
	print("[QA9] locked prep label=", t1.text if t1 != null else "?")
	await _shot("prep_locked_level_text")
	g.queue_free()
	await get_tree().process_frame

	GameState.start_new_run()
	GameState.library_high = 1
	GameState.level = 10
	GameState.prepare_level(10)
	g = (load(GAME) as PackedScene).instantiate()
	add_child(g)
	await get_tree().create_timer(1.2).timeout
	var t2 := _find_text(g, "第 10")
	print("[QA9] unlocked prep label=", t2.text if t2 != null else "?")
	await _shot("prep_unlocked_level_text")
	g.queue_free()
	await get_tree().process_frame

extends Node
## Lead v1.6 验收：走廊新角色/无右上块/点击角色面板/NPC W 打字机/PREP 限购与详情/失败结算/存档快照
const OUT := "G:/GoDot/shots"
const CORRIDOR := "res://scenes/corridor.tscn"
const GAME := "res://scenes/game.tscn"

var _n := 0
var corridor: Node = null
var game: Node = null
var hud: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.2
	await get_tree().process_frame
	await _run()
	print("[QA7] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v16_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA7] ", path)

func _find_button(root: Node, text_substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(text_substr) >= 0:
			return child
	for child in root.get_children():
		var r := _find_button(child, text_substr)
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
		print("[QA7] button not found")
		return
	btn.emit_signal("pressed")

func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _click_at(screen_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = screen_pos
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = screen_pos
	up.pressed = false
	Input.parse_input_event(up)

func _run() -> void:
	print("[QA7] === 走廊：新角色 / 无右上块 / 点击角色面板 / NPC 对话 ===")
	GameState.start_new_run()
	GameState.level = 2
	corridor = (load(CORRIDOR) as PackedScene).instantiate()
	add_child(corridor)
	await get_tree().create_timer(1.2).timeout
	var player = corridor.get("player")
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[1] - FateConfig.CORRIDOR_NPC_OFFSET + 120.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.6).timeout
	await _shot("corridor_new_char")

	# 点击主角 → 角色面板（在 NPC 对话之前）
	if player != null:
		var screen_pos: Vector2 = get_viewport().get_canvas_transform() * (player.position + Vector2(0, -30))
		print("[QA7] click player at ", screen_pos)
		_click_at(screen_pos)
	await get_tree().create_timer(1.0).timeout
	var panel := _find_with_method(corridor, "open_panel")
	print("[QA7] character panel=", panel)
	await _shot("character_panel_cutout")
	if panel != null:
		_press(_find_button(panel, "弹珠"))
		await get_tree().create_timer(0.5).timeout
		await _shot("panel_balls_three")
		_press(_find_button(panel, "卡牌"))
		await get_tree().create_timer(0.5).timeout
		await _shot("panel_cards")
		_press(_find_button(panel, "关闭"))
		await get_tree().create_timer(0.6).timeout

	# 靠近当前关 NPC → W 对话
	if player != null:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[1] - FateConfig.CORRIDOR_NPC_OFFSET + 30.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(0.8).timeout
	_key(KEY_W, true)
	_key(KEY_W, false)
	await get_tree().create_timer(1.0).timeout
	await _shot("npc_typewriter")
	_click_at(Vector2(640, 400))
	await get_tree().create_timer(0.6).timeout
	await _shot("npc_text_full")
	_click_at(Vector2(640, 400))
	await get_tree().create_timer(0.6).timeout
	var enter_btn := _find_button(corridor, "进入试炼")
	print("[QA7] enter_btn=", enter_btn, " npc_seen=", GameState.is_npc_seen(2))
	await _shot("npc_enter_button")
	corridor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA7] === PREP 限购 / 详情 / 失败结算 ===")
	GameState.start_new_run()
	GameState.level = 3
	GameState.prepare_level(3)
	game = (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	hud = game.get("hud")
	var prep := _find_with_method(game, "open_prep")
	await _shot("prep_v16")
	var offers := GameState.roll_shop_offers()
	var first_id := offers[0] if offers.size() > 0 else "shrinkcard"
	var b1 := GameState.buy_item(first_id)
	var b2 := GameState.buy_item(first_id)
	print("[QA7] buy first=", b1, " second=", b2, " id=", first_id)
	await get_tree().create_timer(0.5).timeout
	await _shot("prep_bought_once")

	var start_btn := _find_button(prep, "开始试炼")
	_press(start_btn)
	await get_tree().create_timer(0.6).timeout
	_press(_find_button(prep, "稳妥开局"))
	await get_tree().create_timer(1.2).timeout
	print("[QA7] phase=", game.get("phase"))
	await _shot("play_v16")
	if hud != null:
		if hud.has_method("_show_item_detail"):
			hud.call("_show_item_detail", "shrinkcard")
		await get_tree().create_timer(0.6).timeout
		await _shot("detail_item_lore")
		if hud.has_method("_hide_item_detail"):
			hud.call("_hide_item_detail")
		await get_tree().create_timer(0.3).timeout
		if hud.has_method("_show_ball_detail"):
			hud.call("_show_ball_detail", 1)
		await get_tree().create_timer(0.6).timeout
		await _shot("detail_ball_info")
		if hud.has_method("_hide_item_detail"):
			hud.call("_hide_item_detail")
		await get_tree().create_timer(0.3).timeout

	var summary := GameState.fail_room()
	print("[QA7] fail summary keys=", summary.keys(), " level_score=", summary.get("level_score", -1))
	game.call("_show_result", false, summary)
	await get_tree().create_timer(1.2).timeout
	await _shot("result_fail_v16")
	var cp := _find_button(game, "返回上一存档点")
	print("[QA7] checkpoint button=", cp, " disabled=", cp.disabled if cp != null else "?")
	game.queue_free()
	await get_tree().process_frame

	print("[QA7] === 存档点/资源快照验证 ===")
	GameState.start_new_run()
	GameState.prepare_level(1)
	GameState.mark_checkpoint(FateConfig.CHECKPOINT_SHOP)
	var coins_before := GameState.coins
	GameState.buy_item("shrinkcard")
	print("[QA7] coins before=", coins_before, " after buy=", GameState.coins)
	GameState.save_game()
	GameState.load_save()
	print("[QA7] after reload coins=", GameState.coins, " (expect ", coins_before, ") checkpoint=", GameState.checkpoint)

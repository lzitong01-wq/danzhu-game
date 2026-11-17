extends Node
## Lead v1.5 验收：简洁独游主菜单（虚化星空/无脸主角/五项）、设置/关于、走廊按钮与NPC黑屏白字、角色面板三页、等级
## 用法： & 'D:\Godot_v4.6.3-stable_win64.exe' --path 'G:\GoDot\？！珠珠！？' res://tools/qa_shots6.tscn --resolution 1280x720 --position 40,40
const OUT := "G:/GoDot/shots"
const MENU := "res://scenes/main_menu.tscn"
const CORRIDOR := "res://scenes/corridor.tscn"

var _n := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.time_scale = 1.2
	await get_tree().process_frame
	await _run()
	print("[QA6] done")
	get_tree().quit(0)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_n += 1
	var path := "%s/v15_%02d_%s.png" % [OUT, _n, name]
	img.save_png(path)
	print("[QA6] ", path)

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
		print("[QA6] button not found")
		return
	btn.emit_signal("pressed")

func _run() -> void:
	print("[QA6] === 主菜单（无存档）===")
	GameState.run_active = false
	GameState.save_game()
	var menu := (load(MENU) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.2).timeout
	await _shot("menu_no_save")
	_press(_find_button(menu, "设置"))
	await get_tree().create_timer(0.5).timeout
	await _shot("menu_settings")
	menu.queue_free()
	await get_tree().process_frame

	print("[QA6] === 主菜单（有存档 + 关于我们）===")
	GameState.start_new_run()
	GameState.level = 3
	GameState.add_character_exp(180)
	GameState.save_game()
	menu = (load(MENU) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(1.2).timeout
	await _shot("menu_with_save")
	_press(_find_button(menu, "关于我们"))
	await get_tree().create_timer(0.5).timeout
	await _shot("menu_about")
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	print("[QA6] === 走廊按钮/NPC 黑屏白字 ===")
	GameState.start_new_run()
	GameState.level = 2
	var corridor := (load(CORRIDOR) as PackedScene).instantiate()
	add_child(corridor)
	await get_tree().create_timer(1.2).timeout
	var menu_btn := _find_button(corridor, "主菜单")
	var icon_btn := _find_button(corridor, "")
	print("[QA6] corridor menu_btn=", menu_btn, " canvas buttons ok")
	await _shot("corridor_top_ui")
	var player = corridor.get("player")
	if player != null and FateConfig.CORRIDOR_DOOR_X.size() > 1:
		player.position = Vector2(FateConfig.CORRIDOR_DOOR_X[1] - FateConfig.CORRIDOR_NPC_OFFSET + 20.0, FateConfig.CORRIDOR_FLOOR_Y - 40.0)
	await get_tree().create_timer(1.0).timeout
	await _shot("npc_blackout_story")
	await get_tree().create_timer(4.2).timeout
	await _shot("npc_after_story")
	print("[QA6] npc_seen_level2=", GameState.is_npc_seen(2))

	print("[QA6] === 角色/行囊面板 ===")
	if corridor.has_method("_open_meta_panel"):
		corridor.call("_open_meta_panel")
	await get_tree().create_timer(1.0).timeout
	await _shot("character_info")
	# 找到面板
	var panel := _find_with_method(corridor, "open_panel")
	print("[QA6] panel=", panel)
	if panel != null:
		_press(_find_button(panel, "弹珠"))
		await get_tree().create_timer(0.5).timeout
		await _shot("character_balls")
		_press(_find_button(panel, "卡牌"))
		await get_tree().create_timer(0.5).timeout
		await _shot("character_cards")
		_press(_find_button(panel, "关闭"))
		await get_tree().create_timer(0.6).timeout
	corridor.queue_free()
	await get_tree().process_frame

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

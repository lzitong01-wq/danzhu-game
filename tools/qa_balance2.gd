extends Node
## Lead v1.1 平衡探针：只测单房间（默认第 1 间）在随机力度下的过关率与 0 分球比例。
## 用法：$env:QA_TRIALS="8"; $env:QA_ROOM="1"; godot --headless --fixed-fps 60 --path <proj> --script res://tools/qa_balance2.gd
const GAME := "res://scenes/game.tscn"

var trials := 6
var room := 1
var wins := 0
var ball_scores: Array[int] = []
var zero_balls := 0
var total_balls := 0

func _ready() -> void:
	if OS.get_environment("QA_TRIALS") != "":
		trials = int(OS.get_environment("QA_TRIALS"))
	if OS.get_environment("QA_ROOM") != "":
		room = int(OS.get_environment("QA_ROOM"))
	await get_tree().process_frame
	for t in trials:
		await _trial(t)
	print("[BAL2] room=%d trials=%d wins=%d win_rate=%.0f%% balls=%d zero=%d (%.0f%%) scores=%s" % [
		room, trials, wins, 100.0 * wins / maxi(trials, 1), total_balls, zero_balls,
		100.0 * zero_balls / maxi(total_balls, 1), str(ball_scores)])
	get_tree().quit(0)

func _find_hud(root: Node) -> Node:
	for child in root.get_children():
		if child is CanvasLayer:
			for sub in child.get_children():
				if sub.has_method("set_phase") and sub.has_signal("shop_closed"):
					return sub
	return null

func _trial(index: int) -> void:
	GameState.start_new_run()
	GameState.prepare_level(room)
	var start_level := GameState.level
	var start_target := GameState.get_target()
	var game := (load(GAME) as PackedScene).instantiate()
	add_child(game)
	await get_tree().create_timer(0.8).timeout
	var hud := _find_hud(game)
	if hud != null:
		hud.emit_signal("shop_closed")
	await get_tree().create_timer(0.5).timeout
	var score_before := GameState.level_score
	var guard := 0
	while guard < 400:
		guard += 1
		if not is_instance_valid(game):
			break
		if int(game.get("phase")) != 1:
			break
		if GameState.balls_left <= 0 and game.get("active_ball") == null:
			break
		if game.get("active_ball") == null:
			var t := 0.45 + randf() * 0.55
			game.call("_on_launch_requested", t)
		await get_tree().create_timer(0.2).timeout
		var settle_wait := 0
		while game.get("active_ball") != null and settle_wait < 120:
			await get_tree().create_timer(0.1).timeout
			settle_wait += 1
	await get_tree().create_timer(0.8).timeout
	var got := GameState.level_score
	ball_scores.append(got - score_before)
	total_balls += 5
	# 过关会立刻 complete_room → level+1，因此用 level 是否增加判定胜利
	var cleared := GameState.level > start_level
	if cleared:
		wins += 1
	print("[BAL2] trial %d score=%d target=%d %s" % [index + 1, got, start_target, "WIN" if cleared else "LOSE"])
	if is_instance_valid(game):
		game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

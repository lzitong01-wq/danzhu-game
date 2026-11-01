extends SceneTree
## 临时工具：在真实项目环境中编译检查 gameplay / corridor 脚本（Autoload 已注册）。
## 说明：godot --check-only --script 不会注册 Autoload，因此 GameState/Audio 会误报；
## 本脚本以 SceneTree 启动，Autoload 已注册，可以真实编译各脚本。

func _initialize() -> void:
	print("autoload GameState=", root.has_node("GameState"), " Audio=", root.has_node("Audio"))
	var scripts: Array = [
		"res://scripts/gameplay/fx.gd",
		"res://scripts/gameplay/px.gd",
		"res://scripts/gameplay/peg.gd",
		"res://scripts/gameplay/slot.gd",
		"res://scripts/gameplay/guardian.gd",
		"res://scripts/gameplay/ball.gd",
		"res://scripts/gameplay/launcher.gd",
		"res://scripts/gameplay/board.gd",
		"res://scripts/gameplay/hud_fallback.gd",
		"res://scripts/gameplay/result_fallback.gd",
		"res://scripts/gameplay/game.gd",
		"res://scripts/gameplay/_flow_test.gd",
		"res://scripts/corridor/player.gd",
		"res://scripts/corridor/joystick.gd",
		"res://scripts/corridor/meta_fallback.gd",
		"res://scripts/corridor/corridor.gd",
	]
	var failed := 0
	for path in scripts:
		var res = load(String(path))
		if res == null:
			print("FAIL ", path)
			failed += 1
		else:
			print("OK   ", path)
	print("RESULT failed=", failed)
	quit(1 if failed > 0 else 0)

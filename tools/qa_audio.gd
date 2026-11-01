extends SceneTree
## 音频资源导入自检：加载全部 BGM/SFX，打印时长、循环标记与错误。
## 用法： godot --headless --path <proj> --script res://tools/qa_audio.gd

const BGM := [
	"res://assets/audio/bgm/bgm_menu.ogg",
	"res://assets/audio/bgm/bgm_battle.ogg",
	"res://assets/audio/bgm/bgm_shop.ogg",
	"res://assets/audio/bgm/bgm_victory.ogg",
	"res://assets/audio/bgm/bgm_defeat.ogg",
]
const SFX := [
	"res://assets/audio/sfx/sfx_launch.wav",
	"res://assets/audio/sfx/sfx_peg.wav",
	"res://assets/audio/sfx/sfx_peg_yellow.wav",
	"res://assets/audio/sfx/sfx_peg_green.wav",
	"res://assets/audio/sfx/sfx_slot.wav",
	"res://assets/audio/sfx/sfx_void.wav",
	"res://assets/audio/sfx/sfx_coin.wav",
	"res://assets/audio/sfx/sfx_buy.wav",
	"res://assets/audio/sfx/sfx_click.wav",
	"res://assets/audio/sfx/sfx_guardian.wav",
	"res://assets/audio/sfx/sfx_crack.wav",
	"res://assets/audio/sfx/sfx_win.wav",
	"res://assets/audio/sfx/sfx_lose.wav",
]

func _init() -> void:
	var failed := 0
	for p in BGM:
		if not ResourceLoader.exists(p):
			print("[AUDIO] MISSING ", p)
			failed += 1
			continue
		var s = load(p)
		if s == null or not (s is AudioStream):
			print("[AUDIO] BAD ", p)
			failed += 1
			continue
		print("[AUDIO] BGM ok %-40s len=%.2fs" % [p.get_file(), s.get_length()])
	for p in SFX:
		if not ResourceLoader.exists(p):
			print("[AUDIO] MISSING ", p)
			failed += 1
			continue
		var s = load(p)
		if s == null or not (s is AudioStream):
			print("[AUDIO] BAD ", p)
			failed += 1
			continue
		print("[AUDIO] SFX ok %-30s len=%.2fs" % [p.get_file(), s.get_length()])
	print("[AUDIO] failed=", failed)
	quit(0 if failed == 0 else 1)
